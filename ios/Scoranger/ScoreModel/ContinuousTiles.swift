import CoreGraphics

/// The geometry of the continuous strip.
///
/// Continuous mode engraves the whole score as ONE Verovio page with no system
/// breaks. An eleven-page quartet comes back about 21000pt wide and 540pt tall.
/// That cannot be drawn the way a page is drawn: `PDFPageImage` rasterises a
/// whole page into one `UIImage` and caps it at 5200px, which would draw this
/// strip at a quarter of its resolution -- and raising the cap to fit it is how
/// the watchdog kills the app (the note on `maxRasterWidth` records that
/// happening at 380MB).
///
/// So the strip is cut into tiles and only the tiles near the viewport are
/// drawn at full resolution. It is the same bargain `SpreadLayout.visibleRows`
/// already makes for pages, one axis over.
enum ContinuousTiles {
    /// Tile width in surface points. Wide enough that a scroll crosses few
    /// boundaries, small enough that one tile is a cheap raster.
    static let tileWidth: CGFloat = 900

    /// Room left above and below the strip, matching the paged canvas.
    static let margin: CGFloat = 12

    /// The scale that fits the strip's HEIGHT to the viewport.
    ///
    /// Continuous mode is bound by height, never by width -- the width is the
    /// whole score and fitting it would render the music invisible. This is the
    /// amendment to the paged canvas's fit-page zoom floor (NAV_REVISION §6.4):
    /// here the floor is fit-height.
    static func fittedScale(pageSize: CGSize, viewport: CGSize,
                            bottomChrome: CGFloat = 0) -> CGFloat {
        guard pageSize.width > 0, pageSize.height > 0,
              viewport.height > 0 else { return 1 }
        let clear = max(viewport.height - margin * 2 - max(bottomChrome, 0), 1)
        return max(clear / pageSize.height, 0.01)
    }

    /// The tiles covering a strip of this size, in surface points.
    ///
    /// The last tile is short rather than overhanging: a tile that ran past the
    /// end would draw white space the reader could scroll into.
    static func tiles(surface: CGSize, tileWidth: CGFloat = tileWidth) -> [CGRect] {
        guard surface.width > 0, surface.height > 0, tileWidth > 0 else { return [] }
        var out: [CGRect] = []
        var x: CGFloat = 0
        while x < surface.width {
            let width = min(tileWidth, surface.width - x)
            out.append(CGRect(x: x, y: 0, width: width, height: surface.height))
            x += tileWidth
        }
        return out
    }

    /// Which tiles are worth drawing at full resolution: the ones the viewport
    /// touches, plus `ahead` either side so a scroll does not run into a blank.
    static func atDepth(tiles: [CGRect], visible: CGRect, ahead: Int = 1) -> Set<Int> {
        guard !tiles.isEmpty else { return [] }
        var touched: [Int] = []
        for (index, tile) in tiles.enumerated() where tile.intersects(visible) {
            touched.append(index)
        }
        // Nothing reported yet (the first frame): the head of the strip is
        // where the reader is, so draw that rather than nothing.
        guard let first = touched.first, let last = touched.last else {
            return Set(0...min(ahead, tiles.count - 1))
        }
        let lower = max(first - ahead, 0)
        let upper = min(last + ahead, tiles.count - 1)
        return Set(lower...upper)
    }

    /// Where a tap lands the reader next: one viewport width on, clamped to the
    /// strip. A tap TURNS THE PAGE in paged mode; there are no pages here, so
    /// it advances by what is on screen (designer's spec, §tap zones).
    static func advanced(from offset: CGFloat, by viewportWidth: CGFloat,
                         direction: Int, surfaceWidth: CGFloat) -> CGFloat {
        let step = viewportWidth * CGFloat(direction)
        let furthest = max(surfaceWidth - viewportWidth, 0)
        return min(max(offset + step, 0), furthest)
    }
}
