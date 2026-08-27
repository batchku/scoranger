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

    // MARK: - Fitting the unit, which is what makes the floor mean anything

    /// A4-ish: taller than it is wide.
    private let portrait: CGFloat = 1.414

    func testATallPageOnAWideScreenIsHeightBound() {
        // 1200x800 landscape: the page runs out of height long before width
        let w = PagedCanvas.fittedPageWidth(viewport: CGSize(width: 1200, height: 800),
                                            pageAspect: portrait, pages: 1,
                                            gutter: 12, margin: 12)
        XCTAssertEqual(w * portrait, 800 - 24, accuracy: 1,
                       "the page should be exactly as tall as the viewport allows")
        XCTAssertLessThan(w, 1200 - 24, "and narrower than the width allows")
    }

    func testAWidePageOnATallScreenIsWidthBound() {
        let w = PagedCanvas.fittedPageWidth(viewport: CGSize(width: 400, height: 1200),
                                            pageAspect: portrait, pages: 1,
                                            gutter: 12, margin: 12)
        XCTAssertEqual(w, 400 - 24, accuracy: 1)
    }

    /// A spread has to fit BOTH pages and the gutter between them, so each page
    /// is a little under half the width -- not half.
    func testASpreadSplitsTheWidthAndPaysForTheGutter() {
        let one = PagedCanvas.fittedPageWidth(viewport: CGSize(width: 2000, height: 4000),
                                              pageAspect: portrait, pages: 1,
                                              gutter: 12, margin: 12)
        let two = PagedCanvas.fittedPageWidth(viewport: CGSize(width: 2000, height: 4000),
                                              pageAspect: portrait, pages: 2,
                                              gutter: 12, margin: 12)
        XCTAssertLessThan(two, one / 2 + 1)
        XCTAssertEqual(two * 2 + 12, one, accuracy: 1,
                       "two pages plus the gutter should use the same width as one")
    }

    /// Fitted means fitted: at zoom 1 the whole unit is inside the viewport,
    /// which is the entire reason the zoom floor can be 1.
    func testTheFittedUnitIsInsideTheViewportInBothDimensions() {
        for viewport in [CGSize(width: 1200, height: 800),
                         CGSize(width: 820, height: 1180),
                         CGSize(width: 500, height: 500)] {
            for pages in [1, 2] {
                let w = PagedCanvas.fittedPageWidth(viewport: viewport, pageAspect: portrait,
                                                    pages: pages, gutter: 12, margin: 12)
                let used = w * CGFloat(pages) + 12 * CGFloat(pages - 1)
                XCTAssertLessThanOrEqual(used, viewport.width - 23,
                                         "too wide at \(viewport) x\(pages)")
                XCTAssertLessThanOrEqual(w * portrait, viewport.height - 23,
                                         "too tall at \(viewport) x\(pages)")
            }
        }
    }

    func testAnUnmeasuredViewportAsksForNothing() {
        XCTAssertEqual(PagedCanvas.fittedPageWidth(viewport: .zero, pageAspect: portrait,
                                                   pages: 1, gutter: 12, margin: 12), 0)
        XCTAssertEqual(PagedCanvas.fittedPageWidth(viewport: CGSize(width: 100, height: 100),
                                                   pageAspect: 0, pages: 1,
                                                   gutter: 12, margin: 12), 0)
    }
}
