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

    /// Has this touch already committed to scrolling?
    ///
    /// A finger that travels before the threshold is dragging the page, and
    /// must keep dragging it however long it stays down afterwards. Without
    /// this, a slow continuous drag would cross the threshold mid-scroll and
    /// turn into a lasso under the user's hand.
    static func disqualifiesLasso(elapsed: TimeInterval, movement: CGFloat) -> Bool {
        elapsed < holdThreshold && movement > moveSlop
    }

    /// The decision, made when the finger starts moving.
    ///
    /// This replaces a timer. 0.2.3 timed the hold with `Timer.scheduledTimer`,
    /// which installs into the run loop's DEFAULT mode -- and while a finger is
    /// down on a scroll view, UIKit runs the loop in TRACKING mode, where such
    /// a timer does not fire. On a real device the hold never elapsed and the
    /// lasso could not begin at all. Nothing here depends on the run loop.
    static func shouldBeginLassoOnMove(heldFor: TimeInterval,
                                       touches: Int,
                                       disqualified: Bool) -> Bool {
        touches == 1 && !disqualified && heldFor >= holdThreshold
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

    /// How a touch of this kind begins a lasso.
    enum Begin: Equatable {
        /// A Pencil outside markup: the moment it moves. It cannot be confused
        /// with a scroll, because the Pencil is not allowed to scroll.
        case immediately
        /// A finger: only after it has rested. A finger DOES scroll, and that
        /// is the only thing distinguishing the two intentions.
        case afterHold
        /// A Pencil in markup mode is a pen. Claiming it would cancel the ink.
        case never
    }

    static func lassoStart(isPencil: Bool, markupActive: Bool) -> Begin {
        guard isPencil else { return .afterHold }
        return markupActive ? .never : .immediately
    }

    /// How many touches count, given what is on the glass.
    ///
    /// A Pencil outweighs any number of resting fingers. Outside markup the
    /// PencilKit canvas takes no touches, so ITS palm rejection is not running
    /// -- a hand resting beside the Pencil arrives here as an ordinary direct
    /// touch. Requiring exactly one touch is what made Pencil selection
    /// unreachable on a real iPad while passing in a simulator that has no palm.
    static func effectiveTouchCount(fingers: Int, pencilDown: Bool) -> Int {
        pencilDown ? 1 : fingers
    }

    /// May this touch begin a lasso at all?
    ///
    /// The Pencil is a finger for selection, only steadier: outside markup mode
    /// it draws the same hold-then-drag lasso, adds the same way, and is
    /// governed by the same threshold. Inside markup mode it is a pen, and must
    /// not be claimed -- the recognizer cancels touches in the views below it,
    /// so claiming a Pencil stroke there would delete the ink as it was drawn.
    static func touchMayLasso(isPencil: Bool, markupActive: Bool) -> Bool {
        !isPencil || pencilLassos(markupActive: markupActive)
    }
}
