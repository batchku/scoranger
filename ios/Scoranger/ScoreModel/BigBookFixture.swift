#if canImport(UIKit)
import UIKit

/// A book the size of a Real Book, made on the spot.
///
/// Test fixture only, reached under `-seedBigBook` and by nothing else. It
/// exists because the two faults in the book browser -- a flick that stopped
/// the main thread once per page, and a picture store bounded by a COUNT over
/// pictures that differ 37-fold in size -- cannot be reproduced on a ten-page
/// score. They need the size that broke: several hundred pages.
///
/// Made rather than shipped: a real fake book is hundreds of megabytes of scan
/// and has an owner. This is a few seconds of vector drawing and no copyright.
/// It understates what a page costs to RASTERISE, which is why the timings in
/// `ScannedBookPerfTests` are taken against a scan instead; what it reproduces
/// faithfully is the page COUNT, which is what the strip's laziness and the
/// store's ceiling answer to.
enum BigBookFixture {

    /// What a fake book is: four hundred-odd pages, one tune every page or two.
    static let defaultPages = 512

    /// Write one to `url`. Returns false if it could not be written.
    @discardableResult
    static func write(to url: URL, pages: Int = defaultPages) -> Bool {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for page in 0..<pages {
                context.beginPage()
                draw(page: page)
            }
        }
        return (try? data.write(to: url)) != nil
    }

    /// The same book as a SCAN: every page a picture, so there is no text
    /// layer and the tunes can only be found by reading the pages with Vision
    /// (0.14.0, BookOCR). Reached under `-shareInScannedBook`.
    @discardableResult
    static func writeScanned(to url: URL, pages: Int) -> Bool {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pictures = (0..<pages).map { page in
            UIGraphicsImageRenderer(size: bounds.size).image { _ in
                UIColor.white.setFill()
                UIRectFill(bounds)
                draw(page: page)
            }
        }
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for picture in pictures {
                context.beginPage()
                picture.draw(in: bounds)
            }
        }
        return (try? data.write(to: url)) != nil
    }

    /// A page with a title big enough to read off a thumbnail and enough
    /// staves that a raster is real drawing.
    private static func draw(page: Int) {
        UIColor.black.setFill()
        ("Tune \(page + 1)" as NSString).draw(
            at: CGPoint(x: 60, y: 44),
            withAttributes: [.font: UIFont.boldSystemFont(ofSize: 24)])
        for system in 0..<8 {
            let top = 110 + system * 82
            for line in 0..<5 {
                UIRectFill(CGRect(x: 48, y: top + line * 8, width: 516, height: 1))
            }
            for note in 0..<24 {
                let x = 60 + note * 21
                let y = top + (note * 5 + page) % 32
                UIBezierPath(ovalIn: CGRect(x: x, y: y, width: 9, height: 7)).fill()
            }
        }
    }
}
#endif
