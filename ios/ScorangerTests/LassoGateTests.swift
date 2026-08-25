import CoreGraphics
import XCTest

/// The rules that decide what a touch on the score means.
///
/// The whole model is: the Pencil selects, the hand moves the paper. These
/// tests exist because two previous schemes passed in a simulator and failed on
/// a real iPad, and because the rules are worth stating somewhere a person can
/// read them without a device in their hand.
final class LassoGateTests: XCTestCase {

    // MARK: - Only the Pencil selects

    func testThePencilLassosImmediatelyWhenMarkupIsOff() {
        XCTAssertTrue(LassoGate.lassoBegins(isPencil: true, markupActive: false))
    }

    func testThePencilIsAPenWhileMarkupIsOn() {
        // the recognizer cancels touches in the views below it, so claiming a
        // Pencil stroke here would delete the ink as it was being drawn
        XCTAssertFalse(LassoGate.lassoBegins(isPencil: true, markupActive: true))
    }

    func testAFingerNeverLassos() {
        XCTAssertFalse(LassoGate.lassoBegins(isPencil: false, markupActive: false),
                       "fingers pan and zoom; they do not select")
        XCTAssertFalse(LassoGate.lassoBegins(isPencil: false, markupActive: true))
        XCTAssertFalse(LassoGate.fingerSelects())
    }

    /// There is no hold, no threshold, and no timer left to starve. The 0.2.3
    /// selection bug was a `Timer.scheduledTimer` that never fired because
    /// UIKit runs the loop in tracking mode while a touch is down on a scroll
    /// view; the rule that needed it is gone.
    func testNothingAboutSelectionDependsOnTiming() {
        // the same answer however long the Pencil has been down: there is
        // nothing to disambiguate, because a Pencil cannot pan
        XCTAssertTrue(LassoGate.lassoBegins(isPencil: true, markupActive: false))
    }

    // MARK: - Palm rejection: the canvas holds still under the Pencil

    /// This is the bug that survived two shipped builds. Outside markup mode
    /// the PencilKit canvas takes no touches, so ITS palm rejection is not
    /// running and the hand resting beside the Pencil reaches the scroll view
    /// as an ordinary finger. Nothing may move the page while the Pencil is
    /// down, or the lasso lands on music that drifted underneath it.
    func testTheCanvasIsFrozenWhileThePencilSelects() {
        XCTAssertFalse(LassoGate.canvasMayMove(pencilDown: true, markupActive: false))
    }

    func testFingersPanAndZoomFreelyWithNoPencilDown() {
        XCTAssertTrue(LassoGate.canvasMayMove(pencilDown: false, markupActive: false))
        XCTAssertTrue(LassoGate.canvasMayMove(pencilDown: false, markupActive: true))
    }

    /// In markup mode the Pencil is drawing, and PencilKit IS taking the
    /// touches — so it rejects the palm itself, and two fingers may still pan
    /// the page to reach the next system while the Pencil rests on it.
    func testTheCanvasStillMovesWhileThePencilIsDrawingInk() {
        XCTAssertTrue(LassoGate.canvasMayMove(pencilDown: true, markupActive: true))
    }

    // MARK: - Telling a deliberate modifier finger from the resting palm
    //
    // The rule 0.3.0's finger-add will run on. Ali approved the approach:
    // contact size AND distance from the Pencil tip, both required. The
    // thresholds are provisional until he reports real numbers off the
    // diagnostics readout — these tests pin the SHAPE of the rule, which is
    // what must not drift, and use offsets from the constants so that
    // retuning a threshold does not silently invert a case.

    func testASmallContactFarFromThePencilIsTheOtherHand() {
        XCTAssertTrue(LassoGate.isDeliberateModifierFinger(
            radius: LassoGate.palmRadius - 8,
            distanceFromPencil: LassoGate.modifierMinDistance + 100))
    }

    func testABroadContactIsAPalmEvenFarFromThePencil() {
        // a hand turned sideways rests well away from the tip and is still
        // a palm -- which is why distance alone will not do
        XCTAssertFalse(LassoGate.isDeliberateModifierFinger(
            radius: LassoGate.palmRadius + 6,
            distanceFromPencil: LassoGate.modifierMinDistance + 200))
    }

    func testAFingertipBesideThePencilIsTheHandHoldingIt() {
        // and why size alone will not do either
        XCTAssertFalse(LassoGate.isDeliberateModifierFinger(
            radius: LassoGate.palmRadius - 8,
            distanceFromPencil: LassoGate.modifierMinDistance - 60))
    }

