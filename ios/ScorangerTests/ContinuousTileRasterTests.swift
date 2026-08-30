import PDFKit
import UIKit
import XCTest

/// #61: a tile must be a WINDOW onto the strip, not a shrunken copy of it.
///
/// The continuous strip is one PDF page thousands of points wide, drawn in
/// tiles. `PDFPage.draw(with:to:)` FITS a page to the context it is handed, so
/// every tile drew the entire score squeezed into its own width — on a phone
/// the music arrived as a compressed band about ten points tall. No geometry
/// test could see it: the frames were all correct and the arithmetic was
/// exact. Only the pixels were wrong, so these assertions read pixels.
final class ContinuousTileRasterTests: XCTestCase {
    /// A wide page with ink ONLY in its left quarter, so a correct window can
    /// be told from a squeezed copy: a copy would show that ink in every tile.
    /// The REAL geometry, measured on device: an eleven-page quartet engraved
    /// with breaks:none comes back about 17267 x 541 points. The extreme
    /// aspect ratio is the point -- a modest fixture does not reproduce the
    /// bug, which is how a first version of these tests passed against the
    /// broken code.
    private func stripPage(width: CGFloat = 17267, height: CGFloat = 541) -> PDFPage? {
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            UIColor.black.setFill()
            // full height, and exactly the FIRST TILE's width -- so tile 0 is
            // solid ink and every later tile is blank. On a strip this wide a
            // "left quarter" would span several tiles and prove nothing.
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 900, height: height))
        }
        return PDFDocument(data: data)?.page(at: 0)
    }

    /// (fraction of pixels that are dark, topmost dark row, bottommost dark row)
    private func ink(_ image: UIImage) -> (fraction: Double, top: Int, bottom: Int) {
        guard let cg = image.cgImage else { return (0, -1, -1) }
        let w = cg.width, h = cg.height
        var bytes = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &bytes, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return (0, -1, -1) }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var dark = 0, top = -1, bottom = -1
        for y in 0..<h {
            var rowHasInk = false
            for x in 0..<w where bytes[y * w + x] < 100 {
                dark += 1
                rowHasInk = true
            }
            if rowHasInk {
                if top < 0 { top = y }
                bottom = y
            }
        }
        return (Double(dark) / Double(w * h), top, bottom)
    }

    func testATileShowsOnlyItsOwnSliceOfTheStrip() throws {
        let page = try XCTUnwrap(stripPage())
        let tile = { (x: CGFloat) in CGRect(x: x, y: 0, width: 900, height: 200) }

        // the left tile sits entirely inside the inked quarter
        let left = ContinuousTiles.raster(page: page, tile: tile(0), scale: 1, atDepth: true)
        // the third tile is past it, and must be blank
        let right = ContinuousTiles.raster(page: page, tile: tile(1800), scale: 1, atDepth: true)

        let inked = ink(left), blank = ink(right)
        XCTAssertGreaterThan(inked.fraction, 0.8,
                             "the inked quarter should fill its tile")
        XCTAssertLessThan(blank.fraction, 0.05,
                          "a tile past the ink drew something — every tile is "
                          + "showing the whole page, which is #61")
    }

    /// The symptom as the designer saw it: ink squeezed into a thin band
    /// instead of spanning the tile.
    func testInkSpansTheTileHeightRatherThanCollapsingIntoABand() throws {
        let page = try XCTUnwrap(stripPage())
        let image = ContinuousTiles.raster(page: page, tile: CGRect(x: 0, y: 0,
                                                                   width: 900, height: 541),
                                           scale: 1, atDepth: true)
        let measured = ink(image)
        let height = image.cgImage?.height ?? 0
        XCTAssertGreaterThan(height, 0)
        let span = Double(measured.bottom - measured.top) / Double(height)
        XCTAssertGreaterThan(span, 0.9,
                             "the ink spans \(Int(span * 100))% of the tile; a "
                             + "compressed band is what #61 looked like")
    }

    /// Scale is what fits the strip's height to the canvas; the raster has to
    /// honour it rather than drawing at the page's own size.
    func testTheRasterHonoursTheFittedScale() throws {
        let page = try XCTUnwrap(stripPage())
        let scale: CGFloat = 2
        let tile = CGRect(x: 0, y: 0, width: 900, height: 541 * scale)
        let image = ContinuousTiles.raster(page: page, tile: tile, scale: scale,
                                           atDepth: true)
        let measured = ink(image)
        XCTAssertGreaterThan(measured.fraction, 0.8,
                             "at 2x the page still fills its tile")
    }

    /// A tile off the end of the page is blank, not a repeat of the last one.
    func testATileBeyondTheStripIsBlank() throws {
        let page = try XCTUnwrap(stripPage())
        let image = ContinuousTiles.raster(page: page,
                                           tile: CGRect(x: 20000, y: 0, width: 900, height: 541),
                                           scale: 1, atDepth: true)
        XCTAssertLessThan(ink(image).fraction, 0.05)
    }
}
