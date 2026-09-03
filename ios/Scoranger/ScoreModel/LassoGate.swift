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

    /// How long a STAND-IN finger must have been down before it may draw.
    ///
    /// Zero for a real Pencil, which is why this is not part of the rule above:
    /// a Pencil cannot pan, so a Pencil drag has exactly one meaning and there
    /// is nothing to wait for.
    ///
    /// The stand-in is a different animal. To it, a finger about to pinch and a
    /// finger about to select are the same touch -- and a pinch's first finger
    /// MOVES before its second one lands. A lasso starting there cancelled that
    /// touch out of the scroll view's pinch, so under the stand-in the canvas
    /// could not be zoomed at all: the suite could prove a selection or prove a
    /// zoom, never both in one test, which is exactly what a pair of pictures
    /// at two zooms needs.
    ///
    /// A tenth of a second separates them cleanly. Every lasso in the suite
    /// presses for 0.6s before it drags; a synthesised pinch's fingers are
    /// moving within a frame or two of landing.
    static let standInHold: TimeInterval = 0.1

    static func standInMayDraw(heldFor: TimeInterval) -> Bool {
        heldFor >= standInHold
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

    // MARK: - Telling a deliberate modifier finger from the resting palm
    //
    // Approved for 0.3.0 (finger-held = add to selection). The rule is stated
    // and tested here, and the numbers it depends on are printed in the touch
    // diagnostics, so the thresholds can be set from real measurements off
    // Ali's hand rather than guessed. NOTHING READS IT YET -- 0.2.6 still
    // ignores fingers entirely while the Pencil is down, which is what makes
    // Pencil selection work at all.

    /// Above this contact width a touch is a palm, not a fingertip.
    ///
    /// STILL PROVISIONAL, and widened from 18 after Ali could not make the add
    /// work at all. 18 was too strict in the direction that hurts: a firm
    /// fingertip reports 15-20pt on this hardware, so a deliberate press could
    /// be read as a palm, while a real resting hand is broader still. The two
    /// errors are not equal -- calling a palm a finger only makes a lasso add
    /// when it should replace, which the user sees and can undo, whereas
    /// calling a finger a palm makes the feature appear not to exist.
    static let palmRadius: CGFloat = 26

    /// Nearer than this to the Pencil tip, a contact is the hand holding the
    /// Pencil. The modifier finger is the OTHER hand and lands well away.
    /// PROVISIONAL, widened from 160 for the same reason: a finger held near
    /// the passage being lassoed is closer to the tip than a whole arm's reach.
    static let modifierMinDistance: CGFloat = 110

    /// Is this finger a deliberate "add to the selection" modifier?
    ///
    /// Both signals are required, because either alone is wrong: a palm can
    /// land far from the tip when the hand is turned, and a fingertip of the
    /// Pencil hand can rest close to it. Small AND far is the combination that
    /// only the other hand produces.
    static func isDeliberateModifierFinger(radius: CGFloat,
                                           distanceFromPencil: CGFloat) -> Bool {
        radius < palmRadius && distanceFromPencil >= modifierMinDistance
    }

    /// Two fingers down, gone again, having barely moved: undo the last stroke.
    /// A tap has no movement, so it can never be read as a pinch.
    ///
    /// `inkCanvasLive` is which OWNER the tap belongs to, and it is here rather
    /// than at the call site because having two owners is the whole defect. The
    /// live ink canvas carries its own two-finger recogniser and declares
    /// `cancelsTouchesInView = false`, so it must not cancel the score's pinch
    /// -- which means the same tap also arrives at the lasso overlay. Both
    /// called undo, and one tap took off two strokes.
    static func isUndoTap(touches: Int, movement: CGFloat, elapsed: TimeInterval,
                          inkCanvasLive: Bool = false) -> Bool {
        guard !inkCanvasLive else { return false }
        return touches == 2 && movement <= moveSlop && elapsed <= tapWindow
    }

    // MARK: - What a Pencil touchdown does to the selection already on the page

    /// What happens to the existing selection the moment the Pencil lands.
    enum Landing: Equatable {
        /// Nothing was being held: this is a fresh selection, so the old one
        /// goes NOW rather than when the stroke finishes. Watching the previous
        /// highlight sit there through a whole new lasso read as the app having
        /// missed the gesture.
        case replaceNow
        /// A finger of the other hand is down: this lasso adds to what is
        /// already selected.
        case addToExisting
        /// Markup mode: the Pencil is a pen and the selection is not its
        /// business.
        case leaveAlone
    }

    /// Decided at touchdown, from state alone -- no timer, no threshold, no
    /// waiting. Ali's requirement was explicit: put the finger down and the
    /// Pencil straight after, and it must already be an add.
    static func landing(isPencil: Bool, markupActive: Bool,
                        modifierFingerDown: Bool) -> Landing {
        guard isPencil, !markupActive else { return .leaveAlone }
        return modifierFingerDown ? .addToExisting : .replaceNow
    }

    // MARK: - Bar selection by tapping empty space

    /// What a Pencil tap on a page means, by how many taps.
    enum Tap: Equatable {
        /// One: drop the element under it, if it is selected.
        case dropElement
        /// Two, on empty space in a bar: select that bar, on that staff.
        case selectBar
        /// Three: select that bar across every staff.
        case selectBarAllStaves
    }

    static func tap(count: Int) -> Tap {
        switch count {
        case 1:  return .dropElement
        case 2:  return .selectBar
        default: return .selectBarAllStaves
        }
    }

    /// What a single Pencil tap means when a finger is being held.
    ///
    /// Ali held a finger and TAPPED, and nothing happened -- correctly, by the
    /// old rule: a plain tap drops the element under it, and there was nothing
    /// selected to drop. But holding a finger says "add", and the tap says
    /// which element, so the two together are a clear instruction and should be
    /// obeyed. Adding one at a time is also the natural way to build a chord up.
    enum TapWithFinger: Equatable { case addElement, dropElement }

    static func singleTap(modifierFingerDown: Bool) -> TapWithFinger {
        modifierFingerDown ? .addElement : .dropElement
    }
}
