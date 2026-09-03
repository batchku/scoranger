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
        // ...nor between two sizes of the same page. The book browser draws
        // page 137 twice -- once in its strip, once big enough to read a title
        // off -- and a key that named only the page handed whichever asked
        // second the other one's raster.
        let thumb = CGSize(width: 104, height: 136)
        let page = CGSize(width: 650, height: 840)
        XCTAssertNotEqual(ThumbnailCache.key(document: a, index: 0, size: thumb),
                          ThumbnailCache.key(document: a, index: 0, size: page))
        XCTAssertEqual(ThumbnailCache.key(document: a, index: 0, size: thumb),
                       ThumbnailCache.key(document: a, index: 0, size: thumb))
    }

    /// The same page at two sizes is two rasters, not one stretched.
    func testTheSamePageAtTwoSizesIsTwoImages() throws {
        let doc = document(pages: 2)
        ThumbnailCache.shared.clear()
        let thumb = ThumbnailCache.shared.image(document: doc, index: 0,
                                                size: CGSize(width: 104, height: 136))
        let page = ThumbnailCache.shared.image(document: doc, index: 0,
                                               size: CGSize(width: 650, height: 840))
        // PDFKit fits the page's own aspect ratio inside what is asked for,
        // so the widths are near the request rather than equal to it. What
        // matters is that they are two rasters and not one served twice.
        XCTAssertEqual(try XCTUnwrap(thumb).size.width, 104, accuracy: 2)
        XCTAssertEqual(try XCTUnwrap(page).size.width, 650, accuracy: 2)
    }

    /// A new engraving is made on every render and the last one released, so
    /// documents are not alive at the same time -- which is exactly when an
    /// address stops being unique. A document that has gone must not be able to
    /// hand its thumbnails to the next one.
    func testAReleasedDocumentDoesNotHandItsKeyToTheNextOne() {
        var dead: String?
        autoreleasepool {
            let gone = document(pages: 2)
            dead = ThumbnailCache.key(document: gone, index: 0)
        }
        let fresh = document(pages: 2)
        XCTAssertNotEqual(dead, ThumbnailCache.key(document: fresh, index: 0))
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
