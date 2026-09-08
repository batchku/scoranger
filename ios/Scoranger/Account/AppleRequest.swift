import AuthenticationServices
import UIKit

/// `ASAuthorizationController`, as one `await`.
///
/// The controller is delegate-based and holds neither itself nor its delegate,
/// so the naive bridge -- make both, call `performRequests()`, return -- lets
/// ARC free them before Apple's sheet answers, and the continuation is never
/// resumed. The `await` then hangs for ever, which looks exactly like the bug
/// this file exists to fix: a tap that does nothing.
///
/// So the bridge keeps itself alive in `inFlight` until it has resumed, and
/// resumes exactly once.
final class AppleRequest: NSObject, ASAuthorizationControllerDelegate,
                          ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    /// The strong reference that outlives the call. Cleared on resume.
    private static var inFlight: AppleRequest?

    static func run(_ request: ASAuthorizationRequest) async throws -> ASAuthorization {
        let bridge = AppleRequest()
        inFlight = bridge
        return try await withCheckedThrowingContinuation { continuation in
            bridge.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = bridge
            controller.presentationContextProvider = bridge
            controller.performRequests()
        }
    }

    /// Resuming a continuation twice traps, and both delegate methods can
    /// arrive in odd orders on a cancelled sheet -- so this is the only place
    /// either of them resumes.
    private func settle(_ result: Result<ASAuthorization, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        Self.inFlight = nil
        continuation.resume(with: result)
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        settle(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        settle(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController)
        -> ASPresentationAnchor {
        // The key window of the ACTIVE scene. `UIApplication.windows` is gone,
        // and picking the first scene picks the wrong one on an iPad with two
        // windows open -- which is the device Ali reported from (iPad17,3).
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let window = scenes.first { $0.activationState == .foregroundActive }?
            .keyWindow ?? scenes.first?.keyWindow
        return window ?? ASPresentationAnchor()
    }
}
