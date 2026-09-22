import XCTest

/// The checklist line for a harmony, and the words it uses.
///
/// Ali asked for a violin part a sixth below the tune. The step he watches while
/// it happens should say what the music is doing, so a signed number of scale
/// degrees has to come back out as the interval a musician says.
///
/// The verb was "Harmonising" until a screen recording showed it over the wrong
/// music: a lasso of ten notes, "transpose up an octave", and a step that
/// claimed to be harmonising above a sentence that correctly said it had
/// transposed. The op moves a line and never writes a second one, so it is a
/// transposition in both readings -- ", in key" is what separates it from the
/// chromatic `transpose` beside it.
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
        XCTAssertEqual(title("-6"), "Transposing a sixth below, in key")
        XCTAssertEqual(title("3"), "Transposing a third above, in key")
        XCTAssertEqual(title("8"), "Transposing an octave above, in key")
        XCTAssertEqual(title("-2"), "Transposing a second below, in key")
    }

    /// The selection form takes the same words: it is the one Ali watched, and
    /// nothing about a lasso makes the move a harmony.
    func testTheSelectionFormSaysTheSame() {
        let selected = ChatSteps.stepTitle(
            name: "transpose_diatonic_elements",
            argsJSON: #"{"degrees": "8", "elements": "s1/m1/l1/note#0"}"#)
        XCTAssertEqual(selected, "Transposing an octave above, in key")
    }

    func testAnIntervalTheTableDoesNotNameStillReads() {
        XCTAssertEqual(title("-13"), "Transposing 13 steps below, in key")
        // and a word, which the engine accepts, is passed through rather than mangled
        XCTAssertEqual(title("down a sixth"), "Transposing down a sixth, in key")
    }
}
