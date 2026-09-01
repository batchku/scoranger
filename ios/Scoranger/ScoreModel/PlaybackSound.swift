import Foundation

/// Which sound a part is played with, and where the clicks come from.
///
/// Pure, and separate from `PlaybackEngine`, because everything here is a
/// decision -- which General MIDI program, what a click is, when the
/// performance is over -- while the engine is only wiring. Decisions are worth
/// testing; wiring is worth keeping short.
///
/// The bank path was CONFIRMED on the iOS 26.5 runtime rather than remembered.
/// Worth saying, because a search of the simulator runtime's `RuntimeRoot`
/// does not show this file: only asking the running system does.
enum PlaybackSound {

    /// Apple's General MIDI sound set, shipped with the OS.
    static let bank = URL(fileURLWithPath:
        "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")

    /// The melodic bank. Every pitched instrument lives here.
    static let melodicBankMSB: UInt8 = 0x79
    /// The percussion bank, which is where a woodblock is.
    static let percussionBankMSB: UInt8 = 0x78
    static let bankLSB: UInt8 = 0

    /// What a part with no named instrument is played as.
    ///
    /// Acoustic Grand, deliberately plain. Every staff optical recognition
    /// labels "Voice" arrives with no program at all, and a piano reads as
    /// "no instrument chosen" to a listener in a way that, say, a trumpet
    /// would not.
    static let fallbackProgram: UInt8 = 0

    /// The General MIDI program for a part.
    ///
    /// The engine emits nil rather than guessing, so the guess is made here,
    /// once, where it can be seen. A program outside 0-127 is not a program;
    /// music21 has never emitted one, but the value crosses a JSON boundary
    /// and clamping is cheaper than a crash.
    static func program(for part: PlaybackTimeline.Part) -> UInt8 {
        guard let program = part.program, (0...127).contains(program) else {
            return fallbackProgram
        }
        return UInt8(program)
    }

    /// The click itself: a high woodblock on the downbeat, a low one between.
    ///
    /// Two different sounds, not one louder one. A player checking whether
    /// they are on beat 1 or beat 3 hears pitch far more readily than volume,
    /// which is the entire job of a metronome in a bar of five.
    static func click(down: Bool) -> (key: UInt8, velocity: UInt8) {
        down ? (76, 112) : (77, 84)
    }

    /// The percussion program the click sampler loads.
    static let clickProgram: UInt8 = 0

    /// Whether the performance has run out.
    ///
    /// `AVAudioSequencer` does not stop at the end of its content -- it runs
    /// on into silence, and the transport would sit there saying it was
    /// playing. The timeline knows where the music ends, so it is asked.
    ///
    /// A timeline with no length never stops anything: a score that failed to
    /// produce a map should not silence itself the instant it starts.
    static func hasFinished(beat: Double, end: Double) -> Bool {
        end > 0 && beat >= end
    }
}
