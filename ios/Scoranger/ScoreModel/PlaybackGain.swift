import Foundation

/// What a channel strip's fader means in amplitude.
///
/// The scale a reader sees is 0-10. What the audio graph wants is a linear
/// amplitude multiplier for `AVAudioUnitSampler.volume`, which the gain spike
/// measured as exactly linear: setting 0.25 produced a quarter of the RMS.
///
/// So the only decision here is the CURVE between them, and it is not the
/// identity. Straight linear amplitude puts the midpoint at -6 dB, which means
/// the bottom half of the fader does almost nothing and every setting anyone
/// wants bunches into the top two notches. The standard audio taper -- a
/// squared fader, approximating a log pot -- spreads the useful range across
/// the whole travel.
///
///     10   0 dB      unity
///      7  -6.2 dB    the default, leaving headroom to push a channel UP
///      5  -12 dB
///      3  -20.5 dB
///      1  -40 dB
///      0   silence   exact, not an approximation of -infinity
///
/// The one honest caveat, and the reason `taper` is a named constant rather
/// than a literal 2: perceptual halving is about -10 dB, so the 5 notch reads
/// slightly under half as loud rather than exactly half. Two decibels is less
/// than the spacing between notches, and squared is the standard. If exact
/// half-loudness at 5 is ever wanted, `perceptualHalvingTaper` is the exponent
/// that gives it and this is a one-line change.
enum PlaybackGain {

    /// The exponent. See the note above before changing it.
    static let taper: Double = 2.0

    /// The alternative: the exponent that puts the 5 notch at exactly -10 dB,
    /// which is where a listener hears "half as loud".
    static let perceptualHalvingTaper: Double = 1.66

    static let minimumFader = 0
    static let maximumFader = 10

    /// Below unity on purpose. A mixer whose default is already the maximum can
    /// only ever subtract.
    static let defaultFader = 7

    /// The multiplier for `AVAudioUnitSampler.volume`.
    static func amplitude(for fader: Int) -> Double {
        let clamped = min(max(fader, minimumFader), maximumFader)
        // Hard zero rather than pow(0, taper), which is 0 anyway -- said
        // explicitly because "the fader is all the way down" is a state the
        // mixer promises, not a very small number that rounds to one.
        guard clamped > minimumFader else { return 0 }
        return pow(Double(clamped) / Double(maximumFader), taper)
    }

    /// The same value in decibels, which is the form the taper is argued in.
    static func decibels(for fader: Int) -> Double {
        let amplitude = amplitude(for: fader)
        return amplitude > 0 ? 20 * log10(amplitude) : -.infinity
    }
}
