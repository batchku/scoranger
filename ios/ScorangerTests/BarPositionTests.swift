import CoreGraphics
import Foundation
import XCTest

/// Which bar the reader is looking at (NAVIGATION_SYSTEM §4, the `bar 21`
/// readout in the score's top bar).
///
/// This got much cheaper in 0.4.2: the paged canvas keeps the viewport inside
/// ONE page's coordinate space, so the question is no longer "which of eight
/// stacked pages is under the fold" but "which bars on this page intersect the
/// visible rect". The geometry already exists — `ScoreModelBuilder` indexes
/// every measure's frame in page coordinates.
final class BarPositionTests: XCTestCase {

    /// A page of four bars in a row, each 100 wide, on a 400x200 page.
    private func bars(_ numbers: [Int], width: CGFloat = 100) -> [BarPosition.Bar] {
        numbers.enumerated().map { index, number in
            BarPosition.Bar(number: number,
                            frame: CGRect(x: CGFloat(index) * width, y: 0,
                                          width: width, height: 200))
        }
    }

    // MARK: - The number itself

    func testTheFirstVisibleBarIsReported() {
        let visible = CGRect(x: 0, y: 0, width: 400, height: 200)
        XCTAssertEqual(BarPosition.first(in: visible, bars: bars([1, 2, 3, 4])), 1)
    }

    /// Zoomed and panned to the right: the reader is at bar 3, so the readout
    /// says 3 — not 1, which is what a page-level answer would say.
    func testPanningPastABarMovesTheNumber() {
        let visible = CGRect(x: 210, y: 0, width: 180, height: 200)
        XCTAssertEqual(BarPosition.first(in: visible, bars: bars([1, 2, 3, 4])), 3)
    }

    /// Bar numbers are not page positions: a score whose first page starts at
    /// bar 47 must say 47.
    func testBarNumbersComeFromTheNotationNotThePosition() {
        let visible = CGRect(x: 0, y: 0, width: 150, height: 200)
        XCTAssertEqual(BarPosition.first(in: visible, bars: bars([47, 48, 49, 50])), 47)
    }

    /// A bar only half on screen still counts: the reader can see it.
    func testAPartlyVisibleBarCounts() {
        let visible = CGRect(x: 150, y: 0, width: 100, height: 200)
        XCTAssertEqual(BarPosition.first(in: visible, bars: bars([1, 2, 3, 4])), 2)
    }

    /// Touching edge-to-edge is not overlapping. Without this a viewport that
    /// stops exactly on a barline claims the bar it has not reached.
    func testABarTouchingOnlyTheEdgeDoesNotCount() {
        let visible = CGRect(x: 100, y: 0, width: 100, height: 200)
        XCTAssertEqual(BarPosition.first(in: visible, bars: bars([1, 2, 3, 4])), 2)
    }

    func testNothingVisibleReportsNothing() {
        let visible = CGRect(x: 900, y: 0, width: 50, height: 200)
        XCTAssertNil(BarPosition.first(in: visible, bars: bars([1, 2, 3, 4])))
    }

    /// A score whose geometry never built — the remote-engine path, where the
    /// model is not constructed — must show nothing rather than a wrong number.
    func testNoGeometryReportsNothing() {
        XCTAssertNil(BarPosition.first(in: CGRect(x: 0, y: 0, width: 400, height: 200),
                                       bars: []))
    }

    // MARK: - Ordering

