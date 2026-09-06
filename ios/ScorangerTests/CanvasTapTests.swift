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
                     press: Bool = false,
                     armed: Bool = false,
                     onPage: Bool = true,
                     hit: Bool = true) -> CanvasTap.Outcome {
        CanvasTap.tap(at: point, in: size ?? canvas, isPencil: isPencil,
                      mode: mode, maxFingers: fingers,
                      movement: movement, elapsed: elapsed,
                      wasPress: press, lassoArmed: armed,
                      onPage: onPage, hit: hit)
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

    /// A dwell is not a tap, which is §12 as written. What a long touch DOES
    /// mean is a press, and a press arrives flagged -- see below.
    func testADwellIsNotATap() {
        XCTAssertEqual(tap(mid(canvas), elapsed: 1.2), .none)
        XCTAssertEqual(tap(CGPoint(x: 5, y: 754), elapsed: 1.2), .none,
                       "a thumb resting in the corner turned the page")
    }

    /// Performance mode turns anywhere: the score has the screen and there is
    /// nothing to select.
    func testPerformanceModeTurnsAnywhere() {
        XCTAssertEqual(tap(mid(canvas), mode: .performance), .turn(.next))
        XCTAssertEqual(tap(CGPoint(x: 20, y: 100), mode: .performance),
                       .turn(.previous))
        XCTAssertEqual(tap(mid(canvas), mode: .performance, onPage: false),
                       .turn(.next), "the turn does not need paper under it")
    }

    /// And a finger HELD there still turns (§13). There is no press in
    /// performance mode -- selection is off, so a loupe would magnify
    /// something the reader cannot act on -- which leaves a slow tap.
    func testAHeldFingerStillTurnsInPerformanceMode() {
        XCTAssertEqual(tap(mid(canvas), mode: .performance, elapsed: 4),
                       .turn(.next))
        XCTAssertEqual(tap(mid(canvas), mode: .performance, movement: 40),
                       .none, "a drag in performance mode is still a pan")
    }

    /// A release off the paper cancels: no commit, no clear. The reader who
    /// slid a press off the page did not choose the emptiness there (§13).
    func testAReleaseOffThePageCancels() {
        XCTAssertEqual(tap(mid(canvas), onPage: false), .none)
        XCTAssertEqual(tap(mid(canvas), onPage: false, hit: false), .none)
        XCTAssertEqual(tap(mid(canvas), movement: 200, elapsed: 3,
                           press: true, onPage: false), .none)
        XCTAssertEqual(tap(CGPoint(x: 5, y: 754), onPage: false),
                       .turn(.previous),
                       "the corner turns whether or not paper is under it: at "
                       + "fit the page does not reach the bottom of the canvas")
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

    /// Once the loupe is up the touch is a selection: it may travel, it may
    /// take as long as it likes, and it never turns a page -- including from
    /// a corner, where the reader can see exactly what the crosshair is on.
    func testAPressSelectsWhereverItEnds() {
        XCTAssertEqual(tap(mid(canvas), movement: 120, elapsed: 3, press: true),
                       .select)
        XCTAssertEqual(tap(CGPoint(x: 5, y: 754), movement: 120, elapsed: 3,
                           press: true), .select,
                       "a press that ended in a corner turned the page")
        XCTAssertEqual(tap(mid(canvas), movement: 120, elapsed: 3,
                           press: true, hit: false), .clear)
        XCTAssertEqual(tap(mid(canvas), mode: .performance, movement: 120,
                           elapsed: 3, press: true), .none,
                       "a drag in performance mode is a pan, press flag or not")
        XCTAssertEqual(tap(mid(canvas), fingers: 2, press: true), .none,
                       "a second finger still ends it")
    }

    /// While `Select` is armed the finger is the lasso's, whole -- including
    /// in the corners, or arming it would cost the reader a page turn they
    /// did not ask for.
    func testAnArmedLassoTakesTheWholeFinger() {
        XCTAssertEqual(tap(mid(canvas), armed: true), .none)
        XCTAssertEqual(tap(CGPoint(x: 5, y: 754), armed: true), .none)
        XCTAssertEqual(tap(mid(canvas), armed: true, hit: false), .none)
        XCTAssertEqual(tap(mid(canvas), press: true, armed: true), .none)
        XCTAssertEqual(tap(mid(canvas), mode: .performance, armed: true), .none)
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
            // vary the gesture too: a quick tap and a press resolve the same
            // point differently, and BOTH must resolve it to exactly one thing
            let press = seed % 2 == 0
            let first = tap(point, size: size, movement: press ? 30 : 0,
                            elapsed: press ? 1.4 : 0.1, press: press)
            let again = tap(point, size: size, movement: press ? 30 : 0,
                            elapsed: press ? 1.4 : 0.1, press: press)
            XCTAssertEqual(first, again,
                           "unstable at \(point) in \(size): \(first) then \(again)")
            XCTAssertNotEqual(first, CanvasTap.Outcome.clear,
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
