import CoreGraphics

/// How wide a page is drawn, and how the pages are grouped into rows.
///
/// Two shapes: one page per row (the scroll everybody has had until now), or
/// two side by side, which is how a player reads a printed score on a stand.
/// The arithmetic lives here rather than in the view because the interesting
/// part — a spread must fit the *width* it is given while a single page is
/// allowed to be as wide as it likes — is worth being able to test.
enum SpreadLayout {
    /// Outer margin either side of the page block.
    static let margin: CGFloat = 12
    /// Gutter between two pages of a spread, and between rows.
    static let gutter: CGFloat = 12
    /// A single page never grows past this, or a wide display stretches one
    /// system across half a metre of glass.
    static let maxSinglePageWidth: CGFloat = 1100

    /// Width of one page.
    ///
    /// A spread has no maximum: with both panels collapsed on a portrait iPad
    /// the two pages together are already narrower than one page was, and
    /// capping them would leave a band of empty ground down the middle.
    static func pageWidth(viewport: CGFloat, spread: Bool) -> CGFloat {
        let usable = max(viewport - margin * 2, 1)
        guard spread else { return min(usable, maxSinglePageWidth) }
        return max((usable - gutter) / 2, 1)
    }

    /// Width of the scrollable content: the page block, or the viewport when
    /// the pages do not fill it (so the canvas stays centred rather than
    /// hugging the left edge).
    static func contentWidth(viewport: CGFloat, spread: Bool) -> CGFloat {
        let page = pageWidth(viewport: viewport, spread: spread)
        let block = spread ? page * 2 + gutter + margin * 2 : page + margin * 2
        return max(block, viewport)
    }

    /// Page indices grouped into rows: `[[0], [1], …]` or `[[0, 1], [2, 3], …]`.
    ///
    /// Page 1 pairs with page 2, the way a two-page score sits on a stand —
    /// no blank recto, because these are engraved pages rather than a bound
    /// book with a cover.
    static func rows(pageCount: Int, spread: Bool) -> [[Int]] {
        guard pageCount > 0 else { return [] }
        guard spread else { return (0..<pageCount).map { [$0] } }
        return stride(from: 0, to: pageCount, by: 2).map { start in
            Array(start..<min(start + 2, pageCount))
        }
    }

    /// Which rows of the page stack are on screen.
    ///
    /// Pure so the decision that governs what gets rastered can be tested
    /// without a scroll view. `heights` are the row heights in content
    /// (unzoomed) points, in order; `visible` is the viewport in the same
    /// space. A row counts as visible if it touches the viewport at all, and
    /// its neighbours are included so a scroll does not arrive at a page that
    /// has not been drawn yet.
    static func visibleRows(heights: [CGFloat], gutter: CGFloat = SpreadLayout.gutter,
                            visible: CGRect, neighbours: Int = 1) -> Set<Int> {
        guard !heights.isEmpty else { return [] }
        var touching: Set<Int> = []
        var y: CGFloat = gutter
        for (index, height) in heights.enumerated() {
            let band = y...(y + height)
            if band.lowerBound <= visible.maxY && band.upperBound >= visible.minY {
                touching.insert(index)
            }
            y += height + gutter
        }
        // Nothing intersected (an offset outside the content, which happens
        // mid-resize): fall back to the first row rather than rendering none.
        if touching.isEmpty { touching.insert(0) }
        for index in touching {
            for step in 1...max(neighbours, 1) {
                if index - step >= 0 { touching.insert(index - step) }
                if index + step < heights.count { touching.insert(index + step) }
            }
        }
        return touching
    }
}
