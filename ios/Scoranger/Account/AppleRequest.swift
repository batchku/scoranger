import AuthenticationServices
import UIKit

/// `ASAuthorizationController`, as one `await` that cannot hang.
///
/// **THE BUG THIS FILE IS NOW SHAPED AROUND.** The first version retained the
/// delegate and let the CONTROLLER die. `delegate` and
/// `presentationContextProvider` are weak references *from* the controller, so
/// keeping the bridge alive kept the wrong object: `controller` was a local,
/// ARC released it when the closure returned, and the request was abandoned
/// before Apple could answer. Neither delegate method fired, the continuation
/// never resumed, and Settings read "Signing in…" for ever -- on a simulator
/// and, because the cause is ownership rather than environment, on a device
/// too.
///
/// So the controller is a stored property, and the bridge holds itself in
/// `inFlight` until it has resolved. Both halves are needed: the controller
/// keeps the request alive, and `inFlight` keeps the delegate alive to receive
/// it.
///
/// The other half of the shape is that IT CANNOT HANG SILENTLY. Every exit --
/// success, failure, no window, or nothing at all for `patience` -- goes
/// through `settle`, which resolves the continuation exactly once. A tap now
/// always produces either a sheet or a sentence.
final class AppleRequest: NSObject, ASAuthorizationControllerDelegate,
                          ASAuthorizationControllerPresentationContextProviding {

    /// How long to wait for Apple before calling it a failure.
    ///
    /// Overridable for tests only: a UI test cannot wait out the real value,
    /// and the error path is the thing worth asserting.
    static var patience: TimeInterval = {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-appleSignInPatience"),
           i + 1 < args.count, let seconds = Double(args[i + 1]) {
            return seconds
        }
        return 20
    }()

    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    /// THE RETENTION FIX. Weakly referenced by nothing else; without this the
    /// request is collected before it completes.
    private var controller: ASAuthorizationController?
    /// Keeps the delegate alive across the request. Cleared by `settle`.
    private static var inFlight: AppleRequest?

    static func run(_ request: ASAuthorizationRequest) async throws -> ASAuthorization {
        let bridge = AppleRequest()
        inFlight = bridge
        return try await withCheckedThrowingContinuation { continuation in
            bridge.continuation = continuation

            // Test-only: prove the visible error path without needing an
            // Apple ID, which no simulator has and no test may type.
            if ProcessInfo.processInfo.arguments.contains("-failAppleSignIn") {
                bridge.settle(.failure(Trouble.tookTooLong))
                return
            }

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = bridge
            controller.presentationContextProvider = bridge
            bridge.controller = controller
            bridge.armTimeout()
            controller.performRequests()
        }
    }

    /// A plain timer rather than a racing task.
    ///
    /// The previous attempt raced `Task.sleep` against the request in a task
    /// group and did not fire -- and chasing why was the wrong move, because a
    /// timeout that has to be reasoned about is not a safety net. This one
    /// resolves the SAME continuation through the SAME `settle`, on the main
    /// queue, and is cancelled by whichever answer arrives first.
    private var timeout: DispatchWorkItem?

    private func armTimeout() {
        let work = DispatchWorkItem { [weak self] in
            self?.settle(.failure(Trouble.tookTooLong))
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.patience, execute: work)
    }

    /// The ONE exit. Resuming a continuation twice traps, and both delegate
    /// methods plus the timeout can arrive in any order, so nothing else may
    /// resume it.
    private func settle(_ result: Result<ASAuthorization, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        controller = nil
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
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        // The key window of the ACTIVE scene: picking the first scene picks
        // the wrong one on an iPad with two windows open.
        let window = scenes.first { $0.activationState == .foregroundActive }?
            .keyWindow ?? scenes.first?.keyWindow
        if let window { return window }
        // NOT a bare `ASPresentationAnchor()`. A fresh UIWindow belongs to no
        // scene, so the sheet is presented into nothing: nothing is drawn and
        // no delegate method is ever called. Resolving here turns an invisible
        // dead end into a sentence.
        settle(.failure(Trouble.noWindow))
        return ASPresentationAnchor()
    }

    enum Trouble: LocalizedError {
        /// Apple never answered. Not a refusal: the remedy is to try again.
        case tookTooLong
        case noWindow

        var errorDescription: String? {
            switch self {
            case .tookTooLong:
                return "Apple did not respond. Check your connection and try again."
            case .noWindow:
                return "Could not open the Apple sign-in sheet. Try again."
            }
        }
    }
}
