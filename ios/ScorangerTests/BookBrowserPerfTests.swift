import PDFKit
import XCTest

/// What the book browser costs on a book the size of a Real Book.
///
/// The report was "too slow to scroll a big book" and "after a while it got
/// stuck". A ten-page fixture cannot show either, so the book here is the size
/// the reader's is: several hundred pages, each carrying enough drawing that a
/// raster is real work rather than a memset.
final class BookBrowserPerfTests: XCTestCase {

    /// The sizes the browser actually draws at, in POINTS.
    /// The strip's cell and the page big enough to read a title off.
    private static let stripCell = CGSize(width: 52, height: 68)
    private static let readingPage = CGSize(width: 323, height: 420)
    /// What the shipped call sites ASK for: each doubles the drawn size by
    /// hand for retina before calling.
    private static let shippedStrip = CGSize(width: 104, height: 136)
    private static let shippedPage = CGSize(width: 646, height: 840)

    /// A book the size of the one that broke.
    ///
    /// 512 pages, each with a page number, a title line and forty staff-like
    /// rules, so `PDFPage.thumbnail` has content to rasterise. Built once and
    /// shared: making it is seconds, and every measurement here wants the same
    /// book.
    private static let book: PDFDocument = {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for page in 0..<512 {
                context.beginPage()
                UIColor.black.setFill()
                ("Tune \(page + 1)" as NSString).draw(
                    at: CGPoint(x: 60, y: 48),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 22)])
                for line in 0..<40 {
                    UIRectFill(CGRect(x: 48, y: 96 + line * 16, width: 516, height: 1))
                }
                for note in 0..<120 {
                    let x = 56 + (note % 30) * 17
                    let y = 100 + (note / 30) * 64 + (note * 7) % 40
                    UIBezierPath(ovalIn: CGRect(x: x, y: y, width: 7, height: 5)).fill()
                }
            }
        }
        return PDFDocument(data: data)!
    }()

    private var book: PDFDocument { Self.book }

    /// The book is the size that broke, so nothing here is measured on a
    /// fixture that could not reproduce it.
    func testTheFixtureIsTheSizeThatBroke() {
        XCTAssertEqual(book.pageCount, 512)
    }

    // MARK: - what one raster costs

    /// A picture drawn at 52x68 points on a 2x display needs 104x136 pixels.
    /// Anything more is work and memory spent on nothing.
    func testARasterIsNoBiggerThanThePixelsItIsDrawnWith() throws {
        ThumbnailCache.shared.clear()
        let drawn = Self.stripCell
        let image = try XCTUnwrap(
            ThumbnailCache.shared.image(document: book, index: 0, size: drawn))
        let cg = try XCTUnwrap(image.cgImage)
        let scale = UIScreen.main.scale
        let wanted = (w: Int((drawn.width * scale).rounded()),
                      h: Int((drawn.height * scale).rounded()))
        print("RASTER asked \(drawn) -> image \(image.size) @\(image.scale) "
              + "= \(cg.width)x\(cg.height)px, wanted \(wanted.w)x\(wanted.h)px, "
              + "\(cg.bytesPerRow * cg.height) bytes")
        XCTAssertLessThanOrEqual(cg.width, wanted.w + 2,
                                 "rastered wider than it is drawn")
        XCTAssertLessThanOrEqual(cg.height, wanted.h + 2,
                                 "rastered taller than it is drawn")
    }

    /// What the browser holds after a reader has been through the book: every
    /// page in the strip and every page they stopped on, big.
    func testWhatTheBrowserHoldsAfterAWalkThroughTheBook() throws {
        ThumbnailCache.shared.clear()
        var thumbBytes = 0
        var pageBytes = 0
        for index in 0..<book.pageCount {
            if let thumb = ThumbnailCache.shared.image(document: book, index: index,
                                                       size: Self.shippedStrip),
               let cg = thumb.cgImage {
                thumbBytes += cg.bytesPerRow * cg.height
            }
        }
        // Every eighth page stopped on, which over 512 pages is 64 stops --
        // a conservative reading of "after a while".
        for index in stride(from: 0, to: book.pageCount, by: 8) {
            if let page = ThumbnailCache.shared.image(document: book, index: index,
                                                      size: Self.shippedPage),
               let cg = page.cgImage {
                pageBytes += cg.bytesPerRow * cg.height
            }
        }
        print("HELD strip \(thumbBytes / (1 << 20))MB over \(book.pageCount) pages, "
              + "reading pages \(pageBytes / (1 << 20))MB over 64 stops, "
              + "worst held = 200 entries x biggest = "
              + "\(200 * (pageBytes / 64) / (1 << 20))MB")
    }

    // MARK: - what a scroll costs

    /// A flick through a hundred pages of the strip, timed.
    ///
    /// The number to read is the total: this is what the main thread was made
    /// to do inline, one raster per cell the lazy stack built.
    func testTheCostOfAFlickThroughAHundredPages() {
        ThumbnailCache.shared.clear()
        let start = PerfClock.now
        for index in 0..<100 {
            _ = ThumbnailCache.shared.image(document: book, index: index,
                                            size: Self.shippedStrip)
        }
        let elapsed = PerfClock.now - start
        print("FLICK 100 strip cells drawn in \(Int(elapsed * 1000))ms "
              + "(\(Int(elapsed * 10))ms per cell)")
    }

    /// The same hundred cells a second time, which is what scrolling back over
    /// them costs once they are held.
    func testScrollingBackOverPagesAlreadyDrawn() {
        ThumbnailCache.shared.clear()
        for index in 0..<100 {
            _ = ThumbnailCache.shared.image(document: book, index: index,
                                            size: Self.shippedStrip)
        }
        let start = PerfClock.now
        for index in 0..<100 {
            _ = ThumbnailCache.shared.image(document: book, index: index,
                                            size: Self.shippedStrip)
        }
        print("REFLICK 100 held cells in \(Int((PerfClock.now - start) * 1000))ms")
    }
}

