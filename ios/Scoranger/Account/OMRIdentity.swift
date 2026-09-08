import FirebaseAuth
import FirebaseCore
import Foundation

/// Whose OMR job this is.
///
/// The owner's requirement: *"I want PER-USER tracking of OMR costs"* -- no
/// cap, but each conversion attributable to a user
/// (design/FIREBASE.md §0.12). The service verifies a Firebase ID token
/// against Google's public certificates and logs the resulting uid against
/// every job, so the app's part is simply to send one when there is one.
///
/// **It lives in `Account/` because Firebase does, and that is enforced.**
/// `check_signed_out.py` refuses `Auth.auth()` anywhere else -- those calls
/// TRAP when no `FirebaseApp` has been configured, and nothing configures it
/// until somebody presses a sign-in button. `AppState` therefore cannot ask
/// this question directly; it holds a closure, installed from here, and gets
/// nil until an account exists.
///
/// Nil is the ordinary answer and not a failure. Importing a scanned PDF is a
/// signed-out feature and principle 1 says no login may gate using the app, so
/// a signed-out job goes up on the shared key and the service labels it
/// `unattributed`. There is no user to attribute it to.
enum OMRIdentity {

    /// A fresh ID token, or nil when nobody is signed in.
    ///
    /// `forcingRefresh: false` -- the SDK hands back its cached token and
    /// refreshes only inside the last five minutes of its hour. Forcing a
    /// refresh per job would add a network round trip to every import for no
    /// benefit; the service's own clock skew tolerance covers the rest.
    static func token() async -> String? {
        guard FirebaseApp.app() != nil, let user = Auth.auth().currentUser else {
            return nil
        }
        do {
            return try await user.getIDToken(forcingRefresh: false)
        } catch {
            // A token that cannot be minted is not a reason to fail the
            // import. The job goes up unattributed, which is honest, rather
            // than the reader losing a conversion to an auth problem they
            // cannot see or fix.
            return nil
        }
    }

    /// Hand `AppState` the ability to ask, without letting it import Firebase.
    ///
    /// Called once, from the sign-in surface. Before that -- and forever, for a
    /// reader who never signs in -- `AppState.omrToken` stays nil.
    @MainActor
    static func install(into state: AppState) {
        state.omrToken = { await token() }
    }
}
