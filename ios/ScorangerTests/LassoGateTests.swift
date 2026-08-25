import CoreGraphics
import XCTest

/// The rules that decide whether a touch is a scroll, a lasso, a pinch or an
/// add-to-selection. They live in a plain struct so they can be stated and
/// tested without a simulator, a Pencil, or a running app — the old scheme's
/// rule could only be exercised through a stand-in that let a finger pretend to
/// be a Pencil, which meant the tests never drove what a person actually does.
final class LassoGateTests: XCTestCase {

    // MARK: - One finger: scroll unless it is held first

    func testAFingerThatMovesStraightAwayScrolls() {
        XCTAssertFalse(LassoGate.shouldBeginLasso(elapsed: 0.05, movement: 40, touches: 1),
                       "a drag that starts immediately is a scroll, not a lasso")
    }

    func testAFingerHeldStillThenDraggedLassos() {
        XCTAssertTrue(LassoGate.shouldBeginLasso(elapsed: 0.40, movement: 2, touches: 1))
    }

    func testTheHoldMustBeStillToCount() {
        // held long enough, but wandering: the user is scrolling slowly
        XCTAssertFalse(LassoGate.shouldBeginLasso(elapsed: 0.40, movement: 60, touches: 1),
                       "a finger that has already travelled is scrolling")
    }

    func testTheThresholdIsAroundATalkingThirdOfASecond() {
        // short enough not to make selection feel stuck, long enough that a
        // hesitant scroll does not become a lasso
        XCTAssertGreaterThanOrEqual(LassoGate.holdThreshold, 0.3)
        XCTAssertLessThanOrEqual(LassoGate.holdThreshold, 0.45)
    }

    func testJustUnderTheThresholdIsStillAScroll() {
        XCTAssertFalse(LassoGate.shouldBeginLasso(
            elapsed: LassoGate.holdThreshold - 0.01, movement: 0, touches: 1))
    }

    // MARK: - Two fingers: pinch, unless one of them is parked

    func testTwoFingersBothMovingIsAPinch() {
        XCTAssertEqual(LassoGate.combine(firstMovement: 30, secondMovement: 40), .pinch)
    }

    func testAParkedFingerAndADraggingOneAdds() {
        XCTAssertEqual(LassoGate.combine(firstMovement: 2, secondMovement: 45), .add)
    }

    func testTwoStillFingersAreNeitherYet() {
        // nothing has happened: waiting is the right answer, not guessing
        XCTAssertEqual(LassoGate.combine(firstMovement: 1, secondMovement: 1), .undecided)
    }

    func testTheParkedFingerIsAllowedALittleWander() {
        // a finger resting on glass is never perfectly still
        XCTAssertEqual(LassoGate.combine(firstMovement: LassoGate.moveSlop - 1,
                                         secondMovement: 60), .add)
    }

    func testNothingIsClaimedWhileBothFingersAreStillWithinTheSlop() {
        // Neither has committed, so the gate claims nothing and the scroll
        // view's pinch proceeds untouched. Deciding early is exactly how a
        // pinch turns into a stray selection.
        XCTAssertEqual(LassoGate.combine(firstMovement: 12, secondMovement: 14), .undecided)
    }

    func testOnceTheParkedFingerMovesItIsAPinch() {
        XCTAssertEqual(LassoGate.combine(firstMovement: 40, secondMovement: 45), .pinch)
    }

    // MARK: - Two fingers, no movement at all: the undo tap

    func testATwoFingerTapIsAnUndoNotAPinch() {
        XCTAssertTrue(LassoGate.isUndoTap(touches: 2, movement: 3, elapsed: 0.1))
    }

    func testALongTwoFingerRestIsNotAnUndo() {
        XCTAssertFalse(LassoGate.isUndoTap(touches: 2, movement: 3, elapsed: 1.2),
                       "a tap is quick; a rest is something else")
    }

    func testATwoFingerDragIsNotAnUndo() {
        XCTAssertFalse(LassoGate.isUndoTap(touches: 2, movement: 40, elapsed: 0.1))
    }

    func testOneFingerTapIsNotAnUndo() {
        XCTAssertFalse(LassoGate.isUndoTap(touches: 1, movement: 0, elapsed: 0.1))
    }

    // MARK: - What the Pencil does depends only on markup mode

    func testThePencilDrawsInkWhileMarkupIsOn() {
        XCTAssertFalse(LassoGate.pencilLassos(markupActive: true),
                       "in markup mode the Pencil is a pen")
    }

    func testThePencilLassosWhenMarkupIsOff() {
        XCTAssertTrue(LassoGate.pencilLassos(markupActive: false))
    }

    // MARK: - Deciding at the moment of movement, not on a timer

    /// 0.2.3 timed the hold with `Timer.scheduledTimer`, which installs into the
    /// run loop's DEFAULT mode. While a finger is down on a scroll view UIKit
    /// runs the loop in TRACKING mode, so that timer never fired on a real
    /// device and the lasso could not begin at all — with any number of fingers.
    /// The decision is made when the finger starts moving instead, which cannot
    /// be starved.

