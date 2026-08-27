import CoreGraphics
import XCTest

/// The paged canvas (NAV_REVISION §6, carried into 0.4.2).
///
/// Written before the view, because the spec is explicit that ZoomableScroll
/// has been rebuilt three times and is the highest-risk edit in the revision.
/// What can be decided arithmetically is decided here, where a wrong answer
/// costs a second rather than a device.
final class PagedCanvasTests: XCTestCase {

    // MARK: - The unit on screen

    func testOnePageAtATimeWithTheSpreadOff() {
        XCTAssertEqual(PagedCanvas.unit(at: 3, pageCount: 12, spread: false), [3])
    }

    func testASpreadShowsAPair() {
        XCTAssertEqual(PagedCanvas.unit(at: 2, pageCount: 12, spread: true), [2, 3])
    }

    /// Units start on even indices, so page 1 belongs to the 0–1 spread rather
    /// than starting one of its own -- the way a title page sits alone.
    func testASpreadIsAlignedSoAPageBelongsToOneUnit() {
        XCTAssertEqual(PagedCanvas.unit(at: 3, pageCount: 12, spread: true), [2, 3])
        XCTAssertEqual(PagedCanvas.unit(at: 0, pageCount: 12, spread: true), [0, 1])
    }

    func testTheLastPageOfAnOddScoreSitsAlone() {
        XCTAssertEqual(PagedCanvas.unit(at: 4, pageCount: 5, spread: true), [4])
    }

    func testAnEmptyDocumentShowsNothing() {
        XCTAssertEqual(PagedCanvas.unit(at: 0, pageCount: 0, spread: false), [])
    }

    func testAnIndexOutsideTheDocumentShowsNothing() {
        XCTAssertEqual(PagedCanvas.unit(at: 99, pageCount: 12, spread: false), [])
    }

    // MARK: - Stepping

    func testATurnMovesOnePage() {
        XCTAssertEqual(PagedCanvas.step(from: 3, by: 1, pageCount: 12, spread: false), 4)
        XCTAssertEqual(PagedCanvas.step(from: 3, by: -1, pageCount: 12, spread: false), 2)
    }

    /// In a spread a turn moves a whole unit, or half the music would slide
    /// sideways under the reader.
    func testATurnInASpreadMovesTwo() {
        XCTAssertEqual(PagedCanvas.step(from: 2, by: 1, pageCount: 12, spread: true), 4)
        XCTAssertEqual(PagedCanvas.step(from: 3, by: 1, pageCount: 12, spread: true), 4)
        XCTAssertEqual(PagedCanvas.step(from: 4, by: -1, pageCount: 12, spread: true), 2)
    }

    func testTheEndsDoNotTurn() {
        XCTAssertNil(PagedCanvas.step(from: 11, by: 1, pageCount: 12, spread: false))
        XCTAssertNil(PagedCanvas.step(from: 0, by: -1, pageCount: 12, spread: false))
    }

    // MARK: - The strip jumps to the unit holding a page

    func testTappingAThumbLandsOnItsUnit() {
        XCTAssertEqual(PagedCanvas.index(forPage: 5, spread: true), 4,
                       "tapping the right half of a spread must not scroll its left half away")
        XCTAssertEqual(PagedCanvas.index(forPage: 5, spread: false), 5)
    }

    // MARK: - Zoom, and what it means for how many pages you can see

    /// "You can never see more than two pages" is not enforced anywhere: it is
    /// what fitting one unit to the canvas MEANS, and the floor is fit.
    func testYouCannotZoomOutPastFit() {
        XCTAssertEqual(PagedCanvas.clamp(zoom: 0.5), 1.0)
        XCTAssertEqual(PagedCanvas.clamp(zoom: 0.01), 1.0)
        XCTAssertEqual(PagedCanvas.minimumZoom, 1.0)
    }

    func testYouCanStillZoomAllTheWayIn() {
        XCTAssertEqual(PagedCanvas.clamp(zoom: 12), 12)
        XCTAssertEqual(PagedCanvas.clamp(zoom: 40), 12)
    }

    func testAtFitThereIsNothingToPan() {
        XCTAssertFalse(PagedCanvas.canPan(zoom: 1.0))
        XCTAssertTrue(PagedCanvas.canPan(zoom: 1.4))
    }

    // MARK: - Swipe to turn, and the edge

    /// At fit a drag has nothing to move, so it is free to mean a turn.
    func testASwipeTurnsWhenThereIsNothingToPan() {
        XCTAssertTrue(PagedCanvas.swipeMayTurn(zoom: 1.0, atHorizontalLimit: false))
    }

    /// Zoomed in and mid-page, a drag pans and must not turn -- otherwise the
    /// page flies away from someone reading a notehead.
    func testASwipeDoesNotTurnWhileThereIsStillPageToPan() {
        XCTAssertFalse(PagedCanvas.swipeMayTurn(zoom: 3, atHorizontalLimit: false))
    }

    /// Ali's build-with answer: STOP at the edge. Reaching the limit does not
    /// roll into a turn by itself -- but once you are there, a further swipe
    /// is unambiguous.
    func testAtTheEdgeASwipeMayTurn() {
        XCTAssertTrue(PagedCanvas.swipeMayTurn(zoom: 3, atHorizontalLimit: true))
    }

    // MARK: - What a turn does to the view

    /// A violinist reading at 180% stays at 180%.
    func testZoomSurvivesATurn() {
        XCTAssertEqual(PagedCanvas.afterTurn(zoom: 1.8).zoom, 1.8)
    }

    func testPanResetsToTheTopLeftOfTheNewPage() {
        XCTAssertEqual(PagedCanvas.afterTurn(zoom: 1.8).offset, .zero,
                       "turning a paper page does not leave you halfway down it")
    }

    func testAnImpossibleZoomIsStillClampedAfterATurn() {
        XCTAssertEqual(PagedCanvas.afterTurn(zoom: 0.2).zoom, 1.0)
    }

    // MARK: - Rapid turning

    /// Queueing animations means the reader keeps turning and the score keeps
    /// sliding after they stop.
    func testRapidTurnsCoalesceToTheLatest() {
        XCTAssertEqual(PagedCanvas.coalesce(pending: 4, latest: 7), 7)
        XCTAssertEqual(PagedCanvas.coalesce(pending: nil, latest: 2), 2)
    }
}
