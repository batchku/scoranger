import Foundation

/// Which sound a part is played with, and where the clicks come from.
///
/// Pure, and separate from `PlaybackEngine`, because everything here is a
/// decision -- which General MIDI program, what a click is, when the
/// performance is over -- while the engine is only wiring. Decisions are worth
/// testing; wiring is worth keeping short.
enum PlaybackSound {

    /// The General MIDI bank, out of the bundle that carries this code.
    ///
    /// **The app has to bring its own.** This was an absolute path into macOS
    /// for six months --
    /// `/System/Library/Components/CoreAudio.component/.../gs_instruments.dls`,
    /// Apple's own bank -- and it worked in every test and on nobody's iPad.
    /// There is no `System/Library/Components` in the iOS SDK and none in the
    /// simulator runtime's root; a simulator process falls through to the HOST
    /// Mac's filesystem, where that file really does live, so the simulator
    /// loaded real timbres and the device loaded nothing. The comment here
    /// even recorded the clue and drew the wrong conclusion from it: "a search
    /// of the simulator runtime's RuntimeRoot does not show this file: only
    /// asking the running system does."
    ///
    /// What a device did instead: `loadSoundBankInstrument` threw,
    /// `PlaybackGraph.loadInstrument` swallowed it, and an
    /// `AVAudioUnitSampler` with no instrument loaded plays its own built-in
    /// tone -- a near sine, the same one on every channel, deaf to every
    /// program change. Which is what Ali heard: "all playback is using the
    /// same synth; it sounds like pure sinusoids; changing instruments does
    /// nothing."
    ///
    /// iOS ships no General MIDI bank an app is allowed to load, and Apple's
    /// is not redistributable, so the app carries GeneralUser GS
    /// (ios/scripts/fetch_soundfont.sh). It is fetched rather than committed,
    /// like Python and Verovio, and bundled into the app target AND the test
    /// target -- the unit tests have no host app, and a bank wired into the
    /// app alone would leave every offline render measuring the fallback tone
    /// again.
    ///
    /// `Bundle(for:)` rather than `Bundle.main`: this file compiles into both
    /// targets, and in the unit bundle `Bundle.main` is the XCTest runner. The
    /// bundle that carries THIS CODE is the bundle that carries the bank.
    ///
    /// Optional, and not a path that might not exist. A build without a bank
    /// is a build with no sound at all, and `PlaybackGraph` records that on
    /// every channel (`bankFailures`) rather than pretending a load was
    /// attempted. `PlaybackBankTests` and `check_vendored_soundfont.py` are
    /// what make it never nil in a shipped build.
    static let bank: URL? = Bundle(for: BankBundle.self)
        .url(forResource: bankName, withExtension: "sf2",
             subdirectory: "SoundFonts")
        ?? Bundle.main.url(forResource: bankName, withExtension: "sf2",
                           subdirectory: "SoundFonts")

    /// The vendored file's own name, in one place: the fetch script writes it,
    /// project.yml bundles it and this reads it back.
    static let bankName = "GeneralUser-GS"

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

/// Only so `Bundle(for:)` has a class to name. `PlaybackSound` is an enum and
/// `Bundle.main` is the wrong answer in the test bundle.
private final class BankBundle {}
