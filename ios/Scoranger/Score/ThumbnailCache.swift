import PDFKit
import UIKit

/// Page thumbnails for the strips, rendered once each -- and rendered
/// ANYWHERE BUT the main thread.
///
/// The strip used to draw only the six pages either side of the one you were
/// on and leave the rest as empty placeholders -- so a nine-page score showed
/// seven pages and two blanks, which reads as a broken render rather than as
/// a deliberate budget. The budget was real: the strip is a plain HStack, so
/// every thumbnail was built on every pass, and re-rasterising sixty pages per
/// pass is what §9.7 was avoiding.
///
/// Two changes made the window unnecessary. The strip is lazy, so only the
/// thumbnails on screen are built at all; and each one is rasterised ONCE and
/// kept here, so scrolling back over a page costs a dictionary lookup.
///
/// # What a 512-page book then taught it
///
/// "Too slow to scroll a big book", and "after a while it got stuck". Two
/// faults, both here:
///
///  1. **The drawing was the body.** `image(...)` rasterises on whatever
///     thread asks, and the asker was `View.body` -- so every cell the lazy
///     strip built stopped the main thread for one PDF page. Measured against
///     a 512-page scan: 4 ms a cell on a Mac, and a flick sweeps hundreds. It
///     is worse than slow, because there is nothing to CANCEL: a cell the
///     reader has already scrolled past is still drawn, because drawing it is
///     how the view is made. `request(...)` is the answer -- the raster goes
///     to a queue, and the ask is withdrawn when the cell goes away.
///  2. **The ceiling was a COUNT.** 200 entries, over pictures that differ
///     37-fold: a strip cell is 56KB and a page big enough to read a title off
///     is 2.1MB, so the real ceiling was 413MB of page images -- and this was
///     the one raster store in the app that a memory warning did not clear,
///     so under pressure the app shed the score the reader was looking at and
///     kept the book they had scrolled past. Both fixed below: `MemoCache`
///     bounds it in BYTES, and a memory warning empties it.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    /// Bounded in bytes, least-recently-used out first -- the canvas's own
    /// store, under a smaller budget. See `PageThumbnails.budget` for the
    /// arithmetic behind the number.
    private let images = MemoCache<String, UIImage>(budget: PageThumbnails.budget)

    /// What it is allowed to hold, and what it holds -- for the tests and the
    /// diagnostics panel.
    static var budget: Int { PageThumbnails.budget }
    var heldBytes: Int { images.bytes }
    var heldCount: Int { images.count }

    /// One token per document, minted on first sight and dropped when the
    /// document is.
    ///
    /// The key used to be the document's ADDRESS. An address is only unique
    /// among documents that are alive at the same time, and these are not: a
    /// new engraving is made on every render and the previous one is released,
    /// so the next `PDFDocument` can land on the address the last one had --
    /// and inherit a whole score's worth of its thumbnails. The strip is what
    /// made the pictures unreadable; this is what could make them the wrong
    /// score's.
    ///
    /// Weak keys, so a document that goes away takes its token with it and the
    /// table cannot grow without bound.
    private let tokens = NSMapTable<PDFDocument, NSString>.weakToStrongObjects()
    private var nextToken = 0
    private let lock = NSLock()

    /// Where pages are drawn when a view asks for one.
    ///
    /// ONE at a time, deliberately. The win is getting the raster off the main
    /// thread, not drawing several at once: PDFKit gives no guarantee about
    /// two threads inside one `PDFDocument`, and a strip only ever needs the
    /// dozen cells on screen. A queue is what makes an ask WITHDRAWABLE -- an
    /// operation cancelled before it starts never rasterises at all, which is
    /// what keeps a flick from still drawing page 40 when the reader is at 300.
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.irllabs.scoranger.thumbnails"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    private init() {
        // A memory warning empties it. The pictures can all be drawn again;
        // being killed cannot be undone. `CanvasRasters` has done this since
        // the watchdog first took the app; this store was left out.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: nil) { [weak self] _ in self?.clear() }
    }

    /// A key that cannot collide between documents: two scores both have a
    /// page 1, and they do not look alike. Nor can a document inherit the key
    /// of one that has been released.
    ///
    /// The SIZE is part of it, because the same page is now drawn at two of
    /// them: the book browser shows page 137 as a thumbnail in its strip and
    /// as a page big enough to read a tune's title off, and a key that named
    /// only the page handed whichever asked second the other one's raster --
    /// a 104-point thumbnail stretched over a 420-point page.
    static func key(document: PDFDocument, index: Int,
                    size: CGSize = .zero) -> String {
        "\(shared.token(for: document))#\(index)"
            + (size == .zero ? "" : "@\(Int(size.width))x\(Int(size.height))")
    }

    private func token(for document: PDFDocument) -> String {
        lock.lock()
        defer { lock.unlock() }
        if let existing = tokens.object(forKey: document) { return existing as String }
        nextToken += 1
        let minted = "d\(nextToken)" as NSString
        tokens.setObject(minted, forKey: document)
        return minted as String
    }

    /// Already drawn, or nothing. NEVER rasterises, so a view body can ask it
    /// on every pass without the main thread paying for a PDF page.
    func cached(document: PDFDocument, index: Int, size: CGSize) -> UIImage? {
        images.held(Self.key(document: document, index: index, size: size))
    }

    /// Draw it now, on the calling thread.
    ///
    /// Fine off the main thread, and fine where there is nothing else to do --
    /// the tests, a caller already on a background queue. A VIEW BODY should
    /// call `cached` and `request` instead; see the note at the top of the
    /// file for what happens when it does not.
    @discardableResult
    func image(document: PDFDocument, index: Int, size: CGSize) -> UIImage? {
        let key = Self.key(document: document, index: index, size: size)
        if let held = images.held(key) { return held }
        guard let page = document.page(at: index) else { return nil }
        let span = PerfMetrics.shared.begin(PerfMetrics.Name.thumbnail)
        let drawn = page.thumbnail(of: size, for: .mediaBox)
        span?.end()
        images.store(drawn, for: key, bytes: CanvasRasters.bytes(of: drawn))
        return drawn
    }

    /// Draw it off the main thread, and stop if the asker loses interest.
    ///
    /// Cancelling the calling task cancels the operation. One that has not
    /// started is dropped without rasterising anything, which is the whole
    /// point: a lazy strip creates and destroys cells as fast as a finger
    /// moves, and every cell that goes away takes its request with it.
    ///
    /// nil for a page that will not draw AND for a request that was abandoned.
    /// The caller tells them apart by asking whether it was cancelled --
    /// `PageThumbnails.phase(drew:abandoned:)` -- because a warning triangle
    /// on every page of a fast scroll is worse than no picture.
    func request(document: PDFDocument, index: Int, size: CGSize) async -> UIImage? {
        if let held = cached(document: document, index: index, size: size) {
            return held
        }
        let operation = RasterOperation { [weak self] in
            self?.image(document: document, index: index, size: size)
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
                // Weak, so the block and the operation do not hold each other:
                // the queue keeps the operation alive until this has run.
                operation.completionBlock = { [weak operation] in
                    continuation.resume(returning: operation?.drawn)
                }
                queue.addOperation(operation)
            }
        } onCancel: {
            operation.cancel()
        }
    }

    func clear() { images.clear() }
}

/// One page, drawn off the main thread and abandonable.
///
/// An `Operation` rather than a `DispatchWorkItem` because a queue can be told
/// to drop it: `isCancelled` is checked once here, and a cancelled operation
/// that never started never reaches this at all.
private final class RasterOperation: Operation, @unchecked Sendable {
    private let draw: () -> UIImage?
    private(set) var drawn: UIImage?

    init(draw: @escaping () -> UIImage?) {
        self.draw = draw
    }

    override func main() {
        guard !isCancelled else { return }
        drawn = draw()
    }
}
