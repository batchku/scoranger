import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import Foundation
import GoogleSignIn

/// The account, and the only place in the app that brings Firebase up.
///
/// design/FIREBASE.md §0.2 and §9.1. Principle 1: *"LOCAL-FIRST; cloud
/// OPTIONAL; no login should ever gate using the app."*
///
/// **`FirebaseApp.configure()` is called here, at first sign-in, and nowhere
/// else.** Not at launch, not in `ScorangerApp`, not lazily from the first
/// Firestore read. A signed-out install makes no Firebase contact of any kind:
/// no anonymous auth, no App Check handshake, no configuration call. That is
/// the difference between a promise and an intention, and
/// `check_signed_out.py` asserts that no other file calls it.
///
/// Anonymous auth is deliberately not used as the signed-out state (§9.1). It
/// would create a server-side identity for somebody who declined to have one,
/// put a round trip in first launch, and leave an orphan account behind for
/// everyone who tried the app once.
@MainActor
final class SignIn: ObservableObject {

    /// What the reader is, as far as the account goes.
    enum State: Equatable {
        /// The default, and a complete way to use this app forever.
        case signedOut
        case working
        case signedIn(Account)
        /// Sign-in was attempted and did not finish. The library is untouched.
        case failed(String)
    }

    struct Account: Equatable {
        let uid: String
        /// Absent when the person used Apple's Hide My Email, which hands us a
        /// relay address. §12.10: an invitation cannot find them by an address
        /// their bandmates know, so a code is the fallback.
        let email: String?
        let displayName: String?
        /// Which button they pressed. Kept because the two providers behave
        /// differently at invitation time, not for display.
        let provider: Provider
    }

    enum Provider: String, Equatable {
        case google = "google.com"
        case apple = "apple.com"
    }

    @Published private(set) var state: State = .signedOut

    /// The account, if there is one. Nil is the ordinary case and not a fault.
    var account: Account? {
        if case .signedIn(let account) = state { return account }
        return nil
    }

    /// Whether this build can sign in at all.
    ///
    /// False when `GoogleService-Info.plist` was not baked in -- a checkout
    /// without one still builds and runs, because the signed-out app is the
    /// whole app minus sharing. The account screen says so rather than
    /// offering a button that cannot work.
    var isAvailable: Bool {
        Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
    }

    /// Brought up once, on demand. `FirebaseApp.configure()` traps if called
    /// twice, and the second sign-in in a session would do exactly that.
    private func startFirebaseIfNeeded() throws {
        guard FirebaseApp.app() == nil else { return }
        guard isAvailable else { throw SignInError.notConfigured }
        FirebaseApp.configure()
    }

