import XCTest

/// A PDF arrangement is readable and annotatable, and not editable.
final class ScoreArtifactTests: XCTestCase {
    func testNotationIsRecognisedByItsSuffix() {
        for file in ["v001.musicxml", "v012.MXL", "v003.xml", "v004.mid", "v005.midi"] {
            XCTAssertEqual(ScoreArtifact.kind(ofFile: file), .notation, file)
        }
    }

    func testAPdfIsAScan() {
        XCTAssertEqual(ScoreArtifact.kind(ofFile: "v001.pdf"), .scan)
        XCTAssertEqual(ScoreArtifact.kind(ofFile: "v001.PDF"), .scan)
    }

    /// Anything unrecognised is treated as a scan rather than as notation: the
    /// engine would refuse it anyway, and guessing "notation" would send it to
    /// Verovio and fail deep in a parser.
    func testTheUnknownIsTreatedAsAScan() {
        XCTAssertEqual(ScoreArtifact.kind(ofFile: "v001"), .scan)
        XCTAssertEqual(ScoreArtifact.kind(ofFile: "v001.png"), .scan)
    }

    func testOnlyNotationCanBeSelectedOrEdited() {
        XCTAssertTrue(ScoreArtifact.allowsSelection(.notation))
        XCTAssertTrue(ScoreArtifact.allowsEditing(.notation))
        XCTAssertFalse(ScoreArtifact.allowsSelection(.scan))
        XCTAssertFalse(ScoreArtifact.allowsEditing(.scan))
    }

    /// The reason to bring scans in before any OMR: markup works on day one.
    func testBothKindsTakePencilMarkup() {
        XCTAssertTrue(ScoreArtifact.allowsAnnotation(.notation))
        XCTAssertTrue(ScoreArtifact.allowsAnnotation(.scan))
    }

    func testTheRefusalSaysWhatToDoAboutIt() {
        let text = ScoreArtifact.whyNotEditable()
        XCTAssertTrue(text.contains("PDF") && text.contains("OMR"),
                      "a refusal that does not say the way forward is just a wall: \(text)")
    }
}
