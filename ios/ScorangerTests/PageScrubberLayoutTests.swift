import CoreGraphics
import XCTest

/// The 28pt answer to "where am I", and the finger that moves it.
final class PageScrubberLayoutTests: XCTestCase {

    /// A tick and the finger that aims at it agree, or the scrubber jumps
    /// somewhere the reader did not point.
    func testAFingerOnATickAsksForThatPage() {
        for pages in [1, 2, 9, 12, 47, 128] {
            for width in [120.0, 260.0, 340.0, 700.0] {
                for page in 0..<pages {
                    let x = PageScrubberLayout.x(ofPage: page, width: width,
                                                 pages: pages)
                    XCTAssertEqual(
                        PageScrubberLayout.page(atX: x, width: width, pages: pages),
                        page,
                        "\(pages) pages at \(width)pt: tick \(page) at x=\(x) "
                        + "reads back as another page")
                }
            }
        }
    }

    /// Both ends are live. A finger at the very edge means the first or last
    /// page -- those are the two places a reader aims for most.
    func testTheEndsOfTheRowAreNotDead() {
        XCTAssertEqual(PageScrubberLayout.page(atX: 0, width: 340, pages: 9), 0)
        XCTAssertEqual(PageScrubberLayout.page(atX: 340, width: 340, pages: 9), 8)
        XCTAssertEqual(PageScrubberLayout.page(atX: -40, width: 340, pages: 9), 0,
                       "a finger dragged off the left end")
        XCTAssertEqual(PageScrubberLayout.page(atX: 900, width: 340, pages: 9), 8,
                       "a finger dragged off the right end")
    }

    /// Nothing to divide by: no pages, no width. Answers rather than crashes.
    func testItSurvivesADocumentItKnowsNothingAbout() {
        XCTAssertEqual(PageScrubberLayout.page(atX: 100, width: 0, pages: 9), 0)
        XCTAssertEqual(PageScrubberLayout.page(atX: 100, width: 340, pages: 0), 0)
        XCTAssertEqual(PageScrubberLayout.pitch(width: 340, pages: 0), 0)
        XCTAssertEqual(PageScrubberLayout.label(page: 0, pages: 0), "")
    }

    /// A long book stops drawing separate ticks rather than drawing a smear
    /// that pretends to be countable.
    func testTicksGiveUpWhenTheyWouldOverlap() {
        XCTAssertTrue(PageScrubberLayout.showsTicks(width: 340, pages: 12))
        XCTAssertTrue(PageScrubberLayout.showsTicks(width: 340, pages: 100))
        XCTAssertFalse(PageScrubberLayout.showsTicks(width: 340, pages: 300))
    }

    /// The label counts from one, and never names a page the document has not
    /// got.
    func testTheLabelCountsFromOneAndStaysInsideTheDocument() {
        XCTAssertEqual(PageScrubberLayout.label(page: 0, pages: 9), "page 1")
        XCTAssertEqual(PageScrubberLayout.label(page: 8, pages: 9), "page 9")
        XCTAssertEqual(PageScrubberLayout.label(page: 40, pages: 9), "page 9")
        XCTAssertEqual(PageScrubberLayout.label(page: -3, pages: 9), "page 1")
    }

    /// It is the height §9.6 budgeted, and the budget is the point: 44 + 36 +
    /// 28 + 48 is 156 of a 266pt portrait allowance, and the rail it replaces
    /// was 96 on its own.
    func testItFitsTheChromeBudget() {
        XCTAssertEqual(PageScrubberLayout.height, 28)
        XCTAssertLessThan(PageScrubberLayout.height,
                          Theme.Metric.thumbStripHeight,
                          "the scrubber is not smaller than the rail it stands "
                          + "in for on a phone")
    }
}
