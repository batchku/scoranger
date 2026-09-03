import CoreGraphics
import XCTest

/// The mixer's geometry, asserted against design/PLAYBACK_0.6.md §1.
final class MixerLayoutTests: XCTestCase {

    /// 24 header + 16 mute + 30 fader + 12 value + 16 sound + 16 label +
    /// 8 padding + 24 tempo + 24 scrubber. Written out because the panel's
    /// height is the thing that was wrong with it: the §1 panel was 308pt and
    /// covered a third of the score.
    func testThePanelIsAsTallAsTheLayoutSays() {
        XCTAssertEqual(MixerLayout.panelHeight,
                       24 + 16 + 30 + 12 + 16 + 16 + 8 + 24 + 24)
        XCTAssertEqual(MixerLayout.panelHeight, 170)
    }

    /// It WAS exactly half. The sound row (0.6.5) is 16pt of that half back
    /// and nothing else changed, so the assertion is not relaxed to "about
    /// half" -- it names the one row that was added and still holds the panel
    /// under 60% of what §1 drew.
    func testThePanelIsOneSoundRowTallerThanTheHalvedOne() {
        XCTAssertEqual(MixerLayout.specPanelHeight, 308, "what §1 drew")
        XCTAssertEqual(MixerLayout.panelHeight,
                       MixerLayout.specPanelHeight / 2 + MixerLayout.soundHeight)
        XCTAssertLessThan(MixerLayout.panelHeight,
                          MixerLayout.specPanelHeight * 0.6)
        XCTAssertGreaterThan(MixerLayout.tempoHeight, 0,
                             "and the tempo band is still counted in it")
    }

    /// The sound row came out of the panel's height and not out of the fader:
    /// shaving the control the reader uses most to keep a round number would
    /// have been a worse panel that measured better.
    func testTheSoundRowCostTheFaderNothing() {
        XCTAssertEqual(MixerLayout.faderHeight, 30)
        XCTAssertEqual(MixerLayout.labelHeight, 16)
        XCTAssertEqual(MixerLayout.soundHeight, 16)
        XCTAssertEqual(MixerLayout.rackHeight,
                       16 + 30 + 12 + 16 + 16 + 8)
    }

    /// The widths did NOT halve. A 64pt strip is already the narrowest a staff
    /// label reads at, and squeezing it would trade a panel that is too tall
    /// for one that says "Vio…" four times.
    func testTheStripsKeptTheirWidth() {
        XCTAssertEqual(MixerLayout.stripWidth, 64)
    }

