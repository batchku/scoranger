import Foundation

/// Selection is a *combined* gesture: hold a finger on the page and draw with
/// the Pencil. Nothing is toggled, and nothing else changes meaning.
///
///  | what is touching        | what happens          |
///  |-------------------------|-----------------------|
///  | Pencil, no finger       | annotation, as before |
///  | finger held + Pencil    | lasso selection       |
///  | one finger, no Pencil   | scroll                |
///  | two fingers             | pinch / pan           |
///
/// The rule is small enough to state in one line and to test on its own, which
/// is what `LassoArbiter` is for — the recognizer below only supplies it with
/// what is currently touching the glass.
struct LassoArbiter {
    /// Direct (finger) touches currently down.
    var fingers: Int = 0
    /// Set while a Pencil touch is down.
    var pencilDown: Bool = false
    /// Test hook: with no Pencil in the simulator, a finger has to stand in for
    /// one. Enabled by `-lassoWithFinger`, never in a shipped run.
    var fingerStandsInForPencil: Bool = false
    /// Whether markup mode is on. Only the stand-in cares: the real gesture
    /// distinguishes a lasso from annotation by the held finger, but under the
    /// hook both are "a finger drawing", so markup keeps the finger.
    var annotationActive: Bool = false

    /// Does a touch beginning right now start a lasso?
    ///
    /// The stand-in deliberately keeps the two-finger case out: letting one
    /// finger draw is enough to exercise the path, and claiming the first
    /// finger of a pinch would cancel the zoom — the hook would then be
    /// breaking the behaviour it exists to check.
    func shouldBeginLasso(pencil: Bool) -> Bool {
        if fingerStandsInForPencil {
            return !annotationActive && !pencil && fingers == 1
        }
        // the finger has to be there first: it is the modifier
        return pencil && fingers > 0
    }
}
