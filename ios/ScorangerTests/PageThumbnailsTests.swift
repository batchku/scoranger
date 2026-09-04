import XCTest

/// The budget a strip of page pictures is held to, and the three states a cell
/// can be in.
final class PageThumbnailsTests: XCTestCase {

    /// A whole fake book's strip fits, which is the point of the number: a
    /// reader who has been through the book can go back over it without
    /// redrawing a page.
    func testTheBudgetHoldsAWholeBigBooksStrip() {
        let cell = PageThumbnails.stripCellPixels
        let held = PageThumbnails.pagesHeld(pixelsWide: cell.wide, pixelsHigh: cell.high)
        XCTAssertGreaterThanOrEqual(held, 512,
                                    "the budget cannot hold a 512-page strip")
    }

    /// ...and a working set of the big ones, which is what flipping through
    /// costs. Not two hundred of them: two hundred was the old bound and it
    /// came to 413MB.
    func testTheBudgetHoldsAWorkingSetOfReadingPagesAndNotTwoHundred() {
        let page = PageThumbnails.readingPagePixels
        let held = PageThumbnails.pagesHeld(pixelsWide: page.wide, pixelsHigh: page.high)
        XCTAssertGreaterThanOrEqual(held, 12, "too few reading pages to flip through")
        XCTAssertLessThan(held, 200, "as loose as the count bound it replaces")
        XCTAssertLessThan(200 * PageThumbnails.bytes(pixelsWide: page.wide,
                                                     pixelsHigh: page.high),
                          800 << 20,
                          "sanity: the old ceiling should be hundreds of MB")
        XCTAssertGreaterThan(200 * PageThumbnails.bytes(pixelsWide: page.wide,
                                                        pixelsHigh: page.high),
                             PageThumbnails.budget * 5,
                             "the old count bound was many times this budget")
    }

    func testBytesAreFourToThePixelAndNeverNegative() {
        XCTAssertEqual(PageThumbnails.bytes(pixelsWide: 104, pixelsHigh: 136),
                       104 * 136 * 4)
        XCTAssertEqual(PageThumbnails.bytes(pixelsWide: -5, pixelsHigh: 10), 0)
        XCTAssertEqual(PageThumbnails.pagesHeld(pixelsWide: 0, pixelsHigh: 0), 0)
    }

    // MARK: - the three states

    /// A page that drew, and a page that would not.
    func testAPageThatWillNotDrawSaysSo() {
        XCTAssertEqual(PageThumbnails.phase(drew: true, abandoned: false), .drawn)
        XCTAssertEqual(PageThumbnails.phase(drew: false, abandoned: false), .missing)
    }

    /// A request the reader scrolled past is not a failure. This is the whole
    /// reason there are three states: with cancellation, "no picture came
    /// back" is the ORDINARY outcome of a flick, and showing a warning
    /// triangle for it would put one on every page of a fast scroll.
    func testAbandoningARequestIsNotAFailure() {
        XCTAssertEqual(PageThumbnails.phase(drew: false, abandoned: true), .pending)
        XCTAssertEqual(PageThumbnails.phase(drew: true, abandoned: true), .pending)
    }
}
