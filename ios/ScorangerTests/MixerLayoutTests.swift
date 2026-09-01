import CoreGraphics
import XCTest

/// The mixer's geometry, asserted against design/PLAYBACK_0.6.md §1.
final class MixerLayoutTests: XCTestCase {

    /// 32 header + 24 mute + 150 fader + 18 value + 28 label + padding + the
    /// 40pt scrubber footer. Written out because the spec writes it out.
    func testThePanelIsAsTallAsTheSpecSays() {
        XCTAssertEqual(MixerLayout.panelHeight,
                       32 + 24 + 150 + 18 + 28 + 16 + 40)
    }

    /// 8pt padding + n x 64 + 1pt dividers.
    func testThePanelIsAsWideAsItsStrips() {
        XCTAssertEqual(MixerLayout.panelWidth(channels: 1), 16 + 64)
        XCTAssertEqual(MixerLayout.panelWidth(channels: 4), 16 + 4 * 64 + 3)
    }

    /// Six strips visible, and beyond that the rack scrolls rather than the
    /// panel growing past the canvas.
    func testBeyondSixStripsTheRackScrollsInsteadOfGrowing() {
        let six = MixerLayout.panelWidth(channels: 6)
        XCTAssertEqual(MixerLayout.panelWidth(channels: 12), six,
                       "a twelve-staff score must not make a twelve-strip panel")
        XCTAssertFalse(MixerLayout.scrolls(channels: 6))
        XCTAssertTrue(MixerLayout.scrolls(channels: 7))
        XCTAssertTrue(MixerLayout.scrolls(channels: 5, compact: true),
                      "an iPhone shows four")
    }

    /// The fader fills from the BOTTOM: 0 is empty, 10 is full travel.
    func testTheFaderFillsFromTheBottom() {
        XCTAssertEqual(MixerLayout.capOffset(forFader: 0), 0)
        XCTAssertEqual(MixerLayout.capOffset(forFader: 10), 1)
        XCTAssertEqual(MixerLayout.capOffset(forFader: 7), 0.7, accuracy: 1e-9)
    }

    /// A drag lands on a notch. The scale is 0-10 and the value is printed
    /// under the cap, so a fader resting between two numbers could not be read
    /// back off the thing under it.
    func testADragLandsOnANotch() {
        XCTAssertEqual(MixerLayout.fader(forOffset: 0), 0)
        XCTAssertEqual(MixerLayout.fader(forOffset: 1), 10)
        XCTAssertEqual(MixerLayout.fader(forOffset: 0.72), 7)
        XCTAssertEqual(MixerLayout.fader(forOffset: 0.75), 8, "rounds, not truncates")
        XCTAssertEqual(MixerLayout.fader(forOffset: -5), 0, "a drag off the end clamps")
        XCTAssertEqual(MixerLayout.fader(forOffset: 9), 10)
    }

    /// The detent is the default, so the tick silkscreened on the track marks
    /// where an untouched fader sits.
    func testTheTickMarksTheDefault() {
        XCTAssertEqual(MixerLayout.detent, PlaybackGain.defaultFader)
        XCTAssertEqual(MixerLayout.capOffset(forFader: MixerLayout.detent), 0.7,
                       accuracy: 1e-9)
    }

    /// Four corners, cycled by tapping the grip -- the path for readers who
    /// cannot drag.
    func testTheGripCyclesFourCornersAndComesBack() {
        var corner = MixerLayout.Corner.bottomTrailing
        var seen: [MixerLayout.Corner] = [corner]
        for _ in 0..<3 { corner = corner.next; seen.append(corner) }
        XCTAssertEqual(Set(seen).count, 4, "every corner is reachable")
        XCTAssertEqual(corner.next, .bottomTrailing, "and it comes back round")
    }

    /// The default park is bottom-trailing, ABOVE whatever lanes are occupied:
    /// the ink bar and the sync chip are fixed and cannot move out of the way.
    func testTheDefaultParkSitsAboveTheOccupiedLanes() {
        let bounds = CGSize(width: 1000, height: 800)
        let panel = CGSize(width: 400, height: MixerLayout.panelHeight)
        let clear = MixerLayout.origin(for: .bottomTrailing, panel: panel,
                                       in: bounds, lanesInset: 0)
        let crowded = MixerLayout.origin(for: .bottomTrailing, panel: panel,
                                         in: bounds, lanesInset: 120)
        XCTAssertEqual(clear.x, 1000 - 400 - 8)
        XCTAssertEqual(crowded.y, clear.y - 120, "it lifts by exactly the lanes")
        XCTAssertLessThan(crowded.y, clear.y)
    }

    func testTheOtherCornersGoWhereTheySay() {
        let bounds = CGSize(width: 1000, height: 800)
        let panel = CGSize(width: 400, height: 268)
        XCTAssertEqual(MixerLayout.origin(for: .topLeading, panel: panel,
                                          in: bounds, lanesInset: 0),
                       CGPoint(x: 8, y: 8))
        XCTAssertEqual(MixerLayout.origin(for: .topTrailing, panel: panel,
                                          in: bounds, lanesInset: 0).x, 592)
        XCTAssertEqual(MixerLayout.origin(for: .bottomLeading, panel: panel,
                                          in: bounds, lanesInset: 0).x, 8)
    }

    /// A panel dragged at an edge stays reachable, by the ink bar's own rule
    /// rather than a second one invented for this panel.
    func testADraggedPanelCannotBeLost() {
        let bounds = CGSize(width: 1000, height: 800)
        let panel = CGSize(width: 400, height: 268)
        let shoved = MixerLayout.clamp(CGPoint(x: -9000, y: 9000),
                                       panel: panel, in: bounds)
        XCTAssertGreaterThanOrEqual(shoved.x + panel.width,
                                    InkBarPlacement.mustRemainVisible,
                                    "some of it must stay on screen to grab")
        XCTAssertLessThanOrEqual(shoved.y,
                                 bounds.height - InkBarPlacement.mustRemainVisible)
        XCTAssertGreaterThanOrEqual(shoved.y, 0, "never above the top edge")
    }

    /// A muted strip dims but its LED still lights: the staff IS playing and
    /// the reader cannot hear it, which is how they confirm the mute works.
    func testAMutedStripDimsRatherThanGoingDark() {
        XCTAssertEqual(MixerLayout.mutedOpacity, 0.42)
        XCTAssertGreaterThan(MixerLayout.mutedOpacity, 0,
                             "a muted strip is dimmed, never hidden")
    }
}
