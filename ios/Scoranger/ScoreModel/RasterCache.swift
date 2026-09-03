import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// What a picture of part of a score IS, so the same request twice can be
/// recognised as the same request.
///
/// `document` is a string the canvas owns -- slug, version and layout -- and
/// NOT the `PDFPage`'s object identity. A pointer is not an identity here: a
/// page freed when the reader switches version can be replaced by a new page at
/// the same address, and the cache would then answer with the previous score's
/// music. A string that names what was engraved cannot do that.
struct RasterKey: Hashable {
    /// Which engraving: "<slug>/<version>/<layout>".
    let document: String
    let page: Int
    /// The window drawn, in surface points.
    let tile: CGRect
    /// Surface points per PDF point.
    let scale: CGFloat
    /// Pixels per surface point.
    let detail: CGFloat
}

/// Rastered pictures, kept until the memory they cost is needed for newer ones.
///
/// ### Why this exists
///
/// `ZoomableScroll.updateUIView` assigns `host.rootView = AnyView(content())`,
/// which re-renders the whole canvas. That is deliberate -- a new raster scale
/// or a new pen has to reach the pages -- but `updateUIView` runs whenever
/// `ScorePagesView`'s body is re-evaluated, and that view holds
/// `@EnvironmentObject var state: AppState`. So EVERY publish on AppState
/// redraws every page or tile from the PDF: opening the version band, the
/// manifest poll landing, the ink tool changing, a selection being made.
///
/// In paged layout that is one or two `PDFPage.thumbnail` calls and costs
/// tens of milliseconds. In continuous layout it is one `drawPDFPage` per tile
/// over a strip twenty thousand points wide, and it is the whole of the 12x
/// the version dropdown costs there.
///
/// Rather than stop the rebuild -- the rebuild is how a new zoom reaches the
/// pages -- the DRAWING is made cheap to repeat. A rebuild that finds every
/// tile already drawn is a dictionary lookup per tile.
///
/// ### The budget is the point
///
/// The watchdog has killed this app for holding too many rasters before (see
/// `PDFPageImage.maxRasterWidth`), so this is bounded in BYTES and evicts
/// least-recently-used first, and it empties itself on a memory warning. A
/// cache with no ceiling would be the next thing to kill the app.
final class RasterCache<Value>: @unchecked Sendable {

    /// What the store may hold. Sized against what one strip costs: the two or
    /// three tiles drawn at depth are the expensive ones (a 900pt tile at 2x
    /// over a 900pt-tall strip is about 13MB), the dozen coarse ones are under
    /// half a megabyte each. 96MB holds a strip at two scales -- which is what
    /// opening the band and closing it again asks for -- and no more.
    static var defaultBudget: Int { 96 << 20 }

    private struct Entry {
        let value: Value
        let bytes: Int
        /// When it was last handed out. Monotonic within this store.
        var used: Int
    }

    private let budget: Int
    private let lock = NSLock()
    private var entries: [RasterKey: Entry] = [:]
    private var clock = 0
    private var held = 0

    /// Hits and misses since the last `clear()`, for a diagnostic to read. Not
    /// published and not logged: a counter that publishes would invalidate the
    /// views this exists to stop invalidating.
    private var hitCount = 0
    private var missCount = 0

    var hits: Int { lock.withLock { hitCount } }
    var misses: Int { lock.withLock { missCount } }

    init(budget: Int = RasterCache.defaultBudget) {
        self.budget = budget
    }

    /// The picture for this key, drawn only if it is not already held.
    ///
    /// `cost` is asked what the drawn value takes up, because an image's
    /// backing store is not something to guess at from the size requested --
    /// `CGImage.bytesPerRow` rounds, and the rounding is what fills a budget.
    func value(for key: RasterKey, cost: (Value) -> Int,
               make: () -> Value) -> Value {
        lock.lock()
        if var entry = entries[key] {
            clock += 1
            entry.used = clock
            entries[key] = entry
            hitCount += 1
            lock.unlock()
            return entry.value
        }
        missCount += 1
        lock.unlock()

        // Drawn OUTSIDE the lock: a raster is milliseconds of CoreGraphics and
        // holding a lock across it would serialise every canvas in the app
        // behind the slowest tile. Two threads racing the same key both draw
        // and the second overwrites the first, which costs one wasted raster
        // and never a wrong picture.
        let made = make()
        let bytes = max(cost(made), 0)

        lock.lock()
        defer { lock.unlock() }
        // Bigger than the whole budget: hand it back, never hold it.
        guard bytes <= budget else { return made }
        if let previous = entries[key] { held -= previous.bytes }
        clock += 1
        entries[key] = Entry(value: made, bytes: bytes, used: clock)
        held += bytes
        evictDownToBudget()
        return made
    }

    /// What is held, for the tests and the diagnostics panel.
    var count: Int { lock.withLock { entries.count } }
    var bytes: Int { lock.withLock { held } }

    func clear() {
        lock.withLock {
            entries = [:]
            held = 0
            hitCount = 0
            missCount = 0
        }
    }

    /// Least-recently-used out first. Called with the lock held.
    private func evictDownToBudget() {
        guard held > budget else { return }
        // Sorting is O(n log n) over a few dozen entries and happens only when
        // the budget is exceeded, which is once per scale change at worst.
        for (key, entry) in entries.sorted(by: { $0.value.used < $1.value.used }) {
            guard held > budget else { return }
            entries.removeValue(forKey: key)
            held -= entry.bytes
        }
    }
}

private extension NSLock {
    func withLock<T>(_ work: () -> T) -> T {
        lock()
        defer { unlock() }
        return work()
    }
}

#if canImport(UIKit)
/// The canvas's own store, and the bytes an image costs.
enum CanvasRasters {
    static let shared = RasterCache<UIImage>()

    /// Four bytes a pixel, which is what an `UIGraphicsImageRenderer` image and
    /// a `PDFPage.thumbnail` both are. Measured from the CGImage rather than
    /// from the size asked for, because both round.
    static func bytes(of image: UIImage) -> Int {
        guard let cg = image.cgImage else {
            return Int(image.size.width * image.scale
                       * image.size.height * image.scale * 4)
        }
        return cg.bytesPerRow * cg.height
    }

    /// A memory warning empties it. The pictures can all be drawn again; being
    /// killed cannot be undone.
    static func observeMemoryWarnings() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: nil) { _ in shared.clear() }
    }
}
#endif