    enum SignInError: LocalizedError {
        case notConfigured
        case noIdentityToken
        case cancelled

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "This build has no Firebase configuration, so signing in "
                     + "is unavailable. Everything else works."
            case .noIdentityToken:
                return "That sign-in did not return an identity."
            case .cancelled:
                return "Sign-in cancelled."
            }
        }
    }

    // MARK: - Google

    func signInWithGoogle(presenting: UIViewController) async {
        state = .working
        do {
            try startFirebaseIfNeeded()
            try configureGoogleIfNeeded()
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting)
            guard let idToken = result.user.idToken?.tokenString else {
                throw SignInError.noIdentityToken
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
            try await finish(with: credential, provider: .google)
        } catch {
            state = .failed(readable(error))
        }
    }

    /// Give GoogleSignIn its client id before asking it to do anything.
    ///
    /// **This is what crashed 0.7.0 build 183 on the first tap.**
    /// `GIDSignIn.sharedInstance.signIn(withPresenting:)` requires a
    /// configuration, and with none it raises an OBJECTIVE-C NSException --
    /// "No active configuration" -- which SIGABRTs the process.
    ///
    /// The part worth remembering: the `do/catch` around that call could never
    /// have helped. An NSException is not a Swift `Error`, so `catch` does not
    /// see it and there is no way to contain it after the fact. The only fix is
    /// to satisfy the precondition, which is why this is a separate function
    /// with a name that says so rather than a line inside the flow.
    ///
    /// Firebase has already parsed `GoogleService-Info.plist` by this point and
    /// exposes its `CLIENT_ID` as `options.clientID`, so the id comes from the
    /// one file that is the source of truth for which project this build talks
    /// to -- not from a second copy in `Info.plist` that could disagree with it.
    private func configureGoogleIfNeeded() throws {
        if GIDSignIn.sharedInstance.configuration != nil { return }
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw SignInError.notConfigured
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    // MARK: - Apple

    /// Apple's flow needs a nonce, and it needs it hashed on the way out and
    /// raw on the way back: Apple signs the SHA256 of what we send, and
    /// Firebase verifies the signature against the raw value. Sending the same
    /// string to both is the mistake that makes this fail with an unhelpful
    /// credential error.
    private var appleNonce: String?

    /// The value to put on Apple's request: the HASH. The raw one is kept
    /// here for Firebase to verify against, and the two must not be swapped.
    func prepareAppleNonce() -> String {
        let nonce = Self.randomNonce()
        appleNonce = nonce
        return Self.sha256(nonce)
    }

    /// Whether this build can do Apple sign-in at all.
    ///
    /// Read from the running app's OWN ENTITLEMENTS, not from a constant.
    /// Ali's report was "Sign in with Apple does nothing", and the cause was
    /// that `com.apple.developer.applesignin` is absent -- the capability was
    /// never enabled on the App ID (verified: it carries only GAME_CENTER and
    /// IN_APP_PURCHASE), so the entitlement cannot be in the profile, so
    /// `ASAuthorizationController` fails immediately.
    ///
    /// Asking the binary rather than hardcoding `false` means this button
    /// starts working the moment the capability is enabled and a profile is
    /// regenerated, with no code change and nothing to remember. A constant
    /// would be a second fact to keep in step with the App ID, and it would be
    /// wrong in whichever direction nobody updated.
    /// Read from the app's own `embedded.mobileprovision`, which is the only
    /// way to see one's entitlements on iOS. `SecTaskCopyValueForEntitlement`
    /// is the obvious answer and it is macOS-only -- it does not link here,
    /// which the compiler says plainly and which is why this reads a file
    /// instead.
    ///
    /// The profile is a CMS blob with an XML plist inside it. Slicing the
    /// plist out by its own delimiters is the standard approach and needs no
    /// crypto: the signature is not being verified here, only read, and a
    /// forged profile is not a threat model for deciding whether to enable a
    /// button in the owner's own build.
    ///
    /// Absent profile -- a simulator build, say -- reads as unavailable, which
    /// is the safe direction: the button is disabled with a reason rather than
    /// live and silent.
    static var appleEntitlementIsPresent: Bool {
        guard let url = Bundle.main.url(forResource: "embedded",
                                        withExtension: "mobileprovision"),
              let raw = try? Data(contentsOf: url),
              let text = String(data: raw, encoding: .isoLatin1),
              let start = text.range(of: "<plist"),
              let end = text.range(of: "</plist>")
        else { return false }
        let plist = String(text[start.lowerBound..<end.upperBound])
        guard let data = plist.data(using: .isoLatin1),
              let parsed = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
              let entitlements = parsed["Entitlements"] as? [String: Any]
        else { return false }
        return entitlements["com.apple.developer.applesignin"] != nil
    }

    var appleIsAvailable: Bool { Self.appleEntitlementIsPresent }

    /// Apple's flow, driven by this app's own button.
    ///
    /// `SignInWithAppleButton` used to own this, and it brought two problems.
    /// Its geometry could not be made to match the Google button (Ali's second
    /// report), and its `onCompletion` failure branch was written to swallow
    /// cancellation -- which meant it swallowed EVERY error, including the one
    /// that was actually happening. A tap did nothing and said nothing.
    ///
    /// Here, cancellation is the only thing that stays quiet, and it is
    /// identified by its code rather than by being the default.
    func signInWithApple() async {
        guard appleIsAvailable else {
            state = .failed("Sign in with Apple is not enabled for this build.")
            return
        }
        state = .working
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        // Apple signs the SHA256 of what we send and Firebase verifies the RAW
        // value, so the pair is prepared in one place and only the hash goes out.
        request.nonce = prepareAppleNonce()

        do {
            let authorization = try await AppleRequest.run(request)
            await completeApple(authorization)
        } catch let error as ASAuthorizationError where error.code == .canceled {
            // The one silence that is correct: they changed their mind.
            state = .signedOut
        } catch {
            state = .failed(readable(error))
        }
    }

    func completeApple(_ authorization: ASAuthorization) async {
        state = .working
        do {
            try startFirebaseIfNeeded()
            guard let credential = authorization.credential
                    as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = appleNonce else {
                throw SignInError.noIdentityToken
            }
            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: idToken, rawNonce: nonce,
                fullName: credential.fullName)
            try await finish(with: firebaseCredential, provider: .apple)
        } catch {
            state = .failed(readable(error))
        }
        appleNonce = nil
    }

    // MARK: - both

    /// One account for one person, whichever button they pressed.
    ///
    /// If somebody signs in with Google and later with Apple, Firebase would
    /// hand them two uids and therefore two libraries. Where it can tell the
    /// two are the same person -- a verified address that matches -- the second
    /// credential is LINKED to the first account instead. Where it cannot,
    /// because Hide My Email gave a relay address, they really are two
    /// accounts and nothing here can honestly merge them (§0.4).
    private func finish(with credential: AuthCredential, provider: Provider) async throws {
        do {
            let result = try await Auth.auth().signIn(with: credential)
            state = .signedIn(account(from: result.user, provider: provider))
        } catch let error as NSError
                    where error.code == AuthErrorCode.accountExistsWithDifferentCredential.rawValue {
            // The address is already an account under the other provider. Sign
            // in as that account and attach this credential to it, so the
            // library the person already has is the one they get back.
            guard let current = Auth.auth().currentUser else { throw error }
            let linked = try await current.link(with: credential)
            state = .signedIn(account(from: linked.user, provider: provider))
        }
    }

    private func account(from user: User, provider: Provider) -> Account {
        Account(uid: user.uid,
                // A relay address is not an address anybody can invite, so it
                // is carried as nil rather than as something that looks usable.
                email: user.email.flatMap { $0.hasSuffix("privaterelay.appleid.com") ? nil : $0 },
                displayName: user.displayName,
                provider: provider)
    }

    /// Signing out keeps everything. The library is local and stays local
    /// (§9.2), and the confirmation says so in those words.
    func signOut() {
        if FirebaseApp.app() != nil { try? Auth.auth().signOut() }
        GIDSignIn.sharedInstance.signOut()
        state = .signedOut
    }

    private func readable(_ error: Error) -> String {
        if let signInError = error as? SignInError {
            return signInError.errorDescription ?? "Sign-in failed."
        }
        let nsError = error as NSError
        // The reader pressed cancel. Not a failure to report as one.
        if nsError.domain == ASAuthorizationError.errorDomain
            && nsError.code == ASAuthorizationError.canceled.rawValue {
            return SignInError.cancelled.errorDescription ?? ""
        }
        if nsError.domain == kGIDSignInErrorDomain
            && nsError.code == GIDSignInError.canceled.rawValue {
            return SignInError.cancelled.errorDescription ?? ""
        }
        return nsError.localizedDescription
    }

    // MARK: - the nonce

    static func randomNonce(length: Int = 32) -> String {
        // Apple requires a nonce; a predictable one would let a captured token
        // be replayed against this app.
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