    func testAFingerThatHeldLongEnoughThenMovesLassos() {
        XCTAssertTrue(LassoGate.shouldBeginLassoOnMove(
            heldFor: 0.5, touches: 1, disqualified: false))
    }

    func testAFingerThatMovedTooSoonScrolls() {
        XCTAssertFalse(LassoGate.shouldBeginLassoOnMove(
            heldFor: 0.1, touches: 1, disqualified: false))
    }

    /// The case a plain "has it been 0.35s?" test would get wrong: someone
    /// dragging slowly from the first instant crosses the threshold while still
    /// moving. That is a scroll, and it must stay one.
    func testASlowContinuousDragNeverBecomesALasso() {
        XCTAssertTrue(LassoGate.disqualifiesLasso(elapsed: 0.2, movement: 40),
                      "movement before the threshold means the user is scrolling")
        XCTAssertFalse(LassoGate.shouldBeginLassoOnMove(
            heldFor: 0.6, touches: 1, disqualified: true),
                       "a touch that already scrolled must not turn into a lasso")
    }

    func testAWobbleWithinTheSlopDoesNotDisqualify() {
        XCTAssertFalse(LassoGate.disqualifiesLasso(elapsed: 0.2,
                                                   movement: LassoGate.moveSlop - 1))
    }

    func testMovementAfterTheThresholdNeverDisqualifies() {
        // by then the lasso has begun; moving is the whole point
        XCTAssertFalse(LassoGate.disqualifiesLasso(elapsed: 0.9, movement: 300))
    }

    func testTwoFingersDoNotStartABaseLassoOnMovement() {
        XCTAssertFalse(LassoGate.shouldBeginLassoOnMove(
            heldFor: 1.0, touches: 2, disqualified: false),
                       "two fingers are a pinch or an add, never a plain lasso")
    }

    // MARK: - The Pencil is a finger for selection, only steadier

    func testThePencilLassosLikeAFingerOutsideMarkupMode() {
        XCTAssertTrue(LassoGate.touchMayLasso(isPencil: true, markupActive: false),
                      "outside markup the Pencil selects exactly as a finger does")
    }

    func testThePencilIsLeftAloneInsideMarkupMode() {
        // the recognizer cancels touches in the views below it, so claiming a
        // Pencil stroke here would delete the ink as it was being drawn
        XCTAssertFalse(LassoGate.touchMayLasso(isPencil: true, markupActive: true))
    }

    func testAFingerLassosInEitherMode() {
        XCTAssertTrue(LassoGate.touchMayLasso(isPencil: false, markupActive: true))
        XCTAssertTrue(LassoGate.touchMayLasso(isPencil: false, markupActive: false))
    }

    // MARK: - The Pencil on real hardware

    /// Ali could not select with the Pencil on device through two builds. Three
    /// gates combined to make it unreachable, and none could be seen in a
    /// simulator that has neither a Pencil nor a palm.

    func testThePencilLassosTheMomentItMovesOutsideMarkup() {
        // it needs no hold: a Pencil cannot be confused with a scroll, because
        // the Pencil is not allowed to scroll
        XCTAssertEqual(LassoGate.lassoStart(isPencil: true, markupActive: false), .immediately)
    }

    func testAFingerStillHasToRestFirst() {
        XCTAssertEqual(LassoGate.lassoStart(isPencil: false, markupActive: false), .afterHold)
        XCTAssertEqual(LassoGate.lassoStart(isPencil: false, markupActive: true), .afterHold)
    }

    func testThePencilIsAPenInMarkupMode() {
        XCTAssertEqual(LassoGate.lassoStart(isPencil: true, markupActive: true), .never)
    }

    /// The gate that actually killed it: a hand rests on the glass beside the
    /// Pencil, and outside markup mode PencilKit is not there to reject it.
    func testARestingPalmDoesNotStopThePencil() {
        XCTAssertEqual(LassoGate.effectiveTouchCount(fingers: 1, pencilDown: true), 1,
                       "a palm beside the Pencil must not count as a second touch")
        XCTAssertEqual(LassoGate.effectiveTouchCount(fingers: 3, pencilDown: true), 1,
                       "nor a whole hand")
    }

    func testFingersCountNormallyWhenThereIsNoPencil() {
        XCTAssertEqual(LassoGate.effectiveTouchCount(fingers: 1, pencilDown: false), 1)
        XCTAssertEqual(LassoGate.effectiveTouchCount(fingers: 2, pencilDown: false), 2)
    }

    func testAPencilWithAPalmStillPassesTheMovementGate() {
        // one effective touch, held long enough: this is the combination that
        // returned false through two shipped builds
        XCTAssertTrue(LassoGate.shouldBeginLassoOnMove(
            heldFor: 0.5,
            touches: LassoGate.effectiveTouchCount(fingers: 1, pencilDown: true),
            disqualified: false))
    }
}
