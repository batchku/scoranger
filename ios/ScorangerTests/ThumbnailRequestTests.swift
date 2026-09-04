import PDFKit
import XCTest

/// The queued, withdrawable raster — the half of the book-browser fix that the
/// byte budget cannot cover.
///
/// A lazy strip of 512 pages creates and destroys cells as fast as a finger
/// moves. What broke scrolling was not that a page is expensive to draw (it is
/// 4 ms) but that the drawing happened INSIDE the view body, on the main
/// thread, with nothing able to call it off: a cell the reader had already
/// scrolled past was still drawn, because drawing it is how the cell is made.
final class ThumbnailRequestTests: XCTestCase {

    private func document(pages: Int) -> PDFDocument {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for page in 0..<pages {
                context.beginPage()
                UIColor.black.setFill()
                // Enough drawing that a raster is milliseconds rather than
                // microseconds: a cancellation test over pages that cost
                // nothing measures the sleep, not the cancelling.
                for line in 0..<40 {
                    UIRectFill(CGRect(x: 40, y: 60 + line * 17 + page,
                                      width: 520, height: 2))
                }
                for note in 0..<900 {
                    let x = 44 + (note % 60) * 9
                    let y = 64 + (note / 60) * 46 + (note * 11) % 30
                    UIBezierPath(ovalIn: CGRect(x: x, y: y, width: 8, height: 6)).fill()
                }
            }
        }
        return PDFDocument(data: data)!
    }

    private let size = CGSize(width: 104, height: 136)

    /// The picture comes back, and it is held afterwards.
    func testARequestedPageIsDrawnAndThenHeld() async throws {
        let doc = document(pages: 4)
        ThumbnailCache.shared.clear()
        let image = await ThumbnailCache.shared.request(document: doc, index: 1,
                                                        size: size)
        XCTAssertNotNil(image)
        XCTAssertNotNil(ThumbnailCache.shared.cached(document: doc, index: 1,
                                                     size: size),
                        "the drawn page was not kept")
    }

    /// The lookup a view body does on every pass must never draw anything.
    /// This is what makes it safe to call from `body` at all.
    func testAskingWhatIsHeldNeverDrawsAnything() {
        let doc = document(pages: 4)
        ThumbnailCache.shared.clear()
        XCTAssertNil(ThumbnailCache.shared.cached(document: doc, index: 0, size: size))
        XCTAssertEqual(ThumbnailCache.shared.heldCount, 0,
                       "a peek rasterised a page")
    }

    /// A page that is not there answers nothing rather than crashing.
    func testAPageThatIsNotThereRequestsNothing() async {
        let doc = document(pages: 2)
        let image = await ThumbnailCache.shared.request(document: doc, index: 99,
                                                        size: size)
        XCTAssertNil(image)
    }

    /// The reader scrolled past: the ask is withdrawn, the page is never
    /// drawn, and the call comes back instead of leaking a task.
    ///
    /// The queue draws one at a time, so a hundred asks placed at once and
    /// cancelled at once leave almost all of them un-started — and an
    /// operation that has not started never rasterises. Before this, all
    /// hundred were drawn, in order, on the main thread.
    func testCancellingARequestBeforeItRunsDrawsNothing() async {
        let doc = document(pages: 120)
        ThumbnailCache.shared.clear()
        let work = Task {
            await withTaskGroup(of: Void.self) { group in
                for index in 0..<120 {
                    group.addTask {
                        _ = await ThumbnailCache.shared.request(
                            document: doc, index: index, size: self.size)
                    }
                }
                await group.waitForAll()
            }
        }
        // Long enough for the asks to be placed, far short of what the serial
        // queue needs to draw them all.
        try? await Task.sleep(nanoseconds: 10_000_000)
        work.cancel()
        await work.value
        let drawn = ThumbnailCache.shared.heldCount
        print("CANCEL 120 asked, \(drawn) drawn before the reader moved on")
        XCTAssertLessThan(drawn, 60,
                          "cancelling the asks drew most of the pages anyway")
    }

    /// A cancelled ask returns — it does not hang the caller. The strip's
    /// cells depend on this: every one of them that leaves the screen is a
    /// cancelled task, and a task that never resumed would pile up until the
    /// app stopped answering, which is the fault this whole change is about.
    func testACancelledRequestAlwaysComesBack() async {
        let doc = document(pages: 60)
        ThumbnailCache.shared.clear()
        for _ in 0..<20 {
            let work = Task { () -> UIImage? in
                await ThumbnailCache.shared.request(document: doc,
                                                    index: Int.random(in: 0..<60),
                                                    size: self.size)
            }
            work.cancel()
            _ = await work.value      // hangs the test if a continuation is lost
        }
    }

    /// Two asks for the same page draw it once. The strip and the reading page
    /// are two sizes of one page, so this is per SIZE, not per page.
    func testTheSamePageIsDrawnOnceHoweverOftenItIsAskedFor() async {
        let doc = document(pages: 4)
        ThumbnailCache.shared.clear()
        let first = await ThumbnailCache.shared.request(document: doc, index: 2,
                                                        size: size)
        let again = await ThumbnailCache.shared.request(document: doc, index: 2,
                                                        size: size)
        XCTAssertTrue(first === again, "the page was drawn twice")
        XCTAssertEqual(ThumbnailCache.shared.heldCount, 1)
    }

    /// The store keeps its budget under a walk that asks for far more than it
    /// can hold — the bound that a count could not express.
    func testTheStoreHoldsItsBudgetUnderAWalkThatOverfillsIt() {
        let doc = document(pages: 200)
        ThumbnailCache.shared.clear()
        let big = CGSize(width: 646, height: 840)     // a reading page: 2.1MB
        for index in 0..<200 {
            _ = ThumbnailCache.shared.image(document: doc, index: index, size: big)
        }
        print("BUDGET 200 reading pages asked, holding "
              + "\(ThumbnailCache.shared.heldBytes / (1 << 20))MB in "
              + "\(ThumbnailCache.shared.heldCount) entries "
              + "(ceiling \(ThumbnailCache.budget / (1 << 20))MB)")
        XCTAssertLessThanOrEqual(ThumbnailCache.shared.heldBytes,
                                 ThumbnailCache.budget)
        XCTAssertGreaterThan(ThumbnailCache.shared.heldCount, 0,
                             "the store evicted everything")
    }
}
