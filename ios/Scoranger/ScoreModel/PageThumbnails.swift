import CoreGraphics
import Foundation

/// What a strip of page pictures is allowed to cost, and what a cell knows
/// about its own picture.
///
/// Kept out of the cache and out of the views so both can be checked without
/// a PDF, a screen or an app -- ios/ScorangerTests/PageThumbnailsTests.swift.
enum PageThumbnails {

    /// Four bytes to the pixel, which is what a `PDFPage.thumbnail` is.
    ///
    /// The real cost is read off the CGImage where there is one, because
    /// `bytesPerRow` rounds; this is the arithmetic that SIZES the budget, not
    /// the accounting that enforces it.
    static func bytes(pixelsWide: Int, pixelsHigh: Int) -> Int {
        max(pixelsWide, 0) * max(pixelsHigh, 0) * 4
    }

    /// The two pictures the book browser draws, in PIXELS.
    ///
    /// `PDFPage.thumbnail(of:for:)` answers at scale 1 -- the points asked for
    /// come back as that many pixels -- which is why every call site asks for
    /// twice what it draws at. Halving those requests would halve the memory
    /// and halve the resolution with it, on a retina display.
    static let stripCellPixels = (wide: 104, high: 136)
    static let readingPagePixels = (wide: 646, high: 840)

    /// What the store is allowed to hold.
    ///
    /// Sized against a fake book: every cell of a 512-page strip is
    /// 512 x 56KB = 28MB, and the pages the reader stops on are 2.1MB each. So
    /// 64MB holds a whole big book's strip AND about seventeen reading pages,
    /// and the reader can go back over any of it without paying twice.
    ///
    /// A BYTE bound and not a count. The store was bounded at 200 entries over
    /// pictures that differ 37-fold in size, so its real ceiling was 200
    /// reading pages -- 413MB, measured -- and a count bound cannot see that.
    /// The canvas's own store learned this first: see `MemoCache`.
    static let budget = 64 << 20

    /// How many pictures of one size the budget holds. What the number above
    /// is checked against, so a change to it has to face what it costs.
    static func pagesHeld(pixelsWide: Int, pixelsHigh: Int) -> Int {
        let each = bytes(pixelsWide: pixelsWide, pixelsHigh: pixelsHigh)
        guard each > 0 else { return 0 }
        return budget / each
    }

    /// What a cell of the strip knows about its picture.
    ///
    /// Three states and not two. A page that has not been DRAWN yet and a page
    /// that CANNOT be drawn used to look the same, which is two different
    /// problems wearing one face -- the score's own strip was fixed for this
    /// once and the book's strip inherited the fault when its drawing stopped
    /// being instant.
    enum Phase: Equatable {
        /// Asked for, not yet drawn. A quiet placeholder.
        case pending
        /// Drawn.
        case drawn
        /// Asked for, and the page would not draw. Says so.
        case missing
    }

    /// Where a request lands. `drew` is whether a picture came back; `given up`
    /// is a request abandoned because the reader scrolled past it, which is
    /// NOT a failure and must not be shown as one.
    static func phase(drew: Bool, abandoned: Bool) -> Phase {
        if abandoned { return .pending }
        return drew ? .drawn : .missing
    }
}
