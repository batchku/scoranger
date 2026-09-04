import AVFoundation
import XCTest

/// The sound bank has to travel WITH the app.
///
/// Ali reported every part playing the same pure tone on his iPad, and
/// instrument changes doing nothing. Both are one fault: `PlaybackSound.bank`
/// pointed at
///
///     /System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls
///
/// which is a MACOS path. It is not in the iOS SDK -- that SDK has no
/// `System/Library/Components` at all -- and it is not in the simulator
/// runtime's root either. It resolved in the simulator because a simulator
/// process falls through to the HOST Mac's filesystem, where the file really
/// does live. The code even recorded the clue and drew the wrong conclusion
/// from it: "a search of the simulator runtime's RuntimeRoot does not show
/// this file: only asking the running system does."
///
/// So on a device `loadSoundBankInstrument` throws, `loadInstrument` swallows
/// it, and an `AVAudioUnitSampler` with no instrument loaded plays its own
/// built-in tone -- a near sine, the same one on every channel, unchanged by
/// any program change. Which is exactly what Ali heard.
///
/// A timbre test cannot catch this, because in the simulator the bank loads
/// and the timbres are real. THIS is the test that catches it: the app may
/// not depend on a file it does not carry. It is structural on purpose --
/// the failure is structural, and the gate runs where the bug is invisible.
final class PlaybackBankTests: XCTestCase {

    func testTheSoundBankIsCarriedByTheAppAndNotBorrowedFromTheHost() throws {
        let bank = try XCTUnwrap(PlaybackSound.bank,
                                 "this build carries no sound bank at all, so "
                                 + "every part plays the sampler's built-in "
                                 + "tone -- run ios/scripts/fetch_soundfont.sh")

        XCTAssertFalse(bank.path.hasPrefix("/System/"),
                       "the sound bank is a host system file (\(bank.path)). "
                       + "That path does not exist on an iPad, so every part "
                       + "falls back to the sampler's built-in tone.")
        XCTAssertFalse(bank.path.hasPrefix("/Library/"),
                       "the sound bank is outside the app: \(bank.path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bank.path),
                      "the sound bank is not where PlaybackSound says it is: "
                      + "\(bank.path)")
    }

    /// The bank resolves out of a bundle rather than an absolute path, which
    /// is what makes the previous assertion true on a device as well as here.
    func testTheBankResolvesFromTheBundleThatShipsIt() throws {
        let bank = try XCTUnwrap(PlaybackSound.bank)
        let bundles = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
        let carried = bundles.contains { bundle in
            bank.path.hasPrefix(bundle.bundlePath)
        }
        XCTAssertTrue(carried,
                      "the bank at \(bank.path) is in no bundle this build "
                      + "ships, so nothing guarantees it is on the device")
    }
}
