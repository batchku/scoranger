import XCTest

/// The fader curve: what a channel strip's 0-10 means in amplitude.
///
/// Confirmed by the product owner: `(v/10)²`, the standard audio taper, with 0
/// mapped to hard zero. The numbers below are the whole specification, which is
/// why they are written out rather than recomputed by the test.
final class PlaybackGainTests: XCTestCase {

    /// Straight linear amplitude is what this exists to avoid: at 5 it is only
    /// -6 dB, so the bottom half of the fader does almost nothing and every
    /// useful setting bunches into the top two notches.
    func testTheFaderIsSquaredAndNotLinear() {
        XCTAssertEqual(PlaybackGain.amplitude(for: 10), 1.0, accuracy: 1e-9)
        XCTAssertEqual(PlaybackGain.amplitude(for: 7), 0.49, accuracy: 1e-9)
        XCTAssertEqual(PlaybackGain.amplitude(for: 5), 0.25, accuracy: 1e-9)
        XCTAssertEqual(PlaybackGain.amplitude(for: 3), 0.09, accuracy: 1e-9)
        XCTAssertEqual(PlaybackGain.amplitude(for: 1), 0.01, accuracy: 1e-9)
        XCTAssertNotEqual(PlaybackGain.amplitude(for: 5), 0.5,
                          "linear would put 5 at half amplitude")
    }

    /// Zero is SILENCE, not -40 dB and not "very quiet". A fader pulled all the
    /// way down that still leaks is the kind of thing a reader notices only
    /// when they are trying to practise against one part.
    func testZeroIsHardSilence() {
        XCTAssertEqual(PlaybackGain.amplitude(for: 0), 0)
    }

    /// The default sits BELOW unity on purpose, so a channel can be pushed up
    /// as well as pulled down. A mixer whose default is already the maximum
    /// only ever subtracts.
    func testTheDefaultLeavesHeadroomAbove() {
        XCTAssertEqual(PlaybackGain.defaultFader, 7)
        XCTAssertLessThan(PlaybackGain.amplitude(for: PlaybackGain.defaultFader), 1.0)
        XCTAssertGreaterThan(PlaybackGain.amplitude(for: PlaybackGain.defaultFader), 0.4)
    }

    /// The scale is 0-10 and a value crossing any boundary is clamped rather
    /// than trusted: amplitude above 1 clips the mix, and below 0 is not a
    /// number the mixer has a meaning for.
    func testAFaderOffTheScaleIsClamped() {
        XCTAssertEqual(PlaybackGain.amplitude(for: 99), 1.0, accuracy: 1e-9)
        XCTAssertEqual(PlaybackGain.amplitude(for: -3), 0)
    }

    /// In decibels, which is the form the taper is argued in. -6 dB at the
    /// default, -12 at the midpoint. Perceptual halving is about -10 dB, so 5
    /// reads a little under half; the exponent is a named constant so that
    /// judgement can be changed in one line.
    func testTheNotchesInDecibels() {
        XCTAssertEqual(PlaybackGain.decibels(for: 10), 0, accuracy: 0.05)
        XCTAssertEqual(PlaybackGain.decibels(for: 7), -6.2, accuracy: 0.05)
        XCTAssertEqual(PlaybackGain.decibels(for: 5), -12.04, accuracy: 0.05)
        XCTAssertEqual(PlaybackGain.decibels(for: 0), -.infinity)
    }

    /// The alternative the owner asked to keep one line away.
    func testTheExponentIsNamedSoTheJudgementCanBeChanged() {
        XCTAssertEqual(PlaybackGain.taper, 2.0)
        XCTAssertEqual(PlaybackGain.perceptualHalvingTaper, 1.66, accuracy: 1e-9)
    }
}
