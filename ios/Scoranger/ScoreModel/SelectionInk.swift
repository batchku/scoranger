import CoreGraphics

/// How thick the selection marks are drawn, and where a lasso landed.
///
/// Everything the lasso draws -- its own dashed outline, and the boxes over
/// what it caught -- lives INSIDE the zoom. The pages are laid out at zoom 1
/// and UIScrollView magnifies the whole tree by a transform, so a 1pt outline
/// written in page coordinates is 1pt on screen at 1x and 12pt at 12x. The
/// ceiling used to be 3, which made the error survivable; the render overhaul
/// raised it to 12 and the selection turned into the orange blobs Ali
/// photographed.
///
/// `Playhead` states the same rule for the cursor and the layer that draws it
/// divides every constant by the zoom. This is that rule, for the ink, in one
/// place both the highlight and the lasso outline read from.
enum SelectionInk {

    // MARK: - The sizes, in VIEW points. Each is a size ON SCREEN, at any zoom.

    /// The lasso's outline. Fine rather than crude: at 1.5pt with 6pt dashes it
    /// read as a marquee drawn over the music; a hairline sits with the
    /// engraving instead of on top of it.
    static let lassoWeight: CGFloat = 0.75
    /// Dash on, dash off.
    static let lassoDash: CGFloat = 2.5

    /// The outline around one caught element.
    static let highlightWeight: CGFloat = 1
    /// A hair of padding, so a notehead's box reads as a highlight rather than
    /// a tight outline.
    static let highlightPadding: CGFloat = 3
    /// A box smaller than this is not a box: a stem or a dot would otherwise be
    /// marked by something too small to see.
    static let highlightMinimum: CGFloat = 6
    /// The corner, which is a size on screen like everything else -- an
    /// unscaled 2pt radius is a 24pt roundover at 12x, and the box becomes a
    /// lozenge.
    static let highlightCorner: CGFloat = 2

    // MARK: - The rule

    /// The zoom to divide by: the settled scroll zoom, and 1 for anything that
    /// is not a usable number.
    ///
    /// Zero is the case that matters. A layer can be laid out before the scroll
    /// view has reported anything, and dividing by a zoom of 0 -- or by the
    /// 0.01 floor a `max` would leave -- draws a 75pt slab across the page for
    /// one frame. One is the honest answer to "no zoom yet".
    static func divisor(zoom: CGFloat) -> CGFloat {
        guard zoom.isFinite, zoom > 0.01 else { return 1 }
        return zoom
    }

    /// A size stated in view points, expressed in the CONTENT coordinates the
    /// mark is actually drawn in, so it comes out that size on screen.
    static func onScreen(_ points: CGFloat, zoom: CGFloat) -> CGFloat {
        points / divisor(zoom: zoom)
    }

    /// The dash pattern for the lasso outline, at this zoom.
    static func lassoDashes(zoom: CGFloat) -> [CGFloat] {
        let step = onScreen(lassoDash, zoom: zoom)
        return [step, step]
    }

    /// The drawn extent of a highlight box along one axis.
    ///
    /// `engraved` is the element's own measurement in page (SVG user) units and
    /// `scale` is content points per page unit -- so their product is content
    /// points and scales with the zoom, which is right: the box must stay over
    /// the notehead. The MINIMUM and the PADDING are sizes on screen and must
    /// not, which is the whole distinction this function exists to keep.
    static func highlightExtent(engraved: CGFloat, scale: CGFloat,
                                zoom: CGFloat) -> CGFloat {
        max(engraved * scale, onScreen(highlightMinimum, zoom: zoom))
            + onScreen(highlightPadding, zoom: zoom)
    }
}

/// Where a lasso landed, in the engraving's own coordinates.
///
/// The recognizer reports UNIT (0…1) points of the anchor view the stroke was
/// drawn on, and an anchor covers exactly one engraved page: one sheet in paged
/// mode, the whole strip in continuous. Unit points are dimensionless, which is
/// what lets one conversion serve both -- the strip's surface is in PDF points
/// (16970 wide for a score whose geometry is 383690 SVG units wide) and mixing
/// those two put the play head twenty-two times too far into the piece.
/// Nothing here can make that mistake, because nothing here knows about either
/// number: it is told the page it landed on and multiplies by that page's size.
///
/// The anchor must therefore COVER the page and nothing else. In continuous
/// mode that means the overlay goes on the tile row -- which is the surface,
/// exactly -- and not on the padded container around it.
enum LassoPath {

    /// Unit points of an anchor -> page (SVG user) coordinates.
    static func onPage(unit: [CGPoint], pageSize: CGSize) -> [CGPoint] {
        guard pageSize.width > 0, pageSize.height > 0 else { return [] }
        return unit.map { CGPoint(x: $0.x * pageSize.width,
                                  y: $0.y * pageSize.height) }
    }
}
