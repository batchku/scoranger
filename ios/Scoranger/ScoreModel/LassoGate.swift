import CoreGraphics
import Foundation

/// What a touch on the score means.
///
///  | what is touching                      | what happens          |
///  |---------------------------------------|-----------------------|
///  | one finger, moving                    | scroll                |
///  | one finger, held still, then dragging | lasso                 |
///  | one finger parked + another dragging  | lasso, adding         |
///  | two fingers moving                    | pinch / zoom          |
///  | two fingers tapped                    | undo the last stroke  |
///  | Pencil, markup on                     | ink                   |
///  | Pencil, markup off                    | lasso (held first)    |
///
/// This replaces `LassoArbiter`, whose rule was "hold a finger and draw with
/// the Pencil". That rule could not be driven by a test: the simulator has no
/// Pencil, so a launch argument let a finger pretend to be one and the tests
/// exercised the pretence rather than the gesture. Everything here is
/// something a finger can actually do, so the tests do what a person does.
enum LassoGate {
    /// How long a finger must rest before a drag means "select" rather than
    /// "scroll". Below about 0.3s a hesitant scroll turns into a lasso; above
    /// about 0.45s selecting feels stuck.
    static let holdThreshold: TimeInterval = 0.35

    /// How far a touch may wander and still count as held. A finger resting on
    /// glass is never perfectly still.
    static let moveSlop: CGFloat = 14

    /// A tap is quick. Longer than this and two fingers resting on the page are
    /// the start of something else.
    static let tapWindow: TimeInterval = 0.4

    /// Does a single touch, held this long and moved this far, start a lasso?
    ///
    /// Note what this does NOT do: make scrolling wait. The scroll view's pan
    /// is never asked to fail first, so a drag that starts moving scrolls
    /// immediately. A finger held still produces no pan movement, so when the
    /// threshold passes there is nothing scrolled to undo and nothing jumps.
    static func shouldBeginLasso(elapsed: TimeInterval,
                                 movement: CGFloat,
                                 touches: Int) -> Bool {
        touches == 1 && elapsed >= holdThreshold && movement <= moveSlop
    }

    /// With two fingers down, what is the user doing?
    enum Combine: Equatable {
        /// One finger parked, the other drawing: add to the selection.
        case add
        /// Both moving: zoom.
        case pinch
        /// Neither has moved enough to say. Wait rather than guess — deciding
        /// early is how a pinch becomes a stray selection.
        case undecided
    }

    static func combine(firstMovement: CGFloat, secondMovement: CGFloat) -> Combine {
        let firstParked = firstMovement <= moveSlop
        let secondMoving = secondMovement > moveSlop
        if firstParked && secondMoving { return .add }
        if firstMovement > moveSlop || secondMovement > moveSlop { return .pinch }
        return .undecided
    }

    /// Two fingers down, gone again, having barely moved: undo the last stroke.
    /// A tap has no movement, so it can never be read as a pinch.
    static func isUndoTap(touches: Int, movement: CGFloat, elapsed: TimeInterval) -> Bool {
        touches == 2 && movement <= moveSlop && elapsed <= tapWindow
    }

    /// Markup mode changes what the PENCIL does, and nothing else. A finger
    /// hold-then-drag lassos in either mode.
    static func pencilLassos(markupActive: Bool) -> Bool { !markupActive }
}