    /// padding either side + n x 64 + 1pt dividers.
    func testThePanelIsAsWideAsItsStrips() {
        let pad = MixerLayout.padding * 2
        XCTAssertEqual(MixerLayout.panelWidth(channels: 1), pad + 64)
        XCTAssertEqual(MixerLayout.panelWidth(channels: 4), pad + 4 * 64 + 3)
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

    // MARK: - The sound picker (0.6.5)

    /// The picker is taller than the rack and wider than a narrow panel, so
    /// the layer that parks the panel has to ask for the size rather than
    /// compute the closed one -- a panel that grew without its parking knowing
    /// opens off the bottom of the canvas.
    func testTheOpenPickerIsTallerAndWiderThanTheClosedPanel() {
        let closed = MixerLayout.panelSize(channels: 2)
        let open = MixerLayout.panelSize(channels: 2, picking: true)
        XCTAssertEqual(closed.height, MixerLayout.panelHeight)
        XCTAssertEqual(open.height, MixerLayout.pickerPanelHeight)
        XCTAssertGreaterThan(open.height, closed.height)
        XCTAssertEqual(open.width, MixerLayout.pickerWidth,
                       "a two-strip panel is 136pt and the picker needs 300")
    }

    /// 24 header + 154 lists + 30 footer.
    func testThePickerPanelIsAsTallAsItsParts() {
        XCTAssertEqual(MixerLayout.pickerPanelHeight, 24 + 154 + 30)
        XCTAssertEqual(MixerLayout.pickerPanelHeight, 208)
    }

    /// A wide rack does not SHRINK to the picker's width: the panel keeps the
    /// room it had, or the reader watches it jump narrower to choose a sound
    /// and wider again to see the result.
    func testAWideRackKeepsItsWidthWhileThePickerIsOpen() {
        let six = MixerLayout.panelWidth(channels: 6)
        XCTAssertGreaterThan(six, MixerLayout.pickerWidth)
        XCTAssertEqual(MixerLayout.panelSize(channels: 6, picking: true).width, six)
    }

    /// The family column is the narrower half, and both fit inside the panel
    /// with the divider between them.
    func testTheTwoColumnsFitThePicker() {
        XCTAssertLessThan(MixerLayout.pickerFamilyWidth,
                          MixerLayout.pickerWidth - MixerLayout.pickerFamilyWidth,
                          "the instrument names are longer than the family names")
        XCTAssertGreaterThan(MixerLayout.pickerWidth,
                             MixerLayout.pickerFamilyWidth + MixerLayout.dividerWidth)
    }

    /// Seven rows of list. The instrument column never needs more than the
    /// nine a drum-kit family holds, so it is the FAMILY column that scrolls.
    func testThePickerShowsSevenRowsAtATime() {
        XCTAssertEqual(MixerLayout.pickerListHeight / MixerLayout.pickerRowHeight, 7)
        XCTAssertGreaterThan(GeneralMIDI.Family.allCases.count, 7,
                             "so the family column scrolls")
        XCTAssertEqual(GeneralMIDI.instruments(in: .piano).count, 8)
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
        XCTAssertEqual(clear.x, 1000 - 400 - MixerLayout.padding)
        XCTAssertEqual(crowded.y, clear.y - 120, "it lifts by exactly the lanes")
        XCTAssertLessThan(crowded.y, clear.y)
    }

    func testTheOtherCornersGoWhereTheySay() {
        let bounds = CGSize(width: 1000, height: 800)
        let panel = CGSize(width: 400, height: 268)
        let pad = MixerLayout.padding
        XCTAssertEqual(MixerLayout.origin(for: .topLeading, panel: panel,
                                          in: bounds, lanesInset: 0),
                       CGPoint(x: pad, y: pad))
        XCTAssertEqual(MixerLayout.origin(for: .topTrailing, panel: panel,
                                          in: bounds, lanesInset: 0).x, 1000 - 400 - pad)
        XCTAssertEqual(MixerLayout.origin(for: .bottomLeading, panel: panel,
                                          in: bounds, lanesInset: 0).x, pad)
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

/// What the scrubber's chip says while a finger is on it.
///
/// Its VISIBILITY is a one-line `if let scrubbing` in the view and XCUITest
/// cannot assert inside a gesture -- every gesture runs on the main thread with
/// no hook part-way through. What matters and what is testable is the CONTENT:
/// musicians navigate by bar, so a chip reading `2:14` would be useless at a
/// music stand even though it is the same instant.
final class MixerScrubChipTests: XCTestCase {

    private let timeline = PlaybackTimeline(
        parts: [],
        bars: (0..<40).map { .init(measure: $0 + 1, start: Double($0) * 4,
                                   end: Double($0) * 4 + 4) },
        clicks: [], tempos: [.init(beat: 0, bpm: 120)], beats: 160)

    func testTheChipNamesTheBarUnderTheHandle() {
        XCTAssertEqual(timeline.bar(atBeat: 0), 1)
        XCTAssertEqual(timeline.bar(atBeat: 80), 21, "bar 21, as the spec's example")
        XCTAssertEqual(timeline.bar(atBeat: 83.9), 21)
        XCTAssertEqual(timeline.bar(atBeat: 84), 22)
    }

    /// Off the end of the performance there is no bar, and the chip shows
    /// nothing rather than inventing one.
    func testPastTheEndThereIsNoBarToName() {
        XCTAssertNil(timeline.bar(atBeat: 160))
        XCTAssertNil(timeline.bar(atBeat: -1))
    }

    /// And the handle's position is the fraction of the performance, so
    /// dragging to the middle lands in the middle of the MUSIC -- which for a
    /// score with repeats is the middle of what is PLAYED, not of what is
    /// engraved.
    func testTheHandleTracksThePerformanceNotTheEngraving() {
        let repeated = PlaybackTimeline(
            parts: [],
            bars: [.init(measure: 1, start: 0, end: 4),
                   .init(measure: 2, start: 4, end: 8),
                   .init(measure: 1, start: 8, end: 12),
                   .init(measure: 2, start: 12, end: 16)],
            clicks: [], tempos: [], beats: 16)
        // Halfway through the PERFORMANCE is the second pass of bar 1.
        XCTAssertEqual(repeated.bar(atBeat: 16 * 0.5), 1)
        XCTAssertEqual(repeated.bar(atBeat: 16 * 0.25), 2)
    }
}
