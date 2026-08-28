import CoreGraphics
import Foundation

/// What the counters say (NAVIGATION_SYSTEM.md 12.11).
///
/// Pure, because "which pages am I looking at" and "which bar is that" are
/// arithmetic over geometry the app already has, and both are easy to get
/// subtly wrong at a spread boundary or a zoom.
enum ScorePosition {

    /// `pp. 3–4 / 12`, or `p. 3 / 12` when one page fills the view.
    static func pageLabel(visible: [Int], total: Int) -> String {
        let shown = visible.sorted()
        guard let first = shown.first, total > 0 else { return "" }
        if shown.count == 1 || first == shown.last {
            return "p. \(first + 1) / \(total)"
        }
        return "pp. \(first + 1)–\((shown.last ?? first) + 1) / \(total)"
    }

    /// Which page indices a viewport covers, given each page's vertical band.
    /// Used for the counter and for the strip's "you are here".
    static func visiblePages(bands: [(index: Int, span: ClosedRange<CGFloat>)],
                             visible: CGRect) -> [Int] {
        let touching = bands.filter {
            $0.span.lowerBound <= visible.maxY && $0.span.upperBound >= visible.minY
        }
        return touching.isEmpty ? (bands.first.map { [$0.index] } ?? []) : touching.map(\.index)
    }

    /// The bar to report: the lowest-numbered measure with anything on screen.
    ///
    /// Lowest rather than nearest-to-centre because a reader asking "where am
    /// I?" means the start of what they can see, and because it does not jump
    /// about when a system scrolls past the midpoint.
    static func bar(measuresOnScreen: [Int]) -> Int? {
        measuresOnScreen.filter { $0 > 0 }.min()
    }
}

// MARK: - Where the counters sit (L29)

extension ScorePosition {

    /// How far in from the trailing edge the page/bar counters sit.
    ///
    /// They are pinned to the trailing edge of the score STACK, which runs the
    /// full width -- so with the chat open they were drawn on top of its own
    /// header and buried the model chip under "pp. 1-2 / 9". The counters
    /// belong to the music, so they stop where the music does.
    ///
    /// On a compact width the chat COVERS the score rather than sitting beside
    /// it, and the counters stay with the score underneath.
    static func counterTrailingInset(chatOpen: Bool, isCompact: Bool,
                                     chatWidth: CGFloat, base: CGFloat) -> CGFloat {
        guard chatOpen, !isCompact else { return base }
        return base + chatWidth
    }
}
