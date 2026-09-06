import CoreGraphics
import XCTest

/// One recogniser owns the single-finger tap, and it resolves in a fixed order.
///
/// IPHONE_0.6.14 §12. The alternative -- two gestures racing, or
/// `.simultaneousGesture` -- is what killed the mixer's drag for a release:
/// the panel's drag competed with every control on it and lost silently,
/// measured at 0.0pt of movement. A pure function with a stated order cannot
/// do that, and can be fuzzed.
///
/// The two tests this file exists for are the two the mixer never had:
/// DISJOINT-AND-TOTAL (every point resolves to exactly one outcome, and the
/// outcomes cover the canvas), and NO-STRAY-SELECTION-FROM-A-PINCH.
final class CanvasTapTests: XCTestCase {

    private let canvas = CGSize(width: 393, height: 759)
    private func mid(_ s: CGSize) -> CGPoint { .init(x: s.width / 2, y: s.height / 2) }

    private func tap(_ point: CGPoint, size: CGSize? = nil,
                     isPencil: Bool = false, mode: ScoreMode = .read,
                     fingers: Int = 1, movement: CGFloat = 0,
                     elapsed: TimeInterval = 0.1,
                     hit: Bool = true) -> CanvasTap.Outcome {
        CanvasTap.tap(at: point, in: size ?? canvas, isPencil: isPencil,
                      mode: mode, maxFingers: fingers,
                      movement: movement, elapsed: elapsed, hit: hit)
    }

    // MARK: - The fixed order (§12)

    /// Multi-touch at ANY moment during the touch kills it. Not "two fingers
    /// now" -- a pinch that ends with one finger lifted would otherwise commit
    /// a selection where the remaining finger happens to be.
    func testMultiTouchAtAnyMomentIsNothing() {
        XCTAssertEqual(tap(mid(canvas), fingers: 2), .none)
        XCTAssertEqual(tap(CGPoint(x: 10, y: 700), fingers: 2), .none,
                       "even in a turn zone")
        XCTAssertEqual(tap(mid(canvas), mode: .performance, fingers: 3), .none)
    }

    /// A drag is a pan, in every mode and every region.
    func testAMoveIsAPanAndNothingElse() {
        XCTAssertEqual(tap(mid(canvas), movement: 40), .none)
        XCTAssertEqual(tap(CGPoint(x: 5, y: 754), movement: 40), .none)
        XCTAssertEqual(tap(mid(canvas), mode: .performance, movement: 40), .none)
    }

    /// A press that never moved SELECTS however long it was held, and never
    /// TURNS unless it was quick.
    ///
    /// §9.2's loupe needs the first half: the reader presses, sees what is
    /// under the fingertip, and releases when the crosshair is right. §6.2
    /// needs the second: a thumb resting in a corner must not turn the page.
    /// Movement separates both from a pan, which is the rule that was always
    /// doing the work.
    func testAHeldStillFingerSelectsButNeverTurns() {
        XCTAssertEqual(tap(mid(canvas), elapsed: 1.2), .select)
        XCTAssertEqual(tap(CGPoint(x: 5, y: 754), elapsed: 1.2), .none,
                       "a thumb resting in the corner turned the page")
        XCTAssertEqual(tap(mid(canvas), mode: .performance, elapsed: 1.2), .none)
    }

    /// Performance mode turns anywhere: the score has the screen and there is
    /// nothing to select.
    func testPerformanceModeTurnsAnywhere() {
        XCTAssertEqual(tap(mid(canvas), mode: .performance), .turn(.next))
        XCTAssertEqual(tap(CGPoint(x: 20, y: 100), mode: .performance),
                       .turn(.previous))
    }

    /// The Pencil keeps its table untouched: it turns only in performance
    /// mode, and otherwise the lasso and the ink own it.
    func testThePencilTableIsUnchanged() {
        XCTAssertEqual(tap(CGPoint(x: 10, y: 700), isPencil: true), .none)
        XCTAssertEqual(tap(mid(canvas), isPencil: true), .none)
        XCTAssertEqual(tap(CGPoint(x: 10, y: 700), isPencil: true,
                           mode: .performance), .turn(.previous))
    }

    /// A finger in a bottom corner turns; anywhere else it selects.
    func testAFingerTurnsInTheCornersAndSelectsElsewhere() {
        XCTAssertEqual(tap(CGPoint(x: 10, y: 740)), .turn(.previous))
        XCTAssertEqual(tap(CGPoint(x: 383, y: 740)), .turn(.next))
        XCTAssertEqual(tap(mid(canvas)), .select)
        XCTAssertEqual(tap(CGPoint(x: 10, y: 100)), .select,
                       "the top-left is music, not a turn zone")
    }

    // MARK: - The zones are corners, not columns (§12)

