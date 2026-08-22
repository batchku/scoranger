import PDFKit
import UIKit
import XCTest

// No import of the app module: this bundle has no host and compiles
// PDFPreflight.swift straight in, the same way it does ScoreModel.

/// The preflight that stands between an imported PDF and optical music
/// recognition. Fixtures are built here rather than committed: the repo is
/// public, and a synthesized page exercises the geometry just as well.
final class PDFPreflightTests: XCTestCase {

    /// A vector PDF at an arbitrary page size, with a little text on it — the
    /// shape of a notation-software export.
    private func vectorPDF(width: CGFloat, height: CGFloat,
                           pages: Int = 1, text: String = "Morrison's Jig") -> Data {
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { ctx in
            for page in 0..<pages {
                ctx.beginPage()
                UIColor.black.setStroke()
                let staff = UIBezierPath()
                for line in 0..<5 {
                    let y = height * 0.3 + CGFloat(line) * height * 0.01
                    staff.move(to: CGPoint(x: width * 0.1, y: y))
                    staff.addLine(to: CGPoint(x: width * 0.9, y: y))
                }
                staff.lineWidth = max(1, height / 800)
                staff.stroke()
                "\(text) \(page + 1)".draw(
                    at: CGPoint(x: width * 0.1, y: height * 0.1),
                    withAttributes: [.font: UIFont.systemFont(ofSize: max(12, height / 60))])
            }
        }
    }

    /// A page with no text layer at all: what a scan looks like.
    private func scanLikePDF(width: CGFloat, height: CGFloat) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { ctx in
            ctx.beginPage()
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: width * 2,
                                                               height: height * 2))
            let image = renderer.image { inner in
                UIColor.white.setFill()
                inner.fill(CGRect(origin: .zero, size: CGSize(width: width * 2,
                                                             height: height * 2)))
                UIColor.black.setStroke()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 20, y: 40))
                path.addLine(to: CGPoint(x: width * 2 - 20, y: 40))
                path.stroke()
            }
            image.draw(in: bounds)
        }
    }

    // MARK: - What gets re-rendered

    func testOversizedPagesAreNormalizedToLetterAt300DPI() throws {
        // Ali's Morrison's Jig geometry: 2976 x 4209 pt, ~41 x 58 inches
        let result = PDFPreflight.prepare(vectorPDF(width: 2976, height: 4209))
        let note = try XCTUnwrap(result.note, "an oversized page must be re-rendered")
        XCTAssertTrue(note.contains("41 x 58 inches"), "note should say what was wrong: \(note)")

        let out = try XCTUnwrap(PDFDocument(data: result.data))
        let box = try XCTUnwrap(out.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertEqual(box.width, 612, accuracy: 1)
        XCTAssertEqual(box.height, 792, accuracy: 1)
    }

    func testVectorNotationAtNormalSizeIsRasterized() throws {
        let result = PDFPreflight.prepare(vectorPDF(width: 595, height: 842))
        let note = try XCTUnwrap(result.note, "vector notation should be rasterized")
        XCTAssertTrue(note.contains("vector"), note)
    }

    func testAScanIsLeftAlone() {
        let scan = scanLikePDF(width: 612, height: 792)
        let result = PDFPreflight.prepare(scan)
        XCTAssertNil(result.note, "a normal scan needs no help")
        XCTAssertEqual(result.data, scan, "a scan must be passed through untouched")
    }

    // MARK: - What comes out

    func testEveryPageSurvivesTheRender() throws {
        let result = PDFPreflight.prepare(vectorPDF(width: 2976, height: 4209, pages: 3))
        let out = try XCTUnwrap(PDFDocument(data: result.data))
        XCTAssertEqual(out.pageCount, 3, "pages were lost in the render")
    }

    func testRenderedPageCarriesInkAtScannerResolution() throws {
        let result = PDFPreflight.prepare(vectorPDF(width: 2976, height: 4209))
        let page = try XCTUnwrap(PDFDocument(data: result.data)?.page(at: 0))
        // 612 pt at 300 DPI = 2550 px across
        let box = page.bounds(for: .mediaBox)
        let image = page.thumbnail(of: CGSize(width: box.width * PDFPreflight.targetDPI / 72,
                                              height: box.height * PDFPreflight.targetDPI / 72),
                                   for: .mediaBox)
        XCTAssertEqual(image.size.width, 2550, accuracy: 4)

        // and it is not a blank page: some pixels are dark
        let cg = try XCTUnwrap(image.cgImage)
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let context = CGContext(data: &pixels, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width,
                                space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)
        context?.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        XCTAssertTrue(pixels.contains { $0 < 128 },
                      "the re-rendered page has no ink on it")
    }

    func testAPDFItCannotReadIsPassedThroughRatherThanDropped() {
        let junk = Data("not a pdf".utf8)
        let result = PDFPreflight.prepare(junk)
        XCTAssertEqual(result.data, junk)
        XCTAssertNil(result.note)
    }

    // MARK: - What the user is told when OMR still fails

    func testFailureAdviceNamesTheCauseAndAWayForward() {
        let advice = PDFPreflight.advice(
            name: "Morrison's jig",
            error: NSError(domain: "omr", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "audiveris could not read this PDF as a score"]),
            preflight: "rendered 2 pages to 300 DPI for OMR (pages are 2976 x 4209 pt)")
        XCTAssertTrue(advice.contains("MusicXML"), "should point at the import that needs no OMR")
        XCTAssertTrue(advice.contains("already rendered 2 pages"),
                      "should say what preflight already tried: \(advice)")
    }

    func testTimeoutAdviceIsDifferent() {
        let advice = PDFPreflight.advice(
            name: "Long score",
            error: NSError(domain: "omr", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "audiveris timed out"]),
            preflight: nil)
        XCTAssertTrue(advice.contains("fewer pages"), advice)
    }
}
