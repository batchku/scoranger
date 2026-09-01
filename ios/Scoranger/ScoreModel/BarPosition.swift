import CoreGraphics
import Foundation

/// Which bar the reader is looking at.
///
/// The `bar 21` readout the navigation system asked for (§4). It was costed as
/// "depends on the vector-score session" when the canvas was a scrolling stack
/// of every page; 0.4.2 made it cheap. The paged canvas shows one page, or one
/// spread, and pans only inside that unit — so the question reduces to "which
/// bars on THIS page does the visible rect overlap", and every measure's frame
/// is already indexed in page coordinates by `ScoreModelBuilder`.
///
/// Pure geometry, so it is tested without an app, a screen or an engine.
enum BarPosition {

    /// One bar's number and where it sits, in page (SVG user) coordinates.
    struct Bar: Equatable {
        let number: Int
        let frame: CGRect
    }

    /// The earliest bar the reader can see, or nil when none is visible.
    ///
    /// The LOWEST number rather than the leftmost frame: on a page with several
    /// systems the leftmost bar of the lower system sits further left than the
    /// rightmost bar of the upper one, and "where am I" means the earliest
    /// music on screen, not the westernmost ink.
    ///
    /// `intersects` is used rather than a containment test because a bar half
    /// on screen is still a bar the reader can see — but touching edge-to-edge
    /// is not overlapping, so stopping exactly on a barline does not claim the
    /// bar beyond it.
    static func first(in visible: CGRect, bars: [Bar]) -> Int? {
        bars.lazy
            .filter { $0.frame.intersects(visible) }
            .map(\.number)
            .min()
    }

    /// The same question for a spread, where the unit is two pages side by side
    /// and each has its own coordinate space and its own visible rect.
    static func first(inPages pages: [(visible: CGRect, bars: [Bar])]) -> Int? {
        pages.compactMap { first(in: $0.visible, bars: $0.bars) }.min()
    }

    /// What the top bar shows. Nil where nothing is known — the remote-engine
    /// path builds no geometry, and a wrong bar number is worse than none.
    static func label(for bar: Int?) -> String? {
        bar.map { "bar \($0)" }
    }
}

extension BarPosition {
    /// Where a page of the current unit sits in scroll-content coordinates.
    ///
    /// Computed rather than measured. A GeometryReader inside the scroll view
    /// never reported: SwiftUI does not re-lay-out a hosted hierarchy as UIKit
    /// scrolls it, and the reader's `onAppear` did not fire at all. The layout
    /// is deterministic anyway -- `pageUnit` is an HStack of equal-width pages
    /// with one gutter between them and a gutter above -- so it is arithmetic,
    /// and arithmetic can be tested without a screen.
    static func pageFrame(position: Int, width: CGFloat, aspect: CGFloat,
                          gutter: CGFloat) -> CGRect {
        CGRect(x: CGFloat(position) * (width + gutter),
               y: gutter,
               width: width,
               height: width * aspect)
    }

    /// Where one numbered bar sits on a page, in page (SVG user) coordinates.
    ///
    /// The FIRST match, because in continuous mode the whole score is one page
    /// and a bar number is unique on it. (A repeated bar is played twice but
    /// engraved once; the repetition lives in the playback timeline, not on
    /// the page.) Nil where the geometry has no such bar, which is every
    /// remote-engine render: that path builds no geometry at all, and the
    /// caller must then follow nothing rather than follow a guess.
    static func frame(ofBar number: Int, among bars: [Bar]) -> CGRect? {
        bars.first { $0.number == number }?.frame
    }

    /// The bars of one page, read out of the geometry the engraver built.
    ///
    /// A `<measure>` element's frame spans the whole bar, which is exactly the
    /// rect wanted here — see `ScoreModelBuilder`'s note that it never uses the
    /// measure element for hit-testing a NOTE for the opposite reason.
    static func bars(onPage page: ScorePage) -> [Bar] {
        page.elements.compactMap { element in
            guard element.kind == .measure, let address = element.address else { return nil }
            return Bar(number: address.measure, frame: element.frame)
        }
    }
}
