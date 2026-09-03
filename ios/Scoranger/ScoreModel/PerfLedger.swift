import Foundation

/// One thing the app did, and how long it took.
struct PerfSample: Equatable {
    /// What was timed. Dotted where it has a family: `bridge.set-metadata`.
    let name: String
    /// Monotonic seconds since some fixed point -- `PerfClock.now`, never a
    /// wall clock, which can step backwards mid-measurement.
    let start: TimeInterval
    let duration: TimeInterval

    var end: TimeInterval { start + duration }
}

/// What a name cost, over the samples held.
///
/// The spread and not only the total: a median of 15 ms with a p95 of 900 ms is
/// a different bug from 200 ms every time, and a mean hides both.
struct PerfSummary: Equatable {
    let name: String
    let count: Int
    let total: TimeInterval
    let min: TimeInterval
    let median: TimeInterval
    let p95: TimeInterval
    let max: TimeInterval
}

/// Time attributed to one name inside a window.
struct PerfAttribution: Equatable {
    let name: String
    let count: Int
    /// Seconds of this name's work that fell INSIDE the window.
    let total: TimeInterval
}

/// The arithmetic behind the diagnostics panel, with no clock and no state of
/// its own beyond the samples handed to it, so it can be tested without a
/// device, a score, or a frame.
///
/// The question worth asking is not how long one engrave took. It is: the
/// reader tapped, waited a second, and what was the app DOING? That is
/// attribution over a window -- and when the answer is "nothing this knows how
/// to name", `unaccounted` says so, which is a finding rather than a shrug.
struct PerfLedger {

    /// Per name. Bounded because this can be left on: a continuous scroll
    /// rasterises tiles by the hundred, and a diagnostic that grows without
    /// limit becomes the performance problem it was added to find.
    static let keepPerName = 200

    private var samples: [String: [PerfSample]] = [:]
    private var order: [String] = []

    init() {}

    mutating func record(_ name: String, start: TimeInterval, duration: TimeInterval) {
        if samples[name] == nil { order.append(name) }
        samples[name, default: []].append(
            PerfSample(name: name, start: start, duration: duration))
        // oldest out: what is on screen NOW is what is being diagnosed
        if samples[name]!.count > Self.keepPerName {
            samples[name]!.removeFirst(samples[name]!.count - Self.keepPerName)
        }
    }

    mutating func clear() {
        samples = [:]
        order = []
    }

    var isEmpty: Bool { samples.isEmpty }

    /// Every name, dearest first -- where the time went.
    func summaries() -> [PerfSummary] {
        order.compactMap { name in
            guard let rows = samples[name], !rows.isEmpty else { return nil }
            let sorted = rows.map(\.duration).sorted()
            return PerfSummary(name: name,
                               count: sorted.count,
                               total: sorted.reduce(0, +),
                               min: sorted.first ?? 0,
                               median: Self.percentile(sorted, 0.5),
                               p95: Self.percentile(sorted, 0.95),
                               max: sorted.last ?? 0)
        }
        .sorted { $0.total > $1.total }
    }

    /// The most recent sample recorded under `name`, whatever else has landed
    /// since. What the panel shows for "the last time you tapped it".
    func latest(_ name: String) -> PerfSample? {
        samples[name]?.last
    }

    /// What the app was measurably doing between two instants.
    ///
    /// Work that straddles an edge counts only the part inside, so a rasterise
    /// that began before the tap does not get charged to the tap.
    func accounted(from: TimeInterval, to: TimeInterval) -> [PerfAttribution] {
        order.compactMap { name -> PerfAttribution? in
            var total: TimeInterval = 0
            var count = 0
            for s in samples[name] ?? [] {
                let overlap = Swift.min(s.end, to) - Swift.max(s.start, from)
                if overlap > 0 {
                    total += overlap
                    count += 1
                }
            }
            return count == 0 ? nil : PerfAttribution(name: name, count: count,
                                                      total: total)
        }
        .sorted { $0.total > $1.total }
    }

    /// The part of the window nothing accounts for.
    ///
    /// This is the number that matters when a tap takes a second: if the engine
    /// and the renderer between them explain 40 ms of it, the other 960 ms is
    /// the app rebuilding views, and no amount of making the engine faster will
    /// be felt.
    ///
    /// Concurrent work can total more than the window it sits in -- four tiles
    /// on four threads -- so this floors at zero rather than reporting a
    /// negative wait.
    func unaccounted(from: TimeInterval, to: TimeInterval) -> TimeInterval {
        let window = Swift.max(0, to - from)
        let busy = accounted(from: from, to: to).reduce(0) { $0 + $1.total }
        return Swift.max(0, window - busy)
    }

    // MARK: - Reading it back

    /// `sorted` must be sorted ascending. Nearest-rank, which for the small
    /// samples this holds is the honest reading: p95 of five samples IS the
    /// slowest of them, and interpolating would invent a number.
    static func percentile(_ sorted: [TimeInterval], _ q: Double) -> TimeInterval {
        guard !sorted.isEmpty else { return 0 }
        if sorted.count == 1 { return sorted[0] }
        if q == 0.5 {
            // the median of an even count is the middle pair, which is what
            // anyone reading "median" expects to see
            let mid = sorted.count / 2
            return sorted.count % 2 == 0
                ? (sorted[mid - 1] + sorted[mid]) / 2
                : sorted[mid]
        }
        let rank = Int((q * Double(sorted.count)).rounded(.up)) - 1
        return sorted[Swift.min(Swift.max(rank, 0), sorted.count - 1)]
    }

    /// Milliseconds, at a precision that does not pretend. Under 100 ms one
    /// decimal is real; above it, it is noise.
    static func ms(_ seconds: TimeInterval) -> String {
        let ms = seconds * 1000
        if ms >= 100 { return "\(Int(ms.rounded())) ms" }
        return String(format: "%.1f ms", ms)
    }
}
