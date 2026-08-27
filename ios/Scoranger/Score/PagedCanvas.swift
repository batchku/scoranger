import CoreGraphics
import Foundation

/// The canvas shows exactly one page, or one spread, and nothing else exists
/// on screen (NAV_MODAL_FREE_0.4.2 §6 / NAV_REVISION §6).
///
/// This replaces a tall scroll holding every page. The consequences are worth
/// stating, because they are what make the rest simpler:
///
/// - "You can never see more than two pages" is not a rule that has to be
///   enforced anywhere: it is what fitting ONE unit to the canvas means. The
///   zoom floor is fit, so zooming out cannot reveal a neighbour.
/// - A turn changes an INDEX, not a scroll offset. `PageTurn.destination` and
///   its boundary arithmetic are gone with the stack they were computed over.
/// - The lasso is always inside one page's coordinate space, so the
///   visible-rect → page mapping loses a whole class of edge case.
enum PagedCanvas {
    /// Fit is 1.0 by definition: the whole unit inside the viewport. Below it
    /// there is nothing to see but ground, so it is the floor.
    static let minimumZoom: CGFloat = 1.0
    static let maximumZoom: CGFloat = 12.0

    /// The pages making up the unit at `index`.
    ///
    /// With the spread on, units start on EVEN indices, so page 0 sits alone on
    /// the left of a spread the way a title page does in a real score.
    static func unit(at index: Int, pageCount: Int, spread: Bool) -> [Int] {
        guard pageCount > 0, index >= 0, index < pageCount else { return [] }
        guard spread else { return [index] }
        let first = index - (index % 2)
        return [first, first + 1].filter { $0 < pageCount }
    }

    /// Where a step lands, or nil at the ends. Stepping is ±1, or ±2 in a
    /// spread, so a turn always moves by a whole unit.
    static func step(from index: Int, by direction: Int,
                     pageCount: Int, spread: Bool) -> Int? {
        guard pageCount > 0 else { return nil }
        let stride = spread ? 2 : 1
        let current = spread ? index - (index % 2) : index
        let next = current + direction * stride
        guard next >= 0, next < pageCount else { return nil }
        return next
    }

    /// The index a thumbnail tap should land on: the unit HOLDING that page,
    /// not the page itself, so tapping the right half of a spread does not
    /// scroll the left half off.
    static func index(forPage page: Int, spread: Bool) -> Int {
        guard spread else { return page }
        return page - (page % 2)
    }

    /// Zoom, clamped. This single clamp is what "never more than two pages"
    /// means in code.
    static func clamp(zoom: CGFloat) -> CGFloat {
        min(max(zoom, minimumZoom), maximumZoom)
    }

    /// Is there anywhere to pan? Only past fit; at fit the unit exactly fills
    /// the canvas, so a drag has nothing to move and is free to mean a turn.
    static func canPan(zoom: CGFloat) -> Bool { zoom > minimumZoom }

    /// May a swipe turn the page?
    ///
    /// Only when there is no horizontal slack -- at fit, or already against the
    /// unit's edge while zoomed. Ali's build-with recommendation was STOP at
    /// the edge, so a drag that reaches it does not roll into a turn; the turn
    /// is a second, deliberate gesture, and the tap zones are always there.
    static func swipeMayTurn(zoom: CGFloat, atHorizontalLimit: Bool) -> Bool {
        !canPan(zoom: zoom) || atHorizontalLimit
    }

    /// What a turn does to zoom and pan.
    ///
    /// Zoom PERSISTS -- a violinist reading at 180% stays at 180% -- and pan
    /// resets to the top-left of the new unit, which is what turning a paper
    /// page does.
    static func afterTurn(zoom: CGFloat) -> (zoom: CGFloat, offset: CGPoint) {
        (clamp(zoom: zoom), .zero)
    }

    /// Coalesce rapid turns to the latest index rather than queueing
    /// animations (§6.4 risk 3).
    static func coalesce(pending: Int?, latest: Int) -> Int {
        _ = pending
        return latest
    }
}
