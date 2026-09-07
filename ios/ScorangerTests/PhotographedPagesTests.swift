import UIKit
import XCTest

/// Several photos are ONE arrangement of n pages (§15 ruling 2).
///
/// Not n arrangements: somebody photographing a score is photographing a
/// piece. PHPicker hands its results back in selection order, and selection
/// order is page order -- the only ordering anyone could mean by tapping four
/// pages of one chart.
final class PhotographedPagesTests: XCTestCase {

    /// A solid colour, so a page can be identified by what is on it.
    private func page(_ colour: UIColor, size: CGSize = .init(width: 40, height: 60))
        -> Data {
        UIGraphicsImageRenderer(size: size).image { context in
            colour.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.pngData()!
    }

    func testSeveralPhotosBecomeOneDocumentOfThatManyPages() {
        let pages = [page(.red), page(.green), page(.blue)]
        guard let data = ScanImage.pdf(fromPages: pages) else {
            return XCTFail("three pictures produced no document")
        }
        guard let document = CGPDFDocument(CGDataProvider(data: data as CFData)!) else {
            return XCTFail("what came back is not a PDF")
        }
        XCTAssertEqual(document.numberOfPages, 3,
                       "three photographs should be one arrangement of three "
                       + "pages, not \(document.numberOfPages)")
    }

    /// Each page keeps its OWN proportions. A photograph is not A4, and a
    /// common page size would letterbox every page that did not match the
    /// first -- white margins round the music, notes shrunk to pay for them.
    func testEachPageKeepsItsOwnProportions() {
        let pages = [page(.red, size: .init(width: 40, height: 60)),
                     page(.green, size: .init(width: 90, height: 30))]
        guard let data = ScanImage.pdf(fromPages: pages),
              let document = CGPDFDocument(CGDataProvider(data: data as CFData)!),
              let first = document.page(at: 1), let second = document.page(at: 2)
        else { return XCTFail("no document") }
        let one = first.getBoxRect(.mediaBox)
        let two = second.getBoxRect(.mediaBox)
        XCTAssertGreaterThan(one.height, one.width, "page 1 should be portrait")
        XCTAssertGreaterThan(two.width, two.height, "page 2 should be landscape")
    }

    /// One photograph is not a document: it stays a picture, so it lands as an
    /// IMAGE arrangement exactly as a shared-in photograph does.
    func testOnePhotographIsStillAPicture() {
        XCTAssertEqual(ScoreArtifact.kind(ofFile: "IMG_0001.HEIC"), .image)
        // And the single-page wrap is still there for DISPLAYING one.
        XCTAssertNotNil(ScanImage.pdf(from: page(.red)))
    }

    /// Nothing readable in, nothing out -- rather than an empty document,
    /// which in the library is indistinguishable from a score that failed.
    func testUnreadablePicturesProduceNothing() {
        XCTAssertNil(ScanImage.pdf(fromPages: []))
        XCTAssertNil(ScanImage.pdf(fromPages: [Data("not a picture".utf8)]))
    }

    /// A readable page among unreadable ones still makes a document, rather
    /// than the whole pick being lost to one bad file.
    func testOneBadPageDoesNotLoseTheRest() {
        let data = ScanImage.pdf(fromPages: [page(.red),
                                             Data("rubbish".utf8),
                                             page(.blue)])
        guard let data, let document = CGPDFDocument(CGDataProvider(data: data as CFData)!)
        else { return XCTFail("the whole pick was lost") }
        XCTAssertEqual(document.numberOfPages, 2)
    }
}
