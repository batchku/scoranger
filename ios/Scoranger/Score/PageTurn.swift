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
/// | input                     | read        | edit   | performance |
/// |---------------------------|-------------|--------|-------------|
/// | finger drag               | pan         | pan    | pan         |
/// | finger tap, bottom corner | TURN        | TURN   | TURN        |
/// | finger tap, elsewhere     | SELECT      | SELECT | TURN        |
/// | two-finger tap            | undo ink    | undo   | --          |
/// | Pencil drag               | lasso       | ink    | TURN        |
/// | Pencil tap                | add / drop  | --     | TURN        |
///
/// The finger row grew a second entry in 0.6.14 and the arbitration moved with
/// it: `CanvasTap` resolves the whole row in one pure function, and what is
/// left here is what a tap IS and the §6 mode table it consults.
enum PageTurn {
    /// The outer fraction of the canvas, each side, that turns on a tap (§5,
    /// 12.15). 22% of a landscape iPad is a comfortable thumb's reach without
    /// eating the music.
    ///
    /// It is a fraction of the WIDTH only. `CanvasTap.zoneHeightFraction`
    /// anchors it to the bottom as well, which is what made the rest of the
    /// canvas free to select (§12).
    static let zoneFraction: CGFloat = 0.22

    /// A tap is still, and quick. Without both, a slow pan would end as a page
    /// turn under the reader's hand -- the one failure that would make the
    /// score unreadable (§6.2).
    static let tapSlop: CGFloat = 10
    static let tapWindow: TimeInterval = 0.3

    enum Zone: Equatable { case previous, next, centre }

    /// Which zone a point falls in, across the width.
    ///
    /// The horizontal half of the rule. `CanvasTap.corner` is the whole of it,
    /// and is what the canvas asks.
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
        // A finger MAY turn in every mode -- but only in a bottom corner now,
        // because since 0.6.14 a finger tap on the rest of the page selects
        // (Ali's ruling, §12). The two do not compete for a point: the corner
        // answers first and `CanvasTap` gives the point exactly one meaning.
        // The Pencil is free only where nothing else claims it.
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

    // `destination(from:boundaries:zone:)` lived here: a turn used to be an
    // animated scroll to a computed offset in a stack of every page. The canvas
    // shows one unit now, so a turn changes an INDEX and the arithmetic goes
    // with the stack it was computed over (NAV_MODAL_FREE_0.4.2 §6.1).
    //
    // Everything above is unchanged: who may turn, in which mode, in which
    // zone, and what counts as a tap at all. That table is the part that
    // protects the lasso, and it did not move.
}
