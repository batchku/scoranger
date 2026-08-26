import CoreGraphics
import Foundation

/// The page-turn rules, and the arbitration that keeps them from eating the
/// selection work.
///
/// NAVIGATION_SYSTEM.md §6 is the specification and §9.1 is the risk: turning a
/// page and lassoing music are the SAME gesture with the same input, and no
/// amount of timing or distance tells them apart honestly. So they are
/// separated by mode, and the mode is stated on screen.
///
/// | input                  | read        | edit  | performance |
/// |------------------------|-------------|-------|-------------|
/// | finger drag            | pan         | pan   | pan         |
/// | finger tap, outer zone | TURN        | TURN  | TURN        |
/// | two-finger tap         | undo ink    | undo  | --          |
/// | Pencil drag            | lasso       | ink   | TURN        |
/// | Pencil tap             | add / drop  | --    | TURN        |
enum PageTurn {
    /// The outer fraction of the canvas, each side, that turns on a tap (§5,
    /// 12.15). 22% of a landscape iPad is a comfortable thumb's reach without
    /// eating the music.
    static let zoneFraction: CGFloat = 0.22

    /// A tap is still, and quick. Without both, a slow pan would end as a page
    /// turn under the reader's hand -- the one failure that would make the
    /// score unreadable (§6.2).
    static let tapSlop: CGFloat = 10
    static let tapWindow: TimeInterval = 0.3

    enum Zone: Equatable { case previous, next, centre }

    /// Which zone a point in the canvas falls in.
    static func zone(atX x: CGFloat, width: CGFloat) -> Zone {
        guard width > 0 else { return .centre }
        let edge = width * zoneFraction
        if x <= edge { return .previous }
        if x >= width - edge { return .next }
        return .centre
    }

    /// Did this touch stay still and brief enough to be a tap at all?
    static func isTap(movement: CGFloat, elapsed: TimeInterval) -> Bool {
        movement <= tapSlop && elapsed <= tapWindow
    }

    /// May THIS input turn a page in THIS mode? The table above, in one place.
    static func mayTurn(isPencil: Bool, mode: ScoreMode) -> Bool {
        // A finger never selects and never inks, so its tap is free in every
        // mode -- a single-finger tap on the page did nothing at all before
        // this (§6.2). The Pencil is free only where nothing else claims it.
        isPencil ? mode == .performance : true
    }

    /// The whole decision for one finished touch.
    static func turn(isPencil: Bool, mode: ScoreMode, x: CGFloat, width: CGFloat,
                     movement: CGFloat, elapsed: TimeInterval) -> Zone? {
        guard mayTurn(isPencil: isPencil, mode: mode),
              isTap(movement: movement, elapsed: elapsed) else { return nil }
        let zone = self.zone(atX: x, width: width)
        return zone == .centre ? nil : zone
    }

    /// Where a turn scrolls to.
    ///
    /// A turn is a SCROLL, not a flip (§6.4): the renderer stacks pages
    /// vertically and the turn animates to the next boundary. Nothing about the
    /// layout engine changes, and zooming in does not reset -- it scrolls to
    /// the next boundary at the current zoom (§6.3).
    static func destination(from offset: CGFloat, boundaries: [CGFloat],
                            zone: Zone) -> CGFloat? {
        let sorted = boundaries.sorted()
        guard !sorted.isEmpty else { return nil }
        // a little tolerance, so sitting a pixel off a boundary still advances
        let epsilon: CGFloat = 1
        switch zone {
        case .next:
            return sorted.first { $0 > offset + epsilon }
        case .previous:
            return sorted.last { $0 < offset - epsilon }
        case .centre:
            return nil
        }
    }
}
