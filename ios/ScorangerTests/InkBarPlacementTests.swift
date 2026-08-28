import CoreGraphics
import XCTest

/// Ali: the ink tools float over the middle of the score. They were anchored
/// to the bottom of the pane but lifted 74 points off it, which on a page that
/// fills the pane puts them over the staves.
final class InkBarPlacementTests: XCTestCase {

    private let pane = CGSize(width: 1000, height: 1300)
    private let bar = CGSize(width: 420, height: 56)

    func testTheBarStartsDockedInTheFooter() {
        XCTAssertEqual(InkBarPlacement.docked, .zero)
        XCTAssertLessThan(InkBarPlacement.footerInset, 20,
                          "the dock is the footer, not a float above the music")
    }

    func testItCanBeMovedUpOffTheMusic() {
        let moved = InkBarPlacement.clamp(CGSize(width: 0, height: -400),
                                          in: pane, barSize: bar)
        XCTAssertEqual(moved.height, -400, accuracy: 0.001)
    }

    /// #46: the bar reaches the thumbnail strip and the transport, because its
    /// container is the whole score SCREEN now rather than the page canvas
    /// that stops above them. The travel is measured from a dock at the
    /// screen's bottom edge, so "over the strip" is a short move UP from there
    /// -- and every point of the screen is inside the range.
    func testItCanReachEveryPartOfTheScreen() {
        let screen = CGSize(width: 1032, height: 1366)
        let up = InkBarPlacement.clamp(CGSize(width: 0, height: -9000),
                                       in: screen, barSize: bar)
        let topWhenRaised = screen.height + up.height - bar.height
                            - InkBarPlacement.footerInset
        XCTAssertLessThanOrEqual(topWhenRaised, 1,
                                 "the bar cannot reach the top of the screen")
        let strip = InkBarPlacement.clamp(CGSize(width: 0, height: -120),
                                          in: screen, barSize: bar)
        XCTAssertEqual(strip.height, -120, accuracy: 0.001,
                       "a short move up, over the strip, was clamped away")
    }

    /// The one limit left: enough of it stays on screen to take hold of.
    func testItCannotBePushedEntirelyOffTheScreen() {
        for offset in [CGSize(width: 9000, height: 0), CGSize(width: -9000, height: 0),
                       CGSize(width: 0, height: 9000), CGSize(width: 0, height: -9000)] {
            let moved = InkBarPlacement.clamp(offset, in: pane, barSize: bar)
            let left = pane.width / 2 + moved.width - bar.width / 2
            let right = pane.width / 2 + moved.width + bar.width / 2
            XCTAssertLessThan(left, pane.width, "gone off the right: \(moved)")
            XCTAssertGreaterThan(right, 0, "gone off the left: \(moved)")
            let top = pane.height - InkBarPlacement.footerInset - bar.height
                      + moved.height
            // a bar shorter than the keep-visible margin can only ever keep
            // its own height, which is the whole of it
            let keep = min(InkBarPlacement.mustRemainVisible, bar.height)
            XCTAssertLessThanOrEqual(top, pane.height - keep + 1,
                                     "gone off the bottom: \(moved)")
        }
    }

    func testItReachesFurtherSidewaysThanTheOldClampAllowed() {
        let far = InkBarPlacement.clamp(CGSize(width: 5000, height: 0),
                                        in: pane, barSize: bar)
        XCTAssertGreaterThan(far.width, (pane.width - bar.width) / 2,
                             "the old inside-the-pane clamp is still in force")
    }

    func testItStaysInsideThePaneVertically() {
        let up = InkBarPlacement.clamp(CGSize(width: 0, height: -99_999),
                                       in: pane, barSize: bar)
        XCTAssertEqual(up.height,
                       -(pane.height - bar.height - InkBarPlacement.footerInset),
                       accuracy: 0.001)
    }

    /// A pane that has not been measured yet must not throw the bar somewhere
    /// arbitrary: it stays docked until there is a pane to move around in.
    func testAnUnmeasuredPaneLeavesItDocked() {
        XCTAssertEqual(InkBarPlacement.clamp(CGSize(width: 100, height: -100),
                                             in: .zero, barSize: bar),
                       InkBarPlacement.docked)
    }

    /// A bar wider than its pane may still be moved, but never so far that
    /// less than a handle's worth of it is left on screen.
    func testABarWiderThanItsPaneStaysReachable() {
        let narrow = CGSize(width: 300, height: 1300)
        let moved = InkBarPlacement.clamp(CGSize(width: 5000, height: 0),
                                          in: narrow, barSize: bar)
        let left = narrow.width / 2 + moved.width - bar.width / 2
        XCTAssertLessThan(left, narrow.width)
    }

    func testAPaneWithNoRoomReportsTheBarAsUnmovable() {
        XCTAssertFalse(InkBarPlacement.isMovable(in: CGSize(width: 400, height: 60),
                                                 barSize: bar))
        XCTAssertTrue(InkBarPlacement.isMovable(in: pane, barSize: bar))
    }
}