    func testBothSignalsAreRequired() {
        XCTAssertFalse(LassoGate.isDeliberateModifierFinger(
            radius: LassoGate.palmRadius + 6,
            distanceFromPencil: LassoGate.modifierMinDistance - 60),
                       "a broad contact beside the Pencil is the clearest palm there is")
    }

    /// 0.2.6 ships the rule and the measurements and acts on NEITHER: while a
    /// Pencil is down, a lasso begins regardless of what fingers are doing.
    /// That is what makes Pencil selection work, and it must not regress while
    /// the rule waits for its numbers.
    func testAFingerDoesNotChangeWhatThePencilDoesYet() {
        XCTAssertTrue(LassoGate.lassoBegins(isPencil: true, markupActive: false))
        XCTAssertFalse(LassoGate.lassoBegins(isPencil: false, markupActive: false))
    }

    // MARK: - The two-finger undo tap

    func testATwoFingerTapIsAnUndo() {
        XCTAssertTrue(LassoGate.isUndoTap(touches: 2, movement: 3, elapsed: 0.1))
    }

    func testALongTwoFingerRestIsNotAnUndo() {
        XCTAssertFalse(LassoGate.isUndoTap(touches: 2, movement: 3, elapsed: 1.2),
                       "a tap is quick; a rest is something else")
    }

    func testATwoFingerDragIsAPinchNotAnUndo() {
        XCTAssertFalse(LassoGate.isUndoTap(touches: 2, movement: 40, elapsed: 0.1))
    }

    func testOneFingerTapIsNotAnUndo() {
        XCTAssertFalse(LassoGate.isUndoTap(touches: 1, movement: 0, elapsed: 0.1))
    }

    func testAFingerRestingOnGlassIsAllowedALittleWander() {
        XCTAssertTrue(LassoGate.isUndoTap(touches: 2,
                                          movement: LassoGate.moveSlop - 1,
                                          elapsed: 0.1))
    }

    // MARK: - What the Pencil landing does to the selection already there (#1, #3)

    /// #1: the previous selection goes the INSTANT the Pencil touches down.
    /// Watching an old highlight sit under a new lasso until the stroke closed
    /// read as the app having missed the gesture entirely.
    func testAPencilLandingWithNoFingerHeldReplacesAtOnce() {
        XCTAssertEqual(LassoGate.landing(isPencil: true, markupActive: false,
                                         modifierFingerDown: false),
                       .replaceNow)
    }

    /// #3: a finger of the other hand already down means this stroke adds.
    /// Decided from state, so putting the finger down and the Pencil straight
    /// after works -- there is no delay to wait out.
    func testAFingerAlreadyDownMakesTheStrokeAdd() {
        XCTAssertEqual(LassoGate.landing(isPencil: true, markupActive: false,
                                         modifierFingerDown: true),
                       .addToExisting)
    }

    func testTheSelectionIsNotTouchedInMarkupMode() {
        for held in [true, false] {
            XCTAssertEqual(LassoGate.landing(isPencil: true, markupActive: true,
                                             modifierFingerDown: held),
                           .leaveAlone,
                           "drawing ink must not disturb the selection")
        }
    }

    func testAFingerLandingDoesNothingAtAll() {
        XCTAssertEqual(LassoGate.landing(isPencil: false, markupActive: false,
                                         modifierFingerDown: false),
                       .leaveAlone,
                       "a finger neither selects nor clears; it pans")
    }

    /// The regression this pairing could cause: a resting palm read as a
    /// modifier turns every lasso into an add, which looks exactly like #1
    /// being broken. The palm rule is what stands between those.
    func testAPalmDoesNotSilentlyTurnEveryLassoIntoAnAdd() {
        let palmIsModifier = LassoGate.isDeliberateModifierFinger(
            radius: LassoGate.palmRadius + 6,
            distanceFromPencil: LassoGate.modifierMinDistance - 40)
        XCTAssertFalse(palmIsModifier)
        XCTAssertEqual(LassoGate.landing(isPencil: true, markupActive: false,
                                         modifierFingerDown: palmIsModifier),
                       .replaceNow)
    }

    // MARK: - Taps (#10b)

    func testOneTapDropsAnElement() {
        XCTAssertEqual(LassoGate.tap(count: 1), .dropElement)
    }

    func testTwoTapsSelectTheBarOnThatStaff() {
        XCTAssertEqual(LassoGate.tap(count: 2), .selectBar)
    }

    func testThreeTapsSelectTheBarEverywhere() {
        XCTAssertEqual(LassoGate.tap(count: 3), .selectBarAllStaves)
    }
}