/// The same measurements against a REAL scanned book, when one is put in
/// reach.
///
/// The synthetic book above is vector, and a vector page rasterises in a
/// quarter of a millisecond -- which is not what a fake book is. A scan is a
/// full-page JPEG per page, and DECODING it is where the time goes.
///
/// Put one at `/tmp/scoranger-big-book.pdf` (or name it in
/// `SCORANGER_BIG_BOOK`, which reaches a run driven from a scheme) and these
/// measure against it; with no book there they SKIP, so nothing in the gate
/// depends on a file that is not in the repository. One is made by repeating
/// a scanned page: see the note in this file's commit.
final class ScannedBookPerfTests: XCTestCase {

    private static let stripCell = CGSize(width: 104, height: 136)
    private static let readingPage = CGSize(width: 646, height: 840)

    private func openBook() throws -> PDFDocument {
        let named = ProcessInfo.processInfo.environment["SCORANGER_BIG_BOOK"]
        let candidates = [named, "/tmp/scoranger-big-book.pdf"].compactMap { $0 }
        guard let path = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0)
        }) else {
            throw XCTSkip("no big book at \(candidates.joined(separator: ", "))")
        }
        return try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: path)),
                             "no book at \(path)")
    }

    func testWhatOneScannedPageCostsToDraw() throws {
        let book = try openBook()
        ThumbnailCache.shared.clear()
        print("SCANBOOK \(book.pageCount) pages")
        var each: [Double] = []
        for index in 0..<40 {
            let start = PerfClock.now
            _ = ThumbnailCache.shared.image(document: book, index: index,
                                            size: Self.stripCell)
            each.append((PerfClock.now - start) * 1000)
        }
        let sorted = each.sorted()
        print("SCAN-THUMB 40 cells: median \(Int(sorted[20]))ms, "
              + "worst \(Int(sorted[39]))ms, total \(Int(each.reduce(0, +)))ms")
    }

    /// A flick: the cells a fast horizontal scroll builds, one after another,
    /// which is what the main thread was made to do inline.
    func testTheCostOfAFlickAcrossAScannedBook() throws {
        let book = try openBook()
        ThumbnailCache.shared.clear()
        let start = PerfClock.now
        for index in 0..<120 {
            _ = ThumbnailCache.shared.image(document: book, index: index,
                                            size: Self.stripCell)
        }
        let ms = (PerfClock.now - start) * 1000
        print("SCAN-FLICK 120 strip cells in \(Int(ms))ms "
              + "(\(Int(ms / 120))ms per cell)")
    }

    func testWhatAScannedReadingPageCostsAndHolds() throws {
        let book = try openBook()
        ThumbnailCache.shared.clear()
        var bytes = 0
        let start = PerfClock.now
        for index in stride(from: 0, to: 200, by: 4) {
            if let image = ThumbnailCache.shared.image(document: book, index: index,
                                                       size: Self.readingPage),
               let cg = image.cgImage {
                bytes += cg.bytesPerRow * cg.height
            }
        }
        let ms = (PerfClock.now - start) * 1000
        print("SCAN-PAGE 50 reading pages in \(Int(ms))ms (\(Int(ms / 50))ms each), "
              + "holding \(bytes / (1 << 20))MB")
    }
}

/// What the process is actually holding, which is the only thing that can
/// explain "after a while it got stuck".
///
/// `phys_footprint` is the number jetsam judges an app by -- not resident
/// size, not what a cache thinks it holds. Read from `task_vm_info`.
enum Footprint {
    static var bytes: Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size)
            / mach_msg_type_number_t(MemoryLayout<natural_t>.size)
        let ok = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return ok == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }
    static var mb: Int { bytes / (1 << 20) }
}

/// A reader working through a big book, and what the app is holding when they
/// are done.
final class BookBrowserFootprintTests: XCTestCase {

    private static let stripCell = CGSize(width: 104, height: 136)
    private static let readingPage = CGSize(width: 646, height: 840)

    private func openBook() throws -> PDFDocument {
        let named = ProcessInfo.processInfo.environment["SCORANGER_BIG_BOOK"]
        let candidates = [named, "/tmp/scoranger-big-book.pdf"].compactMap { $0 }
        guard let path = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0)
        }) else {
            throw XCTSkip("no big book at \(candidates.joined(separator: ", "))")
        }
        return try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: path)))
    }

    /// "After a while": the strip scrolled through the whole book, and every
    /// twentieth page stopped on and read.
    func testWhatIsHeldAfterAWhileWithABigBook() throws {
        let book = try openBook()
        ThumbnailCache.shared.clear()
        let before = Footprint.mb
        for index in 0..<book.pageCount {
            _ = ThumbnailCache.shared.image(document: book, index: index,
                                            size: Self.stripCell)
            if index % 20 == 0 {
                _ = ThumbnailCache.shared.image(document: book, index: index,
                                                size: Self.readingPage)
            }
        }
        let after = Footprint.mb
        print("FOOTPRINT before \(before)MB, after a walk through "
              + "\(book.pageCount) pages \(after)MB (grew \(after - before)MB)")
        ThumbnailCache.shared.clear()
        print("FOOTPRINT after clear \(Footprint.mb)MB")
    }
}
