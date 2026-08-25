import CoreGraphics
import Foundation

/// What a touch on the score means.
///
///  | annotation | what is touching  | what happens               |
///  |------------|-------------------|----------------------------|
///  | off        | Pencil, dragging  | lasso selection, at once   |
///  | off        | Pencil, tapped    | drop that element          |
///  | on         | Pencil            | ink                        |
///  | either     | fingers           | pan and zoom, nothing else |
///
/// The split is by instrument, not by gesture: the Pencil selects, the hand
/// moves the paper. Nothing has to be disambiguated, because a Pencil cannot
/// pan and a finger cannot select -- which is why the lasso needs no hold, no
/// modifier finger, and no timer.
///
/// Two earlier schemes are gone. `LassoArbiter` wanted a finger held while the
/// Pencil drew, and could only be tested through a stand-in. The hold-then-drag
/// finger lasso that replaced it could be tested, but it never worked on a real
/// iPad: outside markup mode the PencilKit canvas takes no touches, so its palm
/// rejection is not running and a hand resting beside the Pencil arrives as an
/// ordinary direct touch -- which the one-touch gate read as a second finger.
enum LassoGate {
    /// How far a touch may wander and still count as standing still. Used for
    /// the two-finger undo tap, which must not fire on a pinch.
    static let moveSlop: CGFloat = 14

    /// A tap is quick. Longer than this and two fingers on the page are the
    /// start of something else.
    static let tapWindow: TimeInterval = 0.4

    /// Does this touch begin a lasso?
    ///
    /// Only the Pencil, only outside markup mode, and immediately -- there is
    /// nothing for a hold to disambiguate. In markup mode the Pencil is a pen
    /// and must not be claimed: the recognizer cancels touches in the views
    /// below it, so claiming a Pencil stroke there would delete the ink as it
    /// was drawn.
    static func lassoBegins(isPencil: Bool, markupActive: Bool) -> Bool {
        isPencil && !markupActive
    }

    /// A finger never selects. It pans and zooms, in either mode.
    static func fingerSelects() -> Bool { false }

    /// May the canvas pan or zoom right now?
    ///
    /// No, while a Pencil is down to select: the hand holding the iPad rests on
    /// the glass beside the Pencil, and a page sliding under the stroke would
    /// make the selection land on whatever drifted beneath it. This is the palm
    /// rejection PencilKit would be doing if it were the one taking the touches.
    static func canvasMayMove(pencilDown: Bool, markupActive: Bool) -> Bool {
        !(pencilDown && !markupActive)
    }

    /// Two fingers down, gone again, having barely moved: undo the last stroke.
    /// A tap has no movement, so it can never be read as a pinch.
    static func isUndoTap(touches: Int, movement: CGFloat, elapsed: TimeInterval) -> Bool {
        touches == 2 && movement <= moveSlop && elapsed <= tapWindow
    }
}
