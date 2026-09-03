import Foundation
import QuartzCore
import os

/// A monotonic clock. Never `Date()`: the wall clock can step while a
/// measurement is open, and a negative duration in a diagnostic is worse than
/// no diagnostic.
enum PerfClock {
    static var now: TimeInterval { CACurrentMediaTime() }
}

/// An open measurement. `end()` is idempotent, so a span dropped down an error
/// path records once and a span ended twice does not double-count.
final class PerfSpan {
    private let name: String
    private let start: TimeInterval
    private var closed = false
    private let signpost: (OSSignposter, OSSignpostIntervalState, StaticString)?

    init(name: String, start: TimeInterval,
         signpost: (OSSignposter, OSSignpostIntervalState, StaticString)? = nil) {
        self.name = name
        self.start = start
        self.signpost = signpost
    }

    func end() {
        guard !closed else { return }
        closed = true
        if let (signposter, state, label) = signpost {
            signposter.endInterval(label, state)
        }
        PerfMetrics.shared.record(name, start: start, duration: PerfClock.now - start)
    }
}

/// Where the app's time goes, when someone has asked.
///
/// Built because nobody had numbers. "Since we introduced these different ways
/// of having both XML and PDFs rendering it has become incredibly slow" is a
/// real report and an unactionable one: the rendering path had just been
/// rewritten, and optimising against a guess would have been worse than doing
/// nothing. So: measure first, and measure the thing the reader named.
///
/// Three properties this has to have, in order:
///
///  1. **Off by default, and free when off.** The gate is a plain `Bool` load
///     before any allocation, any string interpolation, any clock read. A
///     diagnostic that costs 2% is a diagnostic that gets left off and rots.
///  2. **Recordable from any thread.** Tiles rasterise off the main actor, and
///     an instrument that can only be called from one of them measures the
///     wrong half of the app.
///  3. **It never publishes.** The panel takes a `snapshot()` when someone is
///     looking. An `@Published` on the recording path would invalidate views
///     on every sample -- which is the exact bug class being hunted, added by
///     the tool hunting it.
///
/// Intervals also go to `os_signpost`, so Instruments can be pointed at the
/// same names without a second instrumentation pass.
final class PerfMetrics: @unchecked Sendable {

    static let shared = PerfMetrics()

    /// The Settings toggle's key, and the same key `TouchDiagnostics` reads its
    /// own switch from -- diagnostics live together.
    static let defaultsKey = "perfMetrics"

    /// The gate, read on every call. `nonisolated(unsafe)` and deliberately
    /// unlocked: a `Bool` load cannot tear on any device this runs on, and the
    /// worst a race can cost is one sample lost or gained as the switch flips.
    /// Paying for a lock here would break property 1.
    nonisolated(unsafe) private static var enabled = false

    private let lock = NSLock()
    private var dumpTimer: Timer?
    private var ledger = PerfLedger()
    private let signposter = OSSignposter(
        subsystem: "com.irllabs.scoranger", category: "performance")

    private init() {
        Self.enabled = UserDefaults.standard.bool(forKey: Self.defaultsKey)
    }

    var isOn: Bool { Self.enabled }

    /// Called by the Settings toggle. Turning it ON clears what was there, so a
    /// reading is of the session the reader is about to take, not of whatever
    /// the app did at launch three hours ago.
    func setOn(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.defaultsKey)
        if on { clear() }
        Self.enabled = on
    }

    // MARK: - Recording

    func record(_ name: String, start: TimeInterval, duration: TimeInterval) {
        guard Self.enabled else { return }
        lock.lock()
        ledger.record(name, start: start, duration: duration)
        lock.unlock()
    }

    /// Time a synchronous piece of work.
    @discardableResult
    func measure<T>(_ name: String, _ work: () throws -> T) rethrows -> T {
        guard Self.enabled else { return try work() }
        let start = PerfClock.now
        defer { record(name, start: start, duration: PerfClock.now - start) }
        return try work()
    }

    /// Time an asynchronous one -- an engine round trip, a render.
    @discardableResult
    func measure<T>(_ name: String, _ work: () async throws -> T) async rethrows -> T {
        guard Self.enabled else { return try await work() }
        let start = PerfClock.now
        defer { record(name, start: start, duration: PerfClock.now - start) }
        return try await work()
    }

    /// Open a measurement that ends somewhere else -- a callback, a completion
    /// handler, the next frame. Returns nil when off, so the caller's `?.end()`
    /// costs one nil test.
    func begin(_ name: String, _ label: StaticString = "span") -> PerfSpan? {
        guard Self.enabled else { return nil }
        let state = signposter.beginInterval(label)
        return PerfSpan(name: name, start: PerfClock.now,
                        signpost: (signposter, state, label))
    }

    // MARK: - What the reader waited for

    /// Time from now until the frame that shows the result is on the glass.
    ///
    /// This is the only honest way to measure a control whose cost is not in
    /// any one function: flipping `titleMenuOpen` returns in microseconds, and
    /// then SwiftUI rebuilds whatever observes AppState. What the reader
    /// experiences is the frame, so the frame is what is timed -- from the tap
    /// to the render server confirming the transaction that carries it.
    @MainActor
    func measureUntilPresented(_ name: String) {
        guard Self.enabled else { return }
        let start = PerfClock.now
        // One turn of the run loop later, SwiftUI has processed the state
        // change and the transaction being assembled is the one that will
        // carry it. Its completion fires when that frame is committed.
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                PerfMetrics.shared.record(name, start: start,
                                          duration: PerfClock.now - start)
            }
            CATransaction.commit()
        }
    }

    // MARK: - Reading it back

    /// A copy, taken when someone is looking at the panel. The ledger is a
    /// value type, so nothing here is shared with the recording path.
    func snapshot() -> PerfLedger {
        lock.lock()
        defer { lock.unlock() }
        return ledger
    }

    func clear() {
        lock.lock()
        ledger.clear()
        lock.unlock()
    }

    /// Print the table every few seconds, for a measurement run.
    ///
    /// The panel is for a reader holding an iPad. This is for a sweep: the UI
    /// test drives the app and the numbers come back in the log, rather than
    /// being scraped off a scrolling diagnostic view. Behind a launch argument,
    /// and DEBUG only -- a shipped build has no reason to print anything.
    func startConsoleDumpIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-perfDump"),
              dumpTimer == nil else { return }
        dumpTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            let text = PerfReport.text(PerfMetrics.shared.snapshot())
            print("SCORANGER-PERF\n\(text)\nSCORANGER-PERF-END")
        }
        #endif
    }

    /// The names used, in one place so the panel and the instrumentation cannot
    /// drift into two vocabularies.
    enum Name {
        /// Tap on "N versions" to the frame that shows the band.
        static let versionMenu = "menu.versions open"
        /// Tap on the title to the frame that shows the arrangements band.
        static let titleMenu = "menu.title open"
        /// A whole render pass: engrave, rasterise, and the model built from it.
        static let render = "render (engrave + rasterise)"
        /// One manifest fetch and the library rebuild it triggers.
        static let manifest = "manifest refresh"
        /// One page thumbnail.
        static let thumbnail = "thumbnail"
        /// An engine round trip, suffixed with the op: `bridge.set-metadata`.
        static func bridge(_ op: String) -> String { "bridge.\(op)" }
    }
}
