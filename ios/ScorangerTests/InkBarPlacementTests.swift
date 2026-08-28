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

    /// Only upward. There is nothing below the dock to move into, and a bar
    /// dragged off the bottom could not be dragged back.
    func testItCannotBeMovedDownOutOfReach() {
        let moved = InkBarPlacement.clamp(CGSize(width: 0, height: 500),
                                          in: pane, barSize: bar)
        XCTAssertEqual(moved.height, 0, accuracy: 0.001)
    }

    func testItStaysInsideThePaneHorizontally() {
        let sideways = (pane.width - bar.width) / 2
        let far = InkBarPlacement.clamp(CGSize(width: 5000, height: 0),
                                        in: pane, barSize: bar)
        XCTAssertEqual(far.width, sideways, accuracy: 0.001)
        let other = InkBarPlacement.clamp(CGSize(width: -5000, height: 0),
                                          in: pane, barSize: bar)
        XCTAssertEqual(other.width, -sideways, accuracy: 0.001)
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

    /// A bar wider than its pane clamps to the dock rather than to a negative
    /// range, which would let it slide off both edges at once.
    func testABarWiderThanItsPaneDoesNotSlideOff() {
        let narrow = CGSize(width: 300, height: 1300)
        let moved = InkBarPlacement.clamp(CGSize(width: 200, height: 0),
                                          in: narrow, barSize: bar)
        XCTAssertEqual(moved.width, 0, accuracy: 0.001)
    }

    func testAPaneWithNoRoomReportsTheBarAsUnmovable() {
        XCTAssertFalse(InkBarPlacement.isMovable(in: CGSize(width: 400, height: 60),
                                                 barSize: bar))
        XCTAssertTrue(InkBarPlacement.isMovable(in: pane, barSize: bar))
    }
}
