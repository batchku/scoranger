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
        XCTAssertTrue(voices.isOn("Viola"))
        XCTAssertTrue(voices.mutedTracks(in: quartet).isEmpty)
        XCTAssertEqual(voices.summary(in: quartet, metronome: false), "all voices")
    }

    func testATrackIndexIsAPartIndex() {
        var voices = PlaybackVoices()
        voices.toggle("Viola")
        XCTAssertEqual(voices.mutedTracks(in: quartet), [2])
        XCTAssertEqual(voices.summary(in: quartet, metronome: false), "3 of 4 voices")
    }

    /// The two violins carry the SAME instrument name. Keying on the
    /// instrument would collapse them into one switch and silence both.
    func testTwoPartsSharingAnInstrumentAreStillTwoVoices() {
        var voices = PlaybackVoices()
        voices.toggle("Violin I")
        XCTAssertEqual(voices.mutedTracks(in: quartet), [0])
        XCTAssertTrue(voices.isOn("Violin II"))
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

    /// Held by NAME for the same reason a selection is held by address: an op
    /// that removes a part renumbers every part after it. Muting the viola and
    /// then removing Violin II must not leave the cello silent instead.
    func testAMuteSurvivesAPartBeingRemovedFromTheArrangement() {
        var voices = PlaybackVoices()
        voices.toggle("Viola")
        XCTAssertEqual(voices.mutedTracks(in: quartet), [2])

        let trio: [PlaybackTimeline.Part] = [
            .init(index: 0, name: "Violin I", instrument: "Violin", program: 40),
            .init(index: 1, name: "Viola", instrument: "Viola", program: 41),
            .init(index: 2, name: "Violoncello", instrument: "Violoncello", program: 42),
        ]
        XCTAssertEqual(voices.mutedTracks(in: trio), [1],
                       "the viola is still the muted one, at its new index")
        XCTAssertEqual(voices.summary(in: trio, metronome: false), "2 of 3 voices")
    }

    /// A name left over from an earlier version silences nothing and must not
    /// make the app think everything is off.
    func testAStaleNameIsSimplyIgnored() {
        let voices = PlaybackVoices(silenced: ["Accordion L.H."])
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
