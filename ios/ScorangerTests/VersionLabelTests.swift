import XCTest

/// The version list read "v001 bulk-import" and "v002 omr". Ali marked both
/// "Don't!": those are the engine's pipeline names, not a history of what he
/// did to his music.
final class VersionLabelTests: XCTestCase {

    func testTheTwoInTheScreenshot() {
        XCTAssertEqual(VersionLabel.text("bulk-import"), "imported")
        XCTAssertEqual(VersionLabel.text("omr"), "transcribed from the scan")
    }

    func testTheOpsAReaderMeetsMostAreSpelledOut() {
        XCTAssertEqual(VersionLabel.text("transpose"), "transposed")
        XCTAssertEqual(VersionLabel.text("keep-parts"), "parts kept")
        XCTAssertEqual(VersionLabel.text("change-instrument"), "instrument changed")
        XCTAssertEqual(VersionLabel.text("set-metadata"), "title and credits")
        XCTAssertEqual(VersionLabel.text("guitar-tab"), "guitar tab added")
    }

    /// The point of the fallback: there are about forty ops and this table will
    /// fall behind. What it may never do is leak the name it does not know.
    func testAnUnknownOpDegradesRatherThanLeaking() {
        XCTAssertEqual(VersionLabel.text("some-future-op"), "edited")
        XCTAssertEqual(VersionLabel.text(""), "edited")
        XCTAssertEqual(VersionLabel.text(nil), "edited")
        XCTAssertFalse(VersionLabel.text("some-future-op").contains("some-future-op"))
    }

    /// Every op the engine has, run through the table: none may come back as
    /// itself. This is the assertion the screenshot was about.
    func testNoOpNameSurvivesIntoARow() {
        let everyOp = Array(VersionLabel.phrases.keys) + [
            "flatten-voices", "chart-style", "book-extract", "add-version-from-file",
            "some-op-added-next-year", "SET-STRUCTURE",
        ]
        for op in everyOp {
            let shown = VersionLabel.text(op)
            XCTAssertFalse(VersionLabel.isRawOpName(shown),
                           "\(op) came back as an op name: \(shown)")
            // kebab-case with no spaces in it is what an op name looks like.
            // "engine self-test" is a hyphenated PHRASE and reads as English.
            XCTAssertFalse(!shown.contains(" ") && shown.contains("-"),
                           "\(op) -> \(shown) still reads like an op")
            XCTAssertNotEqual(shown.lowercased(), op.lowercased())
        }
    }

    func testTheCaseOfTheOpDoesNotMatter() {
        XCTAssertEqual(VersionLabel.text("OMR"), "transcribed from the scan")
        XCTAssertEqual(VersionLabel.text(" transpose "), "transposed")
    }

    /// What the reader ASKED for beats any phrase written here: it is his own
    /// sentence, and it says more than the op ever could.
    func testAChatPromptWins() {
        XCTAssertEqual(VersionLabel.text(op: "transpose",
                                         prompt: "put this up a tone for the alto"),
                       "put this up a tone for the alto")
    }

    func testWithNoPromptThePhraseIsUsed() {
        XCTAssertEqual(VersionLabel.text(op: "omr", prompt: nil),
                       "transcribed from the scan")
        XCTAssertEqual(VersionLabel.text(op: "omr", prompt: "   "),
                       "transcribed from the scan")
    }
}
