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
        // `.png` stood here as the unrecognised file until images became a
        // kind of their own. The claim is about the UNKNOWN, so it asks with
        // a suffix nothing knows.
        XCTAssertEqual(ScoreArtifact.kind(ofFile: "v001.tiff"), .scan)
    }

    /// A picture of a page is its own kind: the same behaviour as a PDF, and
    /// a different word for it, because a reader has to be able to tell a
    /// photograph from a PDF in the library.
    func testAPictureOfAPageIsAnImage() {
        for name in ["v001.jpg", "v001.jpeg", "v001.png", "v001.PNG",
                     "v001.heic", "v001.HEIC"] {
            XCTAssertEqual(ScoreArtifact.kind(ofFile: name), .image, name)
        }
    }

    /// And it can no more be selected or edited than a PDF can.
    func testAnImageCanBeNeitherSelectedNorEdited() {
        XCTAssertFalse(ScoreArtifact.allowsSelection(.image))
        XCTAssertFalse(ScoreArtifact.allowsEditing(.image))
        XCTAssertFalse(ScoreArtifact.Kind.image.isNotation)
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
