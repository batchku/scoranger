import PDFKit
import XCTest

/// L20: the strip drew only six pages either side of the current one and left
/// the rest blank, so a nine-page score showed seven pages and two empty
/// placeholders -- which reads as a failed render, not as a budget.
final class ThumbnailCacheTests: XCTestCase {

    private func document(pages: Int) -> PDFDocument {
        let format = UIGraphicsPDFRendererFormat()
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = UIGraphicsPDFRenderer(bounds: bounds, format: format).pdfData { context in
            for page in 0..<pages {
                context.beginPage()
                UIColor.black.setFill()
                UIRectFill(CGRect(x: 40, y: 40 + page * 10, width: 200, height: 8))
            }
        }
        return PDFDocument(data: data)!
    }

    func testEveryPageGetsARealThumbnail() {
        let doc = document(pages: 9)
        ThumbnailCache.shared.clear()
        for index in 0..<doc.pageCount {
            let image = ThumbnailCache.shared.image(document: doc, index: index,
                                                    size: CGSize(width: 104, height: 136))
            XCTAssertNotNil(image, "page \(index + 1) drew nothing")
        }
    }

    /// The last two pages are the ones Ali saw blank: outside a six-page window
    /// from page 1, and drawn now.
    func testTheLastPagesOfANinePageScoreDraw() {
        let doc = document(pages: 9)
        ThumbnailCache.shared.clear()
        for index in [7, 8] {
            XCTAssertNotNil(ThumbnailCache.shared.image(document: doc, index: index,
                                                        size: CGSize(width: 104, height: 136)),
                            "page \(index + 1) drew nothing")
        }
    }

    func testAPageThatIsNotThereDrawsNothingRatherThanCrashing() {
        let doc = document(pages: 2)
        XCTAssertNil(ThumbnailCache.shared.image(document: doc, index: 99,
                                                 size: CGSize(width: 104, height: 136)))
    }

    /// Two scores both have a page 1, and they do not look alike.
    func testKeysDoNotCollideBetweenDocuments() {
        let a = document(pages: 2), b = document(pages: 2)
        XCTAssertNotEqual(ThumbnailCache.key(document: a, index: 0),
                          ThumbnailCache.key(document: b, index: 0))
        XCTAssertNotEqual(ThumbnailCache.key(document: a, index: 0),
                          ThumbnailCache.key(document: a, index: 1))
        XCTAssertEqual(ThumbnailCache.key(document: a, index: 1),
                       ThumbnailCache.key(document: a, index: 1))
    }

    /// Rasterising is the expensive part, so a page is drawn once.
    func testAPageIsRasterisedOnceAndThenReused() {
        let doc = document(pages: 3)
        ThumbnailCache.shared.clear()
        let size = CGSize(width: 104, height: 136)
        let first = ThumbnailCache.shared.image(document: doc, index: 1, size: size)
        let again = ThumbnailCache.shared.image(document: doc, index: 1, size: size)
        XCTAssertNotNil(first)
        XCTAssertTrue(first === again, "the page was rasterised twice")
    }
}
