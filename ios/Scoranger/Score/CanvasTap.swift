import CoreGraphics
import Foundation

/// What a single-finger touch on the canvas MEANS -- one recogniser, one
/// answer, resolved in a fixed order.
///
/// IPHONE_0.6.14 §12. Ali's ruling put finger tap-select on the canvas, which
/// puts it in the same place the page turn already lived. The obvious way to
/// add it -- a second recogniser, or `.simultaneousGesture` -- is exactly what
/// cost the mixer its drag for a release: two claims on one touch, arbitrated
/// by whatever SwiftUI decided that frame, measured at 0.0pt of movement. So
/// there is ONE recogniser, and the decision is a pure function that can be
/// fuzzed (`CanvasTapTests`).
///
/// The order is fixed, and each rule is total -- it either answers or passes:
///
/// 1. more than one finger at ANY moment of the touch -> nothing
/// 2. the lasso is armed -> nothing; the finger is drawing a loop (§9.3)
/// 3. it MOVED -> nothing; that was a pan
/// 4. performance mode -> turn, wherever it landed
/// 5. Pencil -> the §6 table, unchanged: the lasso and the ink own it
/// 6. a bottom corner -> turn
/// 7. anything else -> select what is there, or clear if nothing is
///
/// Rule 3 is `PageTurn.isTap` as §12 wrote it: still, and quick. A finger that
/// stays down longer than that is not a slow tap, it is a PRESS -- §9.2's
/// selecting gesture, where the loupe comes up, the reader slides a little to
/// place the crosshair, and release commits. It arrives already flagged, and
/// carries its own permission to have moved and to have taken its time.
///
/// A press never turns, in any region. It is the one gesture the reader can
/// watch themselves make, so there is nothing to protect them from; and a
/// thumb resting in a corner is a press, which is exactly why it must not turn
/// the page (§6.2).
///
/// Zoom is deliberately NOT a separator. Zoom persists across a turn by design
/// (`PagedCanvas.afterTurn`), so "turns at fit, selects when zoomed" would mean
/// the same tap in the same place doing different things for reasons the reader
/// stopped thinking about pages ago.
enum CanvasTap {

    enum Outcome: Equatable {
        case turn(PageTurn.Zone)
        /// Take what is under the finger into the selection.
        case select
        /// Nothing was under the finger: put the selection down.
        case clear
        /// This touch meant nothing at all.
        case none
    }

    /// The turn zones, which are bottom-anchored CORNERS rather than the
    /// full-height columns they were.
    ///
    /// A column at 22% each side takes 44% of every page, and it took it from
    /// the middle of the staff where the notes are. Anchored to the bottom at
    /// 30% of the height, the same fraction across costs about 13% of the
    /// canvas and costs it where a thumb rests anyway.
    ///
    /// The minimums are for the small end -- an iPhone in landscape, a narrow
    /// split view -- where a percentage of a short side is smaller than a
    /// finger. They are capped so the two corners can never meet: whatever the
    /// canvas, there is a selectable band between them.
    static let zoneFraction: CGFloat = PageTurn.zoneFraction
    static let zoneHeightFraction: CGFloat = 0.30
    static let zoneMinWidth: CGFloat = 64
    static let zoneMinHeight: CGFloat = 88

    /// The width of one corner, and the height of both.
    static func zoneSize(in canvas: CGSize) -> CGSize {
        guard canvas.width > 0, canvas.height > 0 else { return .zero }
        return CGSize(
            width: min(max(canvas.width * zoneFraction, zoneMinWidth), canvas.width * 0.4),
            height: min(max(canvas.height * zoneHeightFraction, zoneMinHeight),
                        canvas.height * 0.5))
    }

    /// Which corner a point falls in, or nil for the rest of the canvas.
    ///
    /// The left is tested first, so a point on a boundary belongs to exactly
    /// one corner even where a pathological canvas would let them overlap.
    static func corner(at point: CGPoint, in canvas: CGSize) -> PageTurn.Zone? {
        let zone = zoneSize(in: canvas)
        guard zone.width > 0, point.y >= canvas.height - zone.height else { return nil }
        if point.x <= zone.width { return .previous }
        if point.x >= canvas.width - zone.width { return .next }
        return nil
    }

    /// Which way a tap turns when the WHOLE canvas turns (performance mode).
    private static func half(at point: CGPoint, in canvas: CGSize) -> PageTurn.Zone {
        point.x < canvas.width / 2 ? .previous : .next
    }

    /// The whole decision for one finished touch.
    ///
    /// `hit` is the caller's hit test: whether the geometry has anything under
    /// the finger. It arrives as a fact rather than being consulted mid-rule,
    /// because a turn that depended on what was under the thumb would be a page
    /// turn the reader could not predict -- rejected in §12.
    static func tap(at point: CGPoint, in canvas: CGSize, isPencil: Bool,
                    mode: ScoreMode, maxFingers: Int,
                    movement: CGFloat, elapsed: TimeInterval,
                    wasPress: Bool = false, lassoArmed: Bool = false,
                    hit: Bool = true) -> Outcome {
        guard maxFingers <= 1 else { return .none }
        // While the lasso is armed the finger is the lasso's, whole. A tap
        // that also selected would be a second claim on the same touch, which
        // is the thing this file exists to prevent.
        guard !lassoArmed else { return .none }
        // A PRESS may move: once the loupe is up the touch belongs to the
        // selection and a slide is the reader placing the crosshair, not a
        // pan. Before the press, movement is a pan and means nothing else.
        guard wasPress || movement <= PageTurn.tapSlop else { return .none }
        // A press is never a turn, in any region: it is the selecting
        // gesture, and the reader can see under their own fingertip while
        // they make it.
        let quick = !wasPress && PageTurn.isTap(movement: movement, elapsed: elapsed)
        if mode == .performance { return quick ? .turn(half(at: point, in: canvas)) : .none }
        if isPencil { return .none }
        if !wasPress {
            guard quick else { return .none }
            if let corner = corner(at: point, in: canvas) { return .turn(corner) }
        }
        return hit ? .select : .clear
    }
}

extension CanvasTap {
    /// One finished single-finger touch, as the recogniser observed it.
    ///
    /// The recogniser reports; it decides nothing. `maxFingers` is the most
    /// fingers that were down at ANY moment of the touch, not how many are down
    /// now: a pinch that ends with one finger lifted a moment before the other
    /// would otherwise arrive here looking exactly like a tap.
    struct Touch {
        let point: CGPoint
        let canvas: CGSize
        let isPencil: Bool
        let maxFingers: Int
        let movement: CGFloat
        let elapsed: TimeInterval
        /// The finger stayed still long enough to raise the loupe, so the
        /// touch was a selection from that moment on.
        let wasPress: Bool
        /// The page under the finger and where on it, in unit coordinates.
        /// Nil when the touch landed off every page.
        let page: (index: Int, unit: CGPoint)?
    }

    /// The same decision, for a touch the recogniser handed over.
    static func tap(_ touch: Touch, mode: ScoreMode, lassoArmed: Bool,
                    hit: Bool) -> Outcome {
        tap(at: touch.point, in: touch.canvas, isPencil: touch.isPencil,
            mode: mode, maxFingers: touch.maxFingers,
            movement: touch.movement, elapsed: touch.elapsed,
            wasPress: touch.wasPress, lassoArmed: lassoArmed, hit: hit)
    }
}
