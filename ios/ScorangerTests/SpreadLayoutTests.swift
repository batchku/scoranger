import CoreGraphics
import XCTest

/// The arithmetic behind the two-page spread. The view is what proves the
/// pages land where they should; this proves the numbers they land by.
final class SpreadLayoutTests: XCTestCase {

    /// Portrait iPad, both panels collapsed — the case the spread is tuned for.
    private let portraitCanvas: CGFloat = 834

    func testASpreadPutsBothPagesInsideTheViewport() {
        let page = SpreadLayout.pageWidth(viewport: portraitCanvas, spread: true)
        let block = page * 2 + SpreadLayout.gutter + SpreadLayout.margin * 2
        XCTAssertEqual(block, portraitCanvas, accuracy: 0.5,
                       "a spread must fit the width it is given, exactly")
        XCTAssertEqual(SpreadLayout.contentWidth(viewport: portraitCanvas, spread: true),
                       portraitCanvas, accuracy: 0.5,
                       "and must not make the canvas scroll sideways")
    }

    func testASpreadPageIsAboutHalfASinglePage() {
        let single = SpreadLayout.pageWidth(viewport: portraitCanvas, spread: false)
        let spread = SpreadLayout.pageWidth(viewport: portraitCanvas, spread: true)
        XCTAssertEqual(spread, (single - SpreadLayout.gutter) / 2, accuracy: 0.5)
    }

    func testASpreadIsNotCappedTheWayASinglePageIs() {
        // A single page stops growing at 1100pt; two of them on a wide display
        // would leave a gap down the middle if they stopped there too.
        let wide: CGFloat = 2400
        XCTAssertEqual(SpreadLayout.pageWidth(viewport: wide, spread: false),
                       SpreadLayout.maxSinglePageWidth)
        XCTAssertGreaterThan(SpreadLayout.pageWidth(viewport: wide, spread: true),
                             SpreadLayout.maxSinglePageWidth,
                             "a spread should use the width it has")
    }

    func testASinglePageNarrowerThanTheViewportStillFillsTheCanvas() {
        // 1100pt cap, 2400pt of glass: the content stays viewport-wide so the
        // page centres instead of hugging the left edge.
        XCTAssertEqual(SpreadLayout.contentWidth(viewport: 2400, spread: false), 2400)
    }

    // MARK: - Which pages share a row

    func testPagesPairFromTheFirstPage() {
        XCTAssertEqual(SpreadLayout.rows(pageCount: 4, spread: true), [[0, 1], [2, 3]])
    }

    func testAnOddLastPageSitsAloneRatherThanBeingDropped() {
        XCTAssertEqual(SpreadLayout.rows(pageCount: 5, spread: true),
                       [[0, 1], [2, 3], [4]])
    }

    func testOnePageAtATimeIsOneRowEach() {
        XCTAssertEqual(SpreadLayout.rows(pageCount: 3, spread: false), [[0], [1], [2]])
    }

    func testAnEmptyDocumentHasNoRows() {
        XCTAssertEqual(SpreadLayout.rows(pageCount: 0, spread: true), [])
        XCTAssertEqual(SpreadLayout.rows(pageCount: 0, spread: false), [])
    }

    func testAViewportTooNarrowToDivideStillProducesADrawableWidth() {
        // degenerate, but a zero or negative frame is a crash waiting in a
        // layout pass rather than an assertion here
        XCTAssertGreaterThan(SpreadLayout.pageWidth(viewport: 1, spread: true), 0)
        XCTAssertGreaterThan(SpreadLayout.pageWidth(viewport: 0, spread: false), 0)
    }
}
