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
}
