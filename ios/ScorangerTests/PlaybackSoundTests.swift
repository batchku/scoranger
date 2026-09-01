import XCTest

/// Which sound a part is played with, and when the performance is over.
final class PlaybackSoundTests: XCTestCase {

    private func part(program: Int?) -> PlaybackTimeline.Part {
        .init(index: 0, name: "P", instrument: nil, program: program)
    }

    func testAPartsOwnProgramIsUsed() {
        XCTAssertEqual(PlaybackSound.program(for: part(program: 40)), 40)
        XCTAssertEqual(PlaybackSound.program(for: part(program: 0)), 0)
        XCTAssertEqual(PlaybackSound.program(for: part(program: 127)), 127)
    }

    /// Every staff optical recognition labels "Voice" arrives with no program.
    /// The engine refuses to guess; the guess is made here, once, where it can
    /// be seen.
    func testAPartWithNoInstrumentFallsBackRatherThanFailing() {
        XCTAssertEqual(PlaybackSound.program(for: part(program: nil)),
                       PlaybackSound.fallbackProgram)
    }

    /// The value crosses a JSON boundary. music21 has never emitted one out of
    /// range, but clamping costs less than a trap in a UInt8 conversion.
    func testAProgramOutsideGeneralMIDIIsNotTrusted() {
        XCTAssertEqual(PlaybackSound.program(for: part(program: 128)),
                       PlaybackSound.fallbackProgram)
        XCTAssertEqual(PlaybackSound.program(for: part(program: -1)),
                       PlaybackSound.fallbackProgram)
    }

    /// Two different sounds, not one louder one. A player checking whether
    /// they are on beat 1 or beat 3 hears pitch far more readily than volume.
    func testTheDownbeatIsADifferentSoundAndNotJustALouderOne() {
        let down = PlaybackSound.click(down: true)
        let other = PlaybackSound.click(down: false)
        XCTAssertNotEqual(down.key, other.key)
        XCTAssertGreaterThan(down.velocity, other.velocity)
    }

    /// `AVAudioSequencer` runs on into silence past the end of its content, so
    /// something has to say when the music has finished.
    func testThePerformanceEndsWhereTheTimelineSaysItDoes() {
        XCTAssertFalse(PlaybackSound.hasFinished(beat: 23.9, end: 24))
        XCTAssertTrue(PlaybackSound.hasFinished(beat: 24, end: 24))
        XCTAssertTrue(PlaybackSound.hasFinished(beat: 30, end: 24))
    }

    /// A score whose map came back empty must not silence itself the instant
    /// it starts -- that would look exactly like playback being broken.
    func testATimelineWithNoLengthNeverStopsAnything() {
        XCTAssertFalse(PlaybackSound.hasFinished(beat: 0, end: 0))
        XCTAssertFalse(PlaybackSound.hasFinished(beat: 100, end: 0))
    }

    /// Melodic and percussion are different banks. Loading the click from the
    /// melodic one gives a piano note where a woodblock should be.
    func testTheClickComesFromThePercussionBank() {
        XCTAssertNotEqual(PlaybackSound.percussionBankMSB, PlaybackSound.melodicBankMSB)
    }
}
