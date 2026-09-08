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

    // MARK: - Apple

    /// Apple's flow needs a nonce, and it needs it hashed on the way out and
    /// raw on the way back: Apple signs the SHA256 of what we send, and
    /// Firebase verifies the signature against the raw value. Sending the same
    /// string to both is the mistake that makes this fail with an unhelpful
    /// credential error.
    private var appleNonce: String?

    func appleRequest() -> ASAuthorizationAppleIDRequest {
        let nonce = Self.randomNonce()
        appleNonce = nonce
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
        return request
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
