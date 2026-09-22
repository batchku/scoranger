import AuthenticationServices
import FirebaseAuth
import FirebaseCore
import FirebaseFunctions
import Foundation

/// Deleting the account, from inside the app.
///
/// Apple's App Review guideline 5.1.1(v): an app that supports account
/// creation must support account deletion. Scoranger has Sign in with Apple
/// and Google sign-in, so it has accounts, and signing out is not deletion.
///
/// **Two halves, and the order matters.**
///
/// 1. SIGN IN WITH APPLE MUST HAVE ITS TOKEN REVOKED, not merely its record
///    removed. Apple checks for it. Revocation needs an `authorizationCode`,
///    which only comes back from a fresh `ASAuthorizationController` run on
///    the device -- there is no server-side way to obtain one -- so the app
///    re-authenticates, hands the code to
///    `Auth.revokeToken(withAuthorizationCode:)`, and Firebase calls Apple's
///    revocation endpoint with it. This is why revocation is HERE and not in
///    the Cloud Function.
///
///    The re-authentication is also what clears `requiresRecentLogin`, the
///    error a long-signed-in account would otherwise hit.
///
/// 2. EVERYTHING ELSE IS THE `deleteAccount` FUNCTION, and it has to be
///    (design/FIREBASE.md §6.6). A client walking its own set lists to promote
///    successors would need write access to membership maps, which §4.4
///    refuses it outright -- `memberships/` is `allow write: if false`. And it
///    has to run to completion: a client killed halfway leaves set lists owned
///    by an account that no longer exists.
///
/// The Function deletes the Firebase Auth user as its last act, so there is
/// nothing left here to delete afterwards -- only local state to drop.
///
/// **The library on this iPad is not touched, and cannot be from here.**
/// Scoranger is local-first; the music never left the device. See
/// `AccountDeletionPlan.keepsLocalLibrary`, which is the sentence the reader
/// is shown.
@MainActor
enum AccountDeletion {

    /// What the Function reported doing, relayed to the screen.
    struct Report: Equatable {
        let handedOn: Int
        let destroyed: Int
        let left: Int
        /// Anything the Function could not finish -- bytes it could not
        /// delete, most likely. Surfaced rather than swallowed: the account is
        /// gone either way, and a person told "done" about a job that was not
        /// has been lied to.
        let incomplete: [String]
    }

    enum Trouble: LocalizedError {
        case notSignedIn
        case notConfigured
        case cancelled
        /// Apple returned an authorization, and no code in it. Without a code
        /// there is no revocation, and going ahead would delete the record
        /// while leaving the token live -- the exact thing 5.1.1(v) forbids.
        case noAppleAuthorizationCode

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "There is no account signed in on this iPad."
            case .notConfigured:
                // Reachable only when the signed-in state is local and
                // Firebase was never brought up -- a build with no
                // configuration, or `-pretendSignedIn`. It must not read as
                // success: NOTHING was deleted.
                return "This session has no connection to your account, so "
                     + "nothing was deleted. Sign in again and try."
            case .cancelled:
                return "Account deletion cancelled."
            case .noAppleAuthorizationCode:
                return "Apple did not return the code needed to hand your "
                     + "sign-in back. Nothing was deleted — try again."
            }
        }
    }

    /// Delete it. Throws rather than reporting failure quietly, because the
    /// caller has to know whether to keep the reader signed in.
    ///
    /// `reauthenticateApple` is a seam for tests, not a policy: the real flow
    /// always re-authenticates an Apple account.
    static func deleteAccount(
        provider: SignIn.Provider,
        reauthenticateApple: () async throws -> ASAuthorization = Self.runAppleReauthentication
    ) async throws -> Report {
        guard FirebaseApp.app() != nil else { throw Trouble.notConfigured }
        guard Auth.auth().currentUser != nil else { throw Trouble.notSignedIn }

        // FIRST, and only for Apple. Doing it after the Function would be
        // doing it after the Auth user is gone, and there would be no account
        // left to revoke a token for.
        if provider == .apple {
            let authorization = try await reauthenticateApple()
            guard let credential = authorization.credential
                    as? ASAuthorizationAppleIDCredential,
                  let codeData = credential.authorizationCode,
                  let code = String(data: codeData, encoding: .utf8) else {
                throw Trouble.noAppleAuthorizationCode
            }
            try await Auth.auth().revokeToken(withAuthorizationCode: code)
        }

        let result = try await Functions.functions(region: "us-west1")
            .httpsCallable("deleteAccount").call([:])
        return report(from: result.data)
    }

    /// Ask Apple again, for a fresh authorization code.
    ///
    /// The same nonce discipline as signing in -- Apple signs the SHA256 of
    /// what is sent -- because this is a full authorization request and not a
    /// lookup. `AppleRequest` is the same controller wrapper the sign-in
    /// button uses, so a cancel here is a cancel there.
    private static func runAppleReauthentication() async throws -> ASAuthorization {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = SignIn.sha256(SignIn.randomNonce())
        do {
            return try await AppleRequest.run(request)
        } catch let error as ASAuthorizationError where error.code == .canceled {
            throw Trouble.cancelled
        }
    }

    /// Read the Function's summary. Shapes rather than a decoder, because the
    /// callable hands back `Any` and a missing field must read as "none of
    /// those" rather than as a failure to delete an account that is gone.
    static func report(from data: Any?) -> Report {
        let dictionary = data as? [String: Any] ?? [:]
        return Report(
            handedOn: (dictionary["handedOver"] as? [Any])?.count ?? 0,
            destroyed: (dictionary["emptied"] as? [Any])?.count ?? 0,
            left: (dictionary["left"] as? [Any])?.count ?? 0,
            incomplete: (dictionary["incomplete"] as? [Any])?
                .compactMap { $0 as? String } ?? [])
    }
}
