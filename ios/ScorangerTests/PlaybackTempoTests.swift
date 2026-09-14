import XCTest

/// The tempo slider and the transport's readout are one value (0.6.3 #10).
final class PlaybackTempoTests: XCTestCase {

    /// 1 to 480 (0.8.0 build 194: Ali wanted the knob past 240, and the
    /// sequencer's rate is the target over the score's tempo -- 4x at 480
    /// against 120, which AVAudioSequencer honours).
    func testTheRangeIsOneToFourEighty() {
        XCTAssertEqual(PlaybackTempo.minimum, 1)
        XCTAssertEqual(PlaybackTempo.maximum, 480)
        XCTAssertEqual(PlaybackTempo.clamp(0), 1)
        XCTAssertEqual(PlaybackTempo.clamp(-40), 1)
        XCTAssertEqual(PlaybackTempo.clamp(1000), 480)
        XCTAssertEqual(PlaybackTempo.clamp(480), 480)
        XCTAssertEqual(PlaybackTempo.rate(target: 480, opening: 120), 4, accuracy: 1e-9)
        XCTAssertEqual(PlaybackTempo.clamp(92), 92)
    }

    /// A NaN out of a divide-by-zero must not become the tempo, or the
    /// sequencer's rate goes with it and the music stops for good.
    func testNonsenseFallsBackRatherThanPropagating() {
        // Neither is a slow tempo or a fast one -- both mean a calculation went
        // wrong upstream, so both land on the default rather than on an end of
        // the range that would look like a deliberate setting.
        XCTAssertEqual(PlaybackTempo.clamp(.nan), 120)
        XCTAssertEqual(PlaybackTempo.clamp(.infinity), 120)
        XCTAssertEqual(PlaybackTempo.clamp(-.infinity), 120)
    }

    /// `AVAudioSequencer` has no "set the tempo": it plays the file's own tempo
    /// map scaled by `rate`, so halving the target halves the rate -- and a
    /// mid-score tempo change survives, because every tempo scales together.
    func testTheRateIsTheTargetOverTheScoresOwnTempo() {
        XCTAssertEqual(PlaybackTempo.rate(target: 60, opening: 120), 0.5, accuracy: 1e-9)
        XCTAssertEqual(PlaybackTempo.rate(target: 120, opening: 120), 1, accuracy: 1e-9)
        XCTAssertEqual(PlaybackTempo.rate(target: 180, opening: 90), 2, accuracy: 1e-9)
    }

    func testAScoreWithNoTempoIsRatedAgainstTheDefault() {
        XCTAssertEqual(PlaybackTempo.rate(target: 60, opening: 0), 0.5, accuracy: 1e-9)
        XCTAssertEqual(PlaybackTempo.rate(target: 60, opening: .nan), 0.5, accuracy: 1e-9)
    }

    // MARK: - The slider

    func testTheHandleTravelsLinearlyWithTheNumberUnderIt() {
        XCTAssertEqual(PlaybackTempo.fraction(forBPM: 1), 0, accuracy: 1e-9)
        XCTAssertEqual(PlaybackTempo.fraction(forBPM: 480), 1, accuracy: 1e-9)
        XCTAssertEqual(PlaybackTempo.fraction(forBPM: 240.5), 0.5, accuracy: 1e-9)
    }

    /// The slider prints a whole number, so it has to be able to land on one.
    func testADragLandsOnAWholeBeatPerMinute() {
        XCTAssertEqual(PlaybackTempo.bpm(forFraction: 0), 1)
        XCTAssertEqual(PlaybackTempo.bpm(forFraction: 1), 480)
        XCTAssertEqual(PlaybackTempo.bpm(forFraction: 0.5), 241)
        XCTAssertEqual(PlaybackTempo.bpm(forFraction: -3), 1, "a drag off the end clamps")
        XCTAssertEqual(PlaybackTempo.bpm(forFraction: 9), 480)
    }

    func testTheSliderRoundTrips() {
        for bpm in [1.0, 40, 92, 120, 200, 300] {
            let back = PlaybackTempo.bpm(forFraction: PlaybackTempo.fraction(forBPM: bpm))
            XCTAssertEqual(back, bpm, accuracy: 1, "\(bpm) came back as \(back)")
        }
    }

    // MARK: - What it says, in both places

    /// The rule the transport already had: 120 nobody chose is not 120 an
    /// arranger chose.
    func testAnUnchosenTempoStillSaysSo() {
        XCTAssertEqual(PlaybackTempo.label(bpm: 120, fromScore: false, overridden: false),
                       "120 (default)")
        XCTAssertEqual(PlaybackTempo.label(bpm: 92, fromScore: true, overridden: false),
                       "92 bpm")
    }

    /// Once the reader has moved the slider it IS a chosen tempo, so the
    /// qualifier goes -- including over a score that named none.
    func testATempoTheReaderSetIsNeverCalledADefault() {
        XCTAssertEqual(PlaybackTempo.label(bpm: 60, fromScore: false, overridden: true),
                       "60 bpm")
    }

    /// The whole point of putting this in one place: the slider's value and the
    /// transport's readout cannot disagree, because they are the same call.
    func testTheSliderAndTheTransportReadTheSameNumber() {
        let opening = 132.0
        XCTAssertEqual(PlaybackTempo.effective(override: nil, opening: opening), 132)
        XCTAssertEqual(PlaybackTempo.effective(override: 60, opening: opening), 60)
        XCTAssertEqual(PlaybackTempo.effective(override: 9000, opening: opening), 480,
                       "an override is clamped like anything else")
        let shown = PlaybackTempo.effective(override: 60, opening: opening)
        XCTAssertEqual(PlaybackTempo.label(bpm: shown, fromScore: true, overridden: true),
                       "60 bpm")
        XCTAssertEqual(PlaybackTempo.fraction(forBPM: shown),
                       PlaybackTempo.fraction(forBPM: 60), accuracy: 1e-9)
    }
}

/// Spacebar starts and stops, except where a space is a space (0.6.3 #9).
final class TransportKeysTests: XCTestCase {

    func testSpacebarTogglesTheTransport() {
        XCTAssertTrue(TransportKeys.spaceToggles(isEditingText: false,
                                                 isTransportShowing: true,
                                                 canPlay: true))
    }

    /// The bug this predicate exists to prevent: a shortcut that eats the space
    /// key makes the chat input and every rename field unusable.
    func testATextFieldWithFocusKeepsItsSpaces() {
        XCTAssertFalse(TransportKeys.spaceToggles(isEditingText: true,
                                                  isTransportShowing: true,
                                                  canPlay: true))
    }

    /// A key that works while the control it drives is off screen does
    /// something invisible.
    func testNoTransportOnScreenMeansNoShortcut() {
        XCTAssertFalse(TransportKeys.spaceToggles(isEditingText: false,
                                                  isTransportShowing: false,
                                                  canPlay: true))
    }

    /// Over a PDF there is no audio, and spacebar must do nothing rather than
    /// look broken.
    func testNothingToPlayMeansNoShortcut() {
        XCTAssertFalse(TransportKeys.spaceToggles(isEditingText: false,
                                                  isTransportShowing: true,
                                                  canPlay: false))
    }
}
