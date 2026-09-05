import CoreGraphics
import XCTest

/// How many SYSTEMS a page holds, inferred from the bars on it.
///
/// The observable #4 needs. Ali's collapse is "one long squished illegible
/// system" with the counter reading "p. 1 / 1" -- and on a short score one
/// page can be CORRECT, so a page count cannot tell a collapse from a tune
/// that simply fits. What distinguishes them is how many lines the music is
/// broken into, and nothing in the app counted those.
///
/// It is inferred rather than parsed: `ScoreGeometry` has no notion of a
/// system, but `BarPosition.clippedToNeighbours` already has to decide
/// whether two bars are on the SAME one, and does it by asking whether their
/// vertical extents overlap. That rule is proven against the real engraver in
/// check_bar_frames.py, so this groups by the same rule rather than inventing
/// a second one that could disagree with it.
final class SystemCountTests: XCTestCase {

    private func bar(_ number: Int, _ x: CGFloat, _ y: CGFloat,
                     _ w: CGFloat = 90, _ h: CGFloat = 60) -> BarPosition.Bar {
        .init(number: number, frame: CGRect(x: x, y: y, width: w, height: h))
    }

    func testBarsOnOneLineAreOneSystem() {
        let bars = [bar(1, 0, 100), bar(2, 100, 100), bar(3, 200, 100)]
        XCTAssertEqual(BarPosition.systems(of: bars).count, 1)
    }

    /// Two bands of bars, far apart vertically, are two systems.
    func testTwoBandsAreTwoSystems() {
        let bars = [bar(1, 0, 100), bar(2, 100, 100),
                    bar(3, 0, 400), bar(4, 100, 400)]
        let systems = BarPosition.systems(of: bars)
        XCTAssertEqual(systems.count, 2)
        XCTAssertEqual(systems.map { $0.map(\.number) }, [[1, 2], [3, 4]])
    }

    /// Systems come back in reading order, top to bottom -- a count is the
    /// point but an order makes a failure legible.
    func testSystemsAreInReadingOrder() {
        let bars = [bar(9, 0, 700), bar(1, 0, 100), bar(5, 0, 400)]
        XCTAssertEqual(BarPosition.systems(of: bars).map { $0[0].number },
                       [1, 5, 9])
    }

    /// A system's bars are not perfectly aligned -- a bar with a high note or
    /// a slur is taller -- so overlap and not equality is the test. This is
    /// the same rule `clippedToNeighbours` uses, and a stricter one would
    /// split a system in two every time a bar grew.
    func testRaggedBarsStillFormOneSystem() {
        let bars = [bar(1, 0, 100, 90, 60),
                    bar(2, 100, 82, 90, 95),   // taller, starts higher
                    bar(3, 200, 104, 90, 50)]  // shorter
        XCTAssertEqual(BarPosition.systems(of: bars).count, 1)
    }

    /// The collapse itself: every bar of the score on ONE line. This is what
    /// Ali's screenshot shows and what the reproduction has to be able to see.
    func testOneLongSystemIsOneSystemHoweverManyBars() {
        let bars = (1...40).map { bar($0, CGFloat($0) * 90, 100) }
        XCTAssertEqual(BarPosition.systems(of: bars).count, 1)
    }

    func testNoBarsIsNoSystems() {
        XCTAssertEqual(BarPosition.systems(of: []).count, 0)
    }

    /// A page whose bars are one per system -- a grand staff with very long
    /// bars -- is that many systems, not one.
    func testOneBarPerLineIsOneSystemEach() {
        let bars = [bar(1, 0, 100), bar(2, 0, 300), bar(3, 0, 500)]
        XCTAssertEqual(BarPosition.systems(of: bars).count, 3)
    }
}
