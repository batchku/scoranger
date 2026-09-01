import XCTest

/// Which parts sound, and the one state the whole feature exists for: none of
/// them, so the metronome plays alone.
final class PlaybackVoicesTests: XCTestCase {

    private let quartet: [PlaybackTimeline.Part] = [
        .init(index: 0, name: "Violin I", instrument: "Violin", program: 40),
        .init(index: 1, name: "Violin II", instrument: "Violin", program: 40),
        .init(index: 2, name: "Viola", instrument: "Viola", program: 41),
        .init(index: 3, name: "Violoncello", instrument: "Violoncello", program: 42),
    ]

    func testEverythingSoundsUntilSomethingIsSwitchedOff() {
        let voices = PlaybackVoices()
        XCTAssertTrue(voices.isOn(2))
        XCTAssertTrue(voices.mutedTracks(in: quartet).isEmpty)
        XCTAssertEqual(voices.summary(in: quartet, metronome: false), "all voices")
    }

    func testATrackIndexIsAPartIndex() {
        var voices = PlaybackVoices()
        voices.toggle(2)
        XCTAssertEqual(voices.mutedTracks(in: quartet), [2])
        XCTAssertEqual(voices.summary(in: quartet, metronome: false), "3 of 4 voices")
    }

    /// The two violins carry the SAME instrument name. Keying on the
    /// instrument would collapse them into one switch and silence both.
    func testTwoPartsSharingAnInstrumentAreStillTwoVoices() {
        var voices = PlaybackVoices()
        voices.toggle(0)
        XCTAssertEqual(voices.mutedTracks(in: quartet), [0])
        XCTAssertTrue(voices.isOn(1))
    }

    /// The practice case: all voices off leaves the metronome, and that is a
    /// destination rather than an error.
    func testTurningEverythingOffIsHowYouGetTheMetronomeAlone() {
        var voices = PlaybackVoices()
        voices.setAll(on: false, parts: quartet)
        XCTAssertTrue(voices.everythingOff(in: quartet))
        XCTAssertEqual(voices.mutedTracks(in: quartet), [0, 1, 2, 3])
        XCTAssertEqual(voices.summary(in: quartet, metronome: true), "metronome only")
    }

    func testAndBackAgain() {
        var voices = PlaybackVoices()
        voices.setAll(on: false, parts: quartet)
        voices.setAll(on: true, parts: quartet)
        XCTAssertFalse(voices.everythingOff(in: quartet))
        XCTAssertTrue(voices.mutedTracks(in: quartet).isEmpty)
    }

    /// The price of keying on INDEX, asserted rather than hoped away.
    ///
    /// This test used to prove the opposite: mutes were keyed on name so they
    /// survived a part being removed. Names had to go -- optical recognition
    /// gives four staves one name between them, and one name was one switch
    /// that silenced the whole score. So the guarantee is now structural, and
    /// `canCarry` is where it is enforced: a mute crosses into the next
    /// performance only when the staves did not move.
    func testAMuteIsDroppedWhenAnOpRenumbersTheParts() {
        var voices = PlaybackVoices()
        voices.toggle(2)                                  // the viola
        XCTAssertEqual(voices.mutedTracks(in: quartet), [2])

        let trio: [PlaybackTimeline.Part] = [
            .init(index: 0, name: "Violin I", instrument: "Violin", program: 40),
            .init(index: 1, name: "Viola", instrument: "Viola", program: 41),
            .init(index: 2, name: "Violoncello", instrument: "Violoncello", program: 42),
        ]
        // Index 2 is the CELLO now. Carrying the mute would silence it, so the
        // mute does not travel.
        XCTAssertFalse(PlaybackChannels.canCarry(from: quartet, to: trio),
                       "a part was removed; the indices moved under the mutes")
    }

    /// And it DOES travel through the ops that leave the staves alone, which
    /// is most of them -- transposing a passage must not cost the reader the
    /// mix they set up to practise against.
    func testAMuteSurvivesAnOpThatLeavesTheStavesAlone() {
        XCTAssertTrue(PlaybackChannels.canCarry(from: quartet, to: quartet))
        let renamed: [PlaybackTimeline.Part] = [
            .init(index: 0, name: "Violin I", instrument: "Violin", program: 40),
            .init(index: 1, name: "Violin II", instrument: "Violin", program: 40),
            .init(index: 2, name: "Bratsche", instrument: "Viola", program: 41),
            .init(index: 3, name: "Violoncello", instrument: "Violoncello", program: 42),
        ]
        XCTAssertFalse(PlaybackChannels.canCarry(from: quartet, to: renamed),
                       "a renamed staff is a staff the reader must look at again")
    }

    /// The captions: exactly what the page says, and told apart only where the
    /// page repeats itself.
    func testDuplicateStaffLabelsAreDisambiguatedForDisplayOnly() {
        let scanned: [PlaybackTimeline.Part] = (0..<4).map {
            .init(index: $0, name: "Voice", instrument: nil, program: nil)
        }
        XCTAssertEqual(PlaybackChannels.labels(for: scanned),
                       ["Voice 1", "Voice 2", "Voice 3", "Voice 4"])
        // and a score whose staves are already distinct is left alone
        XCTAssertEqual(PlaybackChannels.labels(for: quartet),
                       ["Violin I", "Violin II", "Viola", "Violoncello"])
    }

    /// A name left over from an earlier version silences nothing and must not
    /// make the app think everything is off.
    func testAStaleNameIsSimplyIgnored() {
        let voices = PlaybackVoices(silenced: [7])
        XCTAssertTrue(voices.mutedTracks(in: quartet).isEmpty)
        XCTAssertFalse(voices.everythingOff(in: quartet))
        XCTAssertEqual(voices.summary(in: quartet, metronome: false), "all voices")
    }

    /// An arrangement with no parts is not "everything off" -- there is
    /// nothing to be off, and calling it metronome-only would light a state
    /// the reader never chose.
    func testNoPartsIsNotEverythingOff() {
        let voices = PlaybackVoices()
        XCTAssertFalse(voices.everythingOff(in: []))
        XCTAssertEqual(voices.summary(in: [], metronome: false), "no parts")
    }

    /// The one the transport was getting wrong: every voice off AND the
    /// metronome off is not "metronome only", it is silence. A reader who
    /// presses play on that and is told the metronome is playing goes looking
    /// for a broken speaker.
    func testEveryVoiceOffWithNoMetronomeIsSilenceAndSaysSo() {
        var voices = PlaybackVoices()
        voices.setAll(on: false, parts: quartet)
        XCTAssertEqual(voices.summary(in: quartet, metronome: false), "silent")
        XCTAssertEqual(voices.summary(in: quartet, metronome: true), "metronome only")
    }

    /// The line under the voice list, which is the only place the reader is
    /// told how to reach the practice case at all.
    func testTheVoiceListSaysWhatWillActuallyBeHeard() {
        var voices = PlaybackVoices()
        XCTAssertEqual(voices.advice(in: quartet, metronome: false),
                       "turn every voice off to play along to the click")
        voices.setAll(on: false, parts: quartet)
        XCTAssertEqual(voices.advice(in: quartet, metronome: true),
                       "the metronome plays alone")
        XCTAssertEqual(voices.advice(in: quartet, metronome: false),
                       "nothing will sound: switch the metronome on")
    }
}