    /// Bars are not necessarily indexed in reading order, and a lower bar
    /// number can sit further right on a page with several systems. The answer
    /// is the lowest NUMBER among the visible bars, which is what a reader
    /// means by "where am I".
    func testTheLowestVisibleNumberWinsRegardlessOfOrder() {
        let out = [
            BarPosition.Bar(number: 9, frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
            BarPosition.Bar(number: 7, frame: CGRect(x: 200, y: 0, width: 100, height: 100)),
            BarPosition.Bar(number: 8, frame: CGRect(x: 100, y: 0, width: 100, height: 100)),
        ]
        XCTAssertEqual(BarPosition.first(in: CGRect(x: 0, y: 0, width: 400, height: 200),
                                         bars: out), 7)
    }

    /// A second system lower down the page: scrolling to it reports its bars,
    /// not the ones above.
    func testASecondSystemReportsItsOwnBars() {
        let page = [
            BarPosition.Bar(number: 1, frame: CGRect(x: 0, y: 0, width: 200, height: 100)),
            BarPosition.Bar(number: 2, frame: CGRect(x: 200, y: 0, width: 200, height: 100)),
            BarPosition.Bar(number: 3, frame: CGRect(x: 0, y: 120, width: 200, height: 100)),
            BarPosition.Bar(number: 4, frame: CGRect(x: 200, y: 120, width: 200, height: 100)),
        ]
        let lower = CGRect(x: 0, y: 115, width: 400, height: 105)
        XCTAssertEqual(BarPosition.first(in: lower, bars: page), 3)
    }

    // MARK: - What it reads as

    func testTheLabelNamesTheBar() {
        XCTAssertEqual(BarPosition.label(for: 21), "bar 21")
    }

    func testNoBarHasNoLabel() {
        XCTAssertNil(BarPosition.label(for: nil))
    }

    // MARK: - A spread is two pages, and the answer spans both

    /// With the spread on, the unit is two pages side by side. The reader is at
    /// the earliest bar visible across the pair, which is normally on the left
    /// page but is on the right one once the left is scrolled past.
    func testASpreadTakesTheEarliestBarAcrossBothPages() {
        let left = bars([5, 6])
        let right = bars([7, 8])
        XCTAssertEqual(BarPosition.first(inPages: [
            (CGRect(x: 0, y: 0, width: 200, height: 200), left),
            (CGRect(x: 0, y: 0, width: 200, height: 200), right),
        ]), 5)
    }

    func testASpreadFallsToTheRightPageWhenTheLeftIsNotVisible() {
        let left = bars([5, 6])
        let right = bars([7, 8])
        XCTAssertEqual(BarPosition.first(inPages: [
            (CGRect(x: 900, y: 0, width: 50, height: 200), left),
            (CGRect(x: 0, y: 0, width: 200, height: 200), right),
        ]), 7)
    }
}

/// Where the pages of a unit sit, computed rather than measured — a
/// GeometryReader inside the zooming scroll view never reported.
extension BarPositionTests {

    func testASinglePageStartsAfterTheTopGutter() {
        let f = BarPosition.pageFrame(position: 0, width: 400, aspect: 1.4, gutter: 12)
        XCTAssertEqual(f.minX, 0)
        XCTAssertEqual(f.minY, 12)
        XCTAssertEqual(f.width, 400)
        XCTAssertEqual(f.height, 560, accuracy: 0.001)
    }

    /// The right-hand page of a spread clears the left page AND the gutter
    /// between them, or the two pages' coordinate spaces overlap and the
    /// readout reports the wrong page's bars.
    func testTheRightPageOfASpreadClearsTheLeftOneAndTheGutter() {
        let right = BarPosition.pageFrame(position: 1, width: 400, aspect: 1.4, gutter: 12)
        XCTAssertEqual(right.minX, 412)
    }

    func testATallerPageIsTaller() {
        let tall = BarPosition.pageFrame(position: 0, width: 300, aspect: 2.0, gutter: 0)
        XCTAssertEqual(tall.height, 600, accuracy: 0.001)
    }
}

extension BarPositionTests {

    /// Looking a numbered bar up on a page: what follow-scrolling needs to
    /// turn "bar 21 is sounding" into a place on the strip.
    func testABarIsFoundByItsNumber() {
        let bars = [BarPosition.Bar(number: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 50)),
                    BarPosition.Bar(number: 2, frame: CGRect(x: 100, y: 0, width: 120, height: 50)),
                    BarPosition.Bar(number: 3, frame: CGRect(x: 220, y: 0, width: 90, height: 50))]
        XCTAssertEqual(BarPosition.frame(ofBar: 2, among: bars)?.minX, 100)
        XCTAssertEqual(BarPosition.frame(ofBar: 3, among: bars)?.width, 90)
    }

    /// Nil, not a fallback. The remote-engine path builds no geometry at all,
    /// and a guessed position is worse than none: the reader trusts it and
    /// looks away from the music.
    func testABarThatIsNotOnThePageHasNoFrame() {
        XCTAssertNil(BarPosition.frame(ofBar: 9, among: []))
        XCTAssertNil(BarPosition.frame(
            ofBar: 9,
            among: [BarPosition.Bar(number: 1, frame: .zero)]))
    }
}
