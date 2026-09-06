import CoreGraphics

/// Where the reader is in the document, in 28 points.
///
/// IPHONE_0.6.14 §9.6 and §3 E-A. The thumbnail rail is 96pt of a phone's
/// 266pt chrome budget -- more than a third of everything that is not music --
/// and what it buys there is a row of 52x68 thumbnails, which at that size
/// show that a page has staves on it and nothing else. A scrubber says the one
/// thing the rail was being kept for: where in the piece you are, and how to
/// get somewhere else.
///
/// The rail is NOT deleted. An iPad has the room, the thumbnails are legible
/// there, and an access path is not removed until its replacement exists at
/// that width -- so the two sit at different size classes and neither screen
/// loses anything.
///
/// Pure, so the mapping from a finger to a page is tested without a screen.
enum PageScrubberLayout {

    /// The row's own height, and the tick inside it.
    static let height: CGFloat = 28
    static let tickHeight: CGFloat = 12
    static let currentTickHeight: CGFloat = 18
    static let tickWidth: CGFloat = 2
    /// The narrowest gap between ticks before they stop reading as separate.
    static let minimumPitch: CGFloat = 3

    /// How wide one page's slot is, given the room the ticks have.
    ///
    /// Below the minimum pitch the ticks are drawn at the pitch anyway and
    /// overlap: a 300-page book on a phone is a solid bar, which is honest --
    /// it says "long", and the label beside it says where. Inventing a
    /// scrollable scrubber for that case would put a scroll inside a scroll
    /// inside a scroll.
    static func pitch(width: CGFloat, pages: Int) -> CGFloat {
        guard width > 0, pages > 0 else { return 0 }
        return width / CGFloat(pages)
    }

    /// Whether individual ticks are worth drawing at all.
    static func showsTicks(width: CGFloat, pages: Int) -> Bool {
        pitch(width: width, pages: pages) >= minimumPitch
    }

    /// Where a page's tick sits: the CENTRE of its slot.
    ///
    /// Centres rather than left edges, because the tick is a mark for a page
    /// and not a boundary between two of them -- and because `page(atX:)`
    /// below is its exact inverse only if both agree about that.
    static func x(ofPage index: Int, width: CGFloat, pages: Int) -> CGFloat {
        let pitch = pitch(width: width, pages: pages)
        return (CGFloat(index) + 0.5) * pitch
    }

    /// Which page a finger at `x` is asking for.
    ///
    /// Clamped rather than optional: a finger at the very end of the row means
    /// the last page, and returning nil there would make the ends of the
    /// scrubber -- the two places a reader most often aims for -- dead.
    static func page(atX x: CGFloat, width: CGFloat, pages: Int) -> Int {
        guard width > 0, pages > 0 else { return 0 }
        let slot = Int((x / width) * CGFloat(pages))
        return min(max(slot, 0), pages - 1)
    }

    /// What the row says beside the ticks.
    static func label(page index: Int, pages: Int) -> String {
        guard pages > 0 else { return "" }
        return "page \(min(max(index, 0), pages - 1) + 1)"
    }
}
