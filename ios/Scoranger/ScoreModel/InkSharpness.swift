import CoreGraphics

/// How finely the annotation ink is drawn when the score is zoomed in.
///
/// The score zooms by a transform: the hosted view keeps its own geometry and
/// UIKit magnifies it. A raster magnified that way is a raster magnified that
/// way, so the page image re-renders itself at the settled zoom to stay sharp.
/// The PencilKit canvas over it did not, and it is the same picture stretched
/// -- which is why Ali's notes went soft while the notes under them stayed
/// crisp at the same magnification.
///
/// The canvas cannot re-render at a size it does not have. What it can do is
/// draw at a higher `contentScaleFactor`, which is the same idea as the page's
/// finer raster and costs memory the same way, so it is bounded.
enum InkSharpness {

    /// Beyond this the ink is already finer than the display can show, and the
    /// tiles behind a PencilKit canvas are not free. Twelve is the zoom
    /// ceiling; four covers the magnifications a reader actually writes at.
    static let maximumFactor: CGFloat = 4

    /// How much PencilKit is asked to magnify the ink by: the settled zoom,
    /// bounded, and never below 1 (zooming OUT must not degrade what is drawn).
    ///
    /// The canvas is laid out this much larger than the page and scaled back
    /// down by the same amount, so it occupies the page exactly while
    /// PencilKit renders the strokes at the larger size.
    static func canvasZoom(zoom: CGFloat) -> CGFloat {
        guard zoom.isFinite, zoom > 1 else { return 1 }
        return min(zoom, maximumFactor)
    }

    /// The scale to draw the ink at: the screen's own scale multiplied by the
    /// zoom, never finer than `maximumFactor` times it and never coarser than
    /// the screen itself.
    ///
    /// - Parameters:
    ///   - zoom: the settled zoom, as the page raster uses.
    ///   - base: the screen's native scale (2 or 3 on the devices this runs on).
    static func contentScale(zoom: CGFloat, base: CGFloat) -> CGFloat {
        guard base > 0 else { return 1 }
        return base * canvasZoom(zoom: zoom)
    }

    /// Whether a change is worth redrawing for. Assigning a scale re-renders
    /// every stroke, and the zoom settles on quarter steps, so a threshold
    /// below one step would repaint the canvas for nothing.
    static func isWorthRedrawing(from current: CGFloat, to wanted: CGFloat) -> Bool {
        abs(current - wanted) > 0.01
    }
}
