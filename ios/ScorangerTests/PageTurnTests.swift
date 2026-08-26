import CoreGraphics
import XCTest

/// The gesture arbitration from NAVIGATION_SYSTEM.md §6 -- one case per cell of
/// the table, because §9.3 is right that this is where regressions will be.
///
/// The thing being protected: the Pencil lasso. It selects music for chat, and
/// it is the same gesture as a page turn. These tests exist so that "the Pencil
/// turns pages" can never quietly become "the Pencil stopped selecting".
final class PageTurnTests: XCTestCase {

    // MARK: - The Pencil means one thing per mode

    func testThePencilStillLassosInReadMode() {
        XCTAssertFalse(PageTurn.mayTurn(isPencil: true, mode: .read),
                       "a Pencil swipe in read mode is a lasso and must stay one")
    }

    func testThePencilStillInksInEditMode() {
        XCTAssertFalse(PageTurn.mayTurn(isPencil: true, mode: .edit),
                       "a Pencil swipe in edit mode is ink")
    }

    func testThePencilTurnsOnlyInPerformanceMode() {
        XCTAssertTrue(PageTurn.mayTurn(isPencil: true, mode: .performance))
    }

    /// A finger neither selects nor inks, so its tap was free in every mode --
    /// a single-finger tap on the page did nothing at all before this.
    func testAFingerTapTurnsInEveryMode() {
        for mode in ScoreMode.allCases {
            XCTAssertTrue(PageTurn.mayTurn(isPencil: false, mode: mode),
                          "a finger tap should turn in \(mode)")
        }
    }

    // MARK: - A tap is still and quick, or it is a pan

    func testASlowPanNeverTurnsThePage() {
        XCTAssertFalse(PageTurn.isTap(movement: 120, elapsed: 0.2),
                       "movement means the reader is scrolling")
        XCTAssertNil(PageTurn.turn(isPencil: false, mode: .read, x: 30, width: 1000,
                                   movement: 120, elapsed: 0.2))
    }

    func testALongPressIsNotATap() {
        XCTAssertFalse(PageTurn.isTap(movement: 0, elapsed: 1.2))
    }

    func testAStillQuickTouchIsATap() {
        XCTAssertTrue(PageTurn.isTap(movement: PageTurn.tapSlop - 1,
                                     elapsed: PageTurn.tapWindow - 0.05))
    }

    // MARK: - Zones

    func testTheLeadingEdgeGoesBack() {
        XCTAssertEqual(PageTurn.zone(atX: 20, width: 1000), .previous)
    }

    func testTheTrailingEdgeGoesForward() {
        XCTAssertEqual(PageTurn.zone(atX: 980, width: 1000), .next)
    }

    func testTheMiddleOfTheScoreTurnsNothing() {
        XCTAssertEqual(PageTurn.zone(atX: 500, width: 1000), .centre)
        XCTAssertNil(PageTurn.turn(isPencil: false, mode: .read, x: 500, width: 1000,
                                   movement: 0, elapsed: 0.1),
                     "the music itself must not be a button")
    }

    func testTheZonesAreAThumbsReachAndNoMore() {
        // wide enough to hit without looking, narrow enough to leave the music
        XCTAssertGreaterThanOrEqual(PageTurn.zoneFraction, 0.15)
        XCTAssertLessThanOrEqual(PageTurn.zoneFraction, 0.25)
    }

    func testAZerroWidthCanvasTurnsNothing() {
        XCTAssertEqual(PageTurn.zone(atX: 0, width: 0), .centre)
    }

    // MARK: - The whole decision, one case per cell

    func testAPencilTapInPerformanceTurns() {
        XCTAssertEqual(PageTurn.turn(isPencil: true, mode: .performance, x: 950,
                                     width: 1000, movement: 2, elapsed: 0.1), .next)
    }

    func testAPencilTapInReadModeTurnsNothing() {
        // it is an add-or-drop on the selection, and must reach that path
        XCTAssertNil(PageTurn.turn(isPencil: true, mode: .read, x: 950, width: 1000,
                                   movement: 2, elapsed: 0.1))
    }

    func testAFingerTapAtTheEdgeTurnsEvenInEditMode() {
        XCTAssertEqual(PageTurn.turn(isPencil: false, mode: .edit, x: 10, width: 1000,
                                     movement: 1, elapsed: 0.1), .previous)
    }

    // MARK: - A turn is a scroll to the next boundary

    private let boundaries: [CGFloat] = [0, 800, 1600, 2400]

    func testNextGoesToTheFollowingBoundary() {
        XCTAssertEqual(PageTurn.destination(from: 0, boundaries: boundaries, zone: .next), 800)
    }

    func testPreviousGoesBack() {
        XCTAssertEqual(PageTurn.destination(from: 1600, boundaries: boundaries, zone: .previous),
                       800)
    }

    func testTurningFromMidPageAdvancesToTheNextBoundaryNotTheCurrentOne() {
        XCTAssertEqual(PageTurn.destination(from: 900, boundaries: boundaries, zone: .next), 1600)
        XCTAssertEqual(PageTurn.destination(from: 900, boundaries: boundaries, zone: .previous), 800)
    }

    func testTheLastPageDoesNotTurnForward() {
        XCTAssertNil(PageTurn.destination(from: 2400, boundaries: boundaries, zone: .next))
    }

    func testTheFirstPageDoesNotTurnBack() {
        XCTAssertNil(PageTurn.destination(from: 0, boundaries: boundaries, zone: .previous))
    }

    /// Sitting a pixel off a boundary must still advance, or a turn can appear
    /// to do nothing.
    func testAlmostOnABoundaryStillAdvances() {
        XCTAssertEqual(PageTurn.destination(from: 800.5, boundaries: boundaries, zone: .next), 1600)
    }

    func testAnEmptyScoreTurnsNowhere() {
        XCTAssertNil(PageTurn.destination(from: 0, boundaries: [], zone: .next))
    }
}
