import XCTest

/// What a mixer strip is CALLED when two staves share a name.
///
/// Ali: "wrong instruments on the wrong staffs". The audio routing was proven
/// correct per staff, 16 of 16, so the remaining suspect was representation --
/// and a grand staff is where it bites. One MusicXML part, two staves, and
/// music21 splits it into two PartStaffs that BOTH answer "Piano". So the
/// mixer showed "Piano" and "Piano": each strip driving its own staff
/// correctly, and neither of them nameable.
///
/// The engine reports the name exactly as the page spells it, duplicates and
/// all, and that is deliberate -- a strip calling itself something the page
/// does not is a strip nobody can match to a staff. So the telling-apart
/// happens in the label, by the clef, which is the thing the reader can see.
final class MixerStripLabelTests: XCTestCase {

    private func part(_ index: Int, _ name: String, clef: String? = nil)
        -> PlaybackTimeline.Part {
        PlaybackTimeline.Part(index: index, name: name, instrument: nil,
                              program: nil, clef: clef)
    }

    func testDistinctNamesAreLeftAlone() {
        let parts = [part(0, "Violin I", clef: "treble"),
                     part(1, "Acc. Bass", clef: "bass")]
        XCTAssertEqual(PlaybackChannels.labels(for: parts), ["Violin I", "Acc. Bass"])
    }

    func testAGrandStaffIsToldApartByItsClefs() {
        // one part, two staves, one name -- the case that started this
        let parts = [part(0, "Piano", clef: "treble"),
                     part(1, "Piano", clef: "bass")]
        XCTAssertEqual(PlaybackChannels.labels(for: parts),
                       ["Piano · treble", "Piano · bass"])
    }

    func testTheOrdinalIsTheFallbackWhenClefsCannotTellThemApart() {
        // two scanned staves both called Voice, both in treble: genuinely
        // alike, so the ordinal at least says which is higher up the page
        let parts = [part(0, "Voice", clef: "treble"),
                     part(1, "Voice", clef: "treble")]
        XCTAssertEqual(PlaybackChannels.labels(for: parts), ["Voice 1", "Voice 2"])
    }

    func testAMissingClefFallsBackRatherThanLabellingHalfOfThem() {
        // an older engine sent no clef at all; half a clef is worse than none
        let parts = [part(0, "Voice"), part(1, "Voice", clef: "bass")]
        XCTAssertEqual(PlaybackChannels.labels(for: parts), ["Voice 1", "Voice 2"])
    }

    func testThreeStavesOfOneNameStillEachGetOne() {
        let parts = [part(0, "Organ", clef: "treble"),
                     part(1, "Organ", clef: "bass"),
                     part(2, "Organ", clef: "percussion")]
        XCTAssertEqual(PlaybackChannels.labels(for: parts),
                       ["Organ · treble", "Organ · bass", "Organ · percussion"])
    }

    func testTheRawNameIsNeverRewritten() {
        // canCarry and every engine op compare the reported name; only the
        // DISPLAY is qualified
        let parts = [part(0, "Piano", clef: "treble"), part(1, "Piano", clef: "bass")]
        XCTAssertTrue(PlaybackChannels.canCarry(from: parts, to: parts))
        XCTAssertEqual(parts.map(\.name), ["Piano", "Piano"])
    }

    func testTheLabelForAChannelIsFoundByIndexNotPosition() {
        let parts = [part(7, "Piano", clef: "treble"), part(9, "Piano", clef: "bass")]
        XCTAssertEqual(PlaybackChannels.label(at: 9, in: parts), "Piano · bass")
        XCTAssertEqual(PlaybackChannels.label(at: 7, in: parts), "Piano · treble")
    }
}
