import UIKit
import XCTest

/// A picture of a page, turned into something the score view already knows.
///
/// The whole design of image import is that an image takes the PDF's path
/// rather than a parallel one. The score view draws PDFs -- PDFKit, the paged
/// canvas, page turns, thumbnails, Pencil markup, export -- and every one of
/// those would need an image variant if the image stayed an image on screen.
///
/// So it does not. One helper wraps the image in a single-page PDF at the
/// boundary, and everything downstream is unchanged. The same helper feeds
/// OMR, which posts `Content-Type: application/pdf`, so the service needs no
/// work either.
///
/// The ARTIFACT stays the original image. This is a rendering of it, made on
/// demand and never stored, which is what "viewable as-is" has to mean: the
/// bytes in the library are the file the reader gave us.
final class ScanImageTests: XCTestCase {

    /// A real JPEG of a known size, made here rather than shipped as a
    /// fixture -- the test then depends on nothing it cannot see.
    private func jpeg(width: CGFloat, height: CGFloat) -> Data {
        let size = CGSize(width: width, height: height)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            context.fill(CGRect(x: 4, y: 4, width: width - 8, height: 6))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }

    private func pageSize(ofPDF data: Data) -> CGSize? {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else { return nil }
        return page.getBoxRect(.mediaBox).size
    }

    private func pageCount(ofPDF data: Data) -> Int {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else { return 0 }
        return document.numberOfPages
    }

    func testAnImageBecomesASinglePagePDF() throws {
        let wrapped = try XCTUnwrap(ScanImage.pdf(from: jpeg(width: 600, height: 800)))
        XCTAssertEqual(pageCount(ofPDF: wrapped), 1)
    }

    /// The page IS the image: same proportions, so nothing is letterboxed on
    /// to paper it was never on. A photograph of a chart is not A4 and
    /// pretending it is would put white margins round the reader's music.
    func testThePageIsTheImageAndNotAPaperSize() throws {
        for (w, h) in [(600.0, 800.0), (1600.0, 900.0), (500.0, 500.0)] {
            let wrapped = try XCTUnwrap(ScanImage.pdf(from: jpeg(width: w, height: h)))
            let page = try XCTUnwrap(pageSize(ofPDF: wrapped))
            XCTAssertEqual(page.width / page.height, w / h, accuracy: 0.01,
                           "\(Int(w))x\(Int(h)) became \(page)")
        }
    }

    /// Bytes that are not an image are refused rather than producing a blank
    /// page. A blank page in the library is indistinguishable from a score
    /// that failed to load, and the reader would have no way to tell.
    func testSomethingThatIsNotAnImageIsRefused() {
        XCTAssertNil(ScanImage.pdf(from: Data("not an image".utf8)))
        XCTAssertNil(ScanImage.pdf(from: Data()))
    }

    /// A PNG works as well as a JPEG -- the wrap goes through UIImage, which
    /// decodes every format the OS does, which is also why HEIC needs no
    /// special case here.
    func testAPNGWorksToo() throws {
        let size = CGSize(width: 300, height: 400)
        let png = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.pngData()!
        let wrapped = try XCTUnwrap(ScanImage.pdf(from: png))
        XCTAssertEqual(pageCount(ofPDF: wrapped), 1)
    }

    /// The helper only fires for images. A PDF is already a PDF and must go
    /// through untouched -- re-wrapping one would flatten a multi-page score
    /// into a single page, which is the bug this whole feature is next to.
    func testAPDFIsPassedThroughUntouched() throws {
        let pdf = try XCTUnwrap(ScanImage.pdf(from: jpeg(width: 200, height: 200)))
        let again = ScanImage.displayable(pdf, kind: .scan)
        XCTAssertEqual(again, pdf, "a PDF was re-wrapped")
    }

    func testAnImageIsWrappedForDisplay() throws {
        let image = jpeg(width: 200, height: 300)
        let shown = try XCTUnwrap(ScanImage.displayable(image, kind: .image))
        XCTAssertNotEqual(shown, image, "the image was handed over unwrapped")
        XCTAssertEqual(pageCount(ofPDF: shown), 1)
    }
}