    /// The change that buys the canvas back: a full-height column at 22% took
    /// 44% of every page. Bottom-anchored corners take a fraction of that.
    func testTheTurnZonesAreBottomAnchoredCorners() {
        // top corners are selectable
        XCTAssertEqual(tap(CGPoint(x: 5, y: 5)), .select)
        XCTAssertEqual(tap(CGPoint(x: 388, y: 5)), .select)
        // bottom corners turn
        XCTAssertEqual(tap(CGPoint(x: 5, y: 754)), .turn(.previous))
        XCTAssertEqual(tap(CGPoint(x: 388, y: 754)), .turn(.next))
    }

    /// The designer's number: about 86.8% of the canvas selectable. Asserted
    /// as a floor rather than the exact figure, which moves with the minimums
    /// on small canvases.
    func testMostOfTheCanvasIsSelectable() {
        for size in [CGSize(width: 393, height: 759),   // iPhone portrait
                     CGSize(width: 734, height: 372),   // iPhone landscape
                     CGSize(width: 1032, height: 1250),  // iPad portrait
                     CGSize(width: 507, height: 900)] {  // iPad split
            var selectable = 0, total = 0
            for x in stride(from: 2.0, to: size.width, by: 6) {
                for y in stride(from: 2.0, to: size.height, by: 6) {
                    total += 1
                    if tap(CGPoint(x: x, y: y), size: size) == .select {
                        selectable += 1
                    }
                }
            }
            let share = Double(selectable) / Double(total)
            XCTAssertGreaterThan(share, 0.80,
                                 "\(Int(size.width))x\(Int(size.height)): only "
                                 + "\(Int(share * 100))% selectable")
        }
    }

    // MARK: - Disjoint and total

    /// EVERY point resolves to exactly one outcome, on every canvas, and the
    /// outcomes cover the canvas. This is the test the mixer never had: its
    /// drag and its controls both claimed the same points and the arbitration
    /// was whatever SwiftUI decided that frame.
    ///
    /// A pure function makes "exactly one" true by construction -- it returns
    /// one value -- so what is actually asserted is that no point falls into a
    /// gap, that the answer is STABLE for the same input, and that the regions
    /// are contiguous rather than interleaved.
    func testEveryPointResolvesToExactlyOneOutcome() {
        var seed: UInt64 = 0xC0FFEE
        func next(_ upper: Int) -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Int(seed >> 33) % max(upper, 1))
        }
        for _ in 0..<3000 {
            let size = CGSize(width: 200 + next(1200), height: 200 + next(1200))
            let point = CGPoint(x: next(Int(size.width)), y: next(Int(size.height)))
            let held = seed % 2 == 0
            let first = tap(point, size: size, elapsed: held ? 1.4 : 0.1)
            let again = tap(point, size: size, elapsed: held ? 1.4 : 0.1)
            XCTAssertEqual(first, again,
                           "unstable at \(point) in \(size): \(first) then \(again)")
            XCTAssertNotEqual(first, .clear,
                              "with something under the finger, the selecting "
                              + "region never resolves to a clear")
        }
    }

    /// The regions are contiguous: walking left to right along the bottom edge
    /// crosses previous -> select -> next and never returns to a region it
    /// has left.
    func testTheZonesAreContiguousAcrossTheBottomEdge() {
        var seen: [CanvasTap.Outcome] = []
        for x in stride(from: 1.0, to: canvas.width, by: 2) {
            let outcome = tap(CGPoint(x: x, y: canvas.height - 4))
            if seen.last != outcome { seen.append(outcome) }
        }
        XCTAssertEqual(seen, [.turn(.previous), .select, .turn(.next)],
                       "the bottom edge is not three contiguous regions: \(seen)")
    }

    /// A tap where the geometry has nothing puts the selection down. Same
    /// region, same rule -- the hit test changes what SELECT does, never
    /// whether the tap was a turn.
    func testATapOnEmptyPaperClears() {
        XCTAssertEqual(tap(mid(canvas), hit: false), .clear)
        XCTAssertEqual(tap(CGPoint(x: 5, y: 754), hit: false), .turn(.previous),
                       "an empty corner still turns")
    }

    // MARK: - No stray selection from a pinch

    /// A pinch must never leave a selection behind, however it ends. This is
    /// the failure mode that matters most: the reader zooms, lifts one finger
    /// slightly before the other, and a note they never aimed at is selected.
    func testAPinchNeverSelects() {
        for movement in [0.0, 5.0, 60.0, 400.0] {
            for elapsed in [0.05, 0.2, 2.0] {
                for fingers in [2, 3, 4] {
                    XCTAssertEqual(
                        tap(mid(canvas), fingers: fingers,
                            movement: movement, elapsed: elapsed),
                        .none,
                        "a \(fingers)-finger gesture selected something")
                }
            }
        }
    }

    /// And the same in performance mode, where a finger tap DOES turn: a
    /// pinch there must not turn the page either.
    func testAPinchNeverTurnsEither() {
        XCTAssertEqual(tap(mid(canvas), mode: .performance, fingers: 2), .none)
    }
}
