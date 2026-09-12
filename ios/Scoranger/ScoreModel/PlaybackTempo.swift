import Foundation

/// The tempo the reader is playing at, and what the transport says about it.
///
/// The score names a tempo, or it does not and 120 is the writer's default.
/// Either way a player practising wants it SLOWER, and until now the only
/// tempo in the app was whatever the arrangement was written at.
///
/// The mixer's tempo slider and the transport's readout are ONE value here.
/// They were nearly two -- a slider holding its own bpm beside a readout
/// printing the timeline's -- and two sources for one fact is exactly how the
/// playhead and the bar readout drifted apart in 0.5.
enum PlaybackTempo {

    /// 1 to 300 bpm. 1 is absurd and it is also the whole point: someone
    /// learning a passage sets it as slow as it will go.
    static let minimum: Double = 1
    static let maximum: Double = 480

    /// What a score that names no tempo is played at. The same 120
    /// `PlaybackTimeline.openingTempo` falls back to, stated once.
    static let fallback: Double = 120

    static func clamp(_ bpm: Double) -> Double {
        guard bpm.isFinite else { return fallback }
        return min(max(bpm, minimum), maximum)
    }

    /// The sequencer's playback rate for a chosen tempo.
    ///
    /// `AVAudioSequencer` has no "set the tempo" -- it runs the MIDI file's own
    /// tempo map and scales it by `rate`. So a target of 60 against a score
    /// written at 120 is rate 0.5, and a mid-score tempo change still works
    /// because every tempo in the map is scaled by the same factor.
    static func rate(target: Double, opening: Double) -> Double {
        let base = opening.isFinite && opening > 0 ? opening : fallback
        return clamp(target) / base
    }

    /// Where the slider's handle sits, 0 at 1 bpm and 1 at 300.
    ///
    /// Linear, not logarithmic. A log scale would give the slow end the room
    /// it deserves, and it would also make the number under the handle move
    /// at a rate nobody can predict; the number is what the reader is aiming
    /// at, so the travel matches it.
    static func fraction(forBPM bpm: Double) -> Double {
        (clamp(bpm) - minimum) / (maximum - minimum)
    }

    /// The tempo for a drag, rounded to whole bpm -- the slider prints an
    /// integer, so it must be able to land on one.
    static func bpm(forFraction fraction: Double) -> Double {
        guard fraction.isFinite else { return fallback }
        let f = min(max(fraction, 0), 1)
        return (minimum + f * (maximum - minimum)).rounded()
    }

    /// What the transport prints, and what the mixer prints under its slider.
    ///
    /// Three states, and each of them is a different fact:
    ///   - the reader set it: `92 bpm` -- theirs, and no qualifier needed
    ///   - the arrangement names one: `92 bpm`
    ///   - nobody named one: `120 (default)` -- 120 nobody chose is not 120
    ///     an arranger chose, and a player setting up to practise deserves to
    ///     know which they are hearing
    static func label(bpm: Double, fromScore: Bool, overridden: Bool) -> String {
        let rounded = Int(clamp(bpm).rounded())
        if overridden || fromScore { return "\(rounded) bpm" }
        return "\(rounded) (default)"
    }

    /// The tempo in force: what the reader set, else what the score says.
    static func effective(override: Double?, opening: Double) -> Double {
        clamp(override ?? opening)
    }
}
