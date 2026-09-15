import XCTest

/// The checklist line for a harmony, and the words it uses.
///
/// Ali asked for a violin part a sixth below the tune. The step he watches while
/// it happens should say what the music is doing, so a signed number of scale
/// degrees has to come back out as the interval a musician says.
///
/// That the tool is OFFERED at all -- in ops.py, cli.py, chat.py, bridge.py and
/// the on-device table in ChatTools.swift, five hand-maintained lists -- is
/// asserted in engine/scripts/check_diatonic.py, which can read all five at
/// once. The table itself moved into ScoreModel in 0.8.2, so what the app does
/// with a tool call is now asserted here too: ChatDispatchTests.
final class DiatonicHarmonyTests: XCTestCase {

    // MARK: the checklist line the reader watches

    private func title(_ degrees: String) -> String {
        ChatSteps.stepTitle(name: "transpose_diatonic",
                            argsJSON: #"{"degrees": "\#(degrees)", "parts": ["Violin II"]}"#)
    }

    func testTheStepSaysWhatTheMusicIsDoing() {
        // not "Transpose diatonic", which is the tool's name and not the music
        XCTAssertEqual(title("-6"), "Harmonising a sixth below, in key")
        XCTAssertEqual(title("3"), "Harmonising a third above, in key")
        XCTAssertEqual(title("8"), "Harmonising an octave above, in key")
        XCTAssertEqual(title("-2"), "Harmonising a second below, in key")
    }

    func testAnIntervalTheTableDoesNotNameStillReads() {
        XCTAssertEqual(title("-13"), "Harmonising 13 steps below, in key")
        // and a word, which the engine accepts, is passed through rather than mangled
        XCTAssertEqual(title("down a sixth"), "Harmonising down a sixth, in key")
    }
}
