import XCTest

/// PDF vs MusicXML, everywhere the reader looks (0.6.3 features 3-5).
///
/// The complaint this answers: a library of imported PDFs and OMR'd notation
/// looked identical row by row, so "can I edit this one" could only be
/// answered by opening it and watching the pencil select nothing.
final class ArtifactTagTests: XCTestCase {

    private func version(_ id: String, _ file: String) -> VersionDoc {
        VersionDoc(id: id, file: file, op: "import", time: nil, parts: nil, turn: nil)
    }

    private func score(_ slug: String, files: [String]) -> ScoreDoc {
        ScoreDoc(slug: slug, name: slug, title: nil, composer: nil,
                 latest: files.indices.last.map { "v\($0)" },
                 versions: files.enumerated().map { version("v\($0.offset)", $0.element) },
                 sources: nil, piece: nil)
    }

    // MARK: - What a set of files holds

    func testNotationOnlyIsMusicXML() {
        XCTAssertEqual(ArtifactTag.holding(files: ["v001.musicxml", "v002.mxl"]),
                       .notation)
    }

    func testPdfOnlyIsAPdf() {
        XCTAssertEqual(ArtifactTag.holding(files: ["v001.pdf"]), .pdf)
    }

    /// The case the tag exists for: a scan that has been read. Both artifacts
    /// are still there, and the reader wants to know that -- the PDF is what
    /// they compare the OMR against.
    func testAScanThatHasBeenOMRdHoldsBoth() {
        XCTAssertEqual(ArtifactTag.holding(files: ["v001.pdf", "v002.musicxml"]),
                       .both)
    }

    /// An arrangement with no versions says nothing rather than claiming to be
    /// a PDF, which is what "unknown suffix means scan" would otherwise make it.
    func testNothingToShowMeansNoTag() {
        XCTAssertNil(ArtifactTag.holding(files: []))
        XCTAssertNil(ArtifactTag.holding(files: [""]))
    }

    /// The suffix rule is `ScoreArtifact`'s, not a second one invented here --
    /// so an unrecognised file is a scan in both places.
    ///
    /// This used `v001.png` as the unrecognised file, which it was until
    /// images became a kind of their own. The claim was always about the rule
    /// being SHARED rather than about PNG in particular, so it now asks with a
    /// suffix nothing knows.
    func testTheSuffixRuleIsTheOneTheScoreViewUses() {
        XCTAssertEqual(ArtifactTag.holding(files: ["v001.tiff"]), .pdf)
        XCTAssertEqual(ArtifactTag.holding(files: ["v001.png"]), .image)
        XCTAssertEqual(ArtifactTag.holding(files: ["v001.mid"]), .notation)
        XCTAssertEqual(ArtifactTag.holding(for: .notation), .notation)
        XCTAssertEqual(ArtifactTag.holding(for: .scan), .pdf)
        XCTAssertEqual(ArtifactTag.holding(for: .image), .image)
    }

    // MARK: - Arrangements and pieces

    func testAnArrangementIsJudgedOnItsWholeHistory() {
        let omrd = score("tune", files: ["v001.pdf", "v002.musicxml", "v003.musicxml"])
        XCTAssertEqual(ArtifactTag.holding(of: omrd), .both,
                       "the PDF is still in the library and still openable")
    }

    /// The piece-level tag (feature 4): what this tune holds across every
    /// arrangement filed under it.
    func testAPieceHoldsWhatItsArrangementsHold() {
        let pdfOnly = score("scan", files: ["v001.pdf"])
        let engraved = score("engraved", files: ["v001.musicxml"])
        XCTAssertEqual(ArtifactTag.holding(ofScores: [pdfOnly]), .pdf)
        XCTAssertEqual(ArtifactTag.holding(ofScores: [engraved]), .notation)
        XCTAssertEqual(ArtifactTag.holding(ofScores: [pdfOnly, engraved]), .both,
                       "one scanned arrangement and one engraved one is a piece "
                       + "holding both")
        XCTAssertNil(ArtifactTag.holding(ofScores: []))
    }

    // MARK: - What it says

    func testTheTagSaysPdfOrMusicXMLInThoseWords() {
        XCTAssertEqual(ArtifactTag.label(ArtifactHolding.pdf), "PDF")
        XCTAssertEqual(ArtifactTag.label(ArtifactHolding.notation), "MUSICXML")
        XCTAssertEqual(ArtifactTag.label(ArtifactHolding.both), "PDF + MUSICXML")
    }

    func testTheScoreViewsMarkerNamesTheVersionOnScreen() {
        XCTAssertEqual(ArtifactTag.label(ScoreArtifact.Kind.notation), "MUSICXML")
        XCTAssertEqual(ArtifactTag.label(ScoreArtifact.Kind.scan), "PDF")
        XCTAssertEqual(ArtifactTag.markerDetail(.notation), "editable")
        XCTAssertEqual(ArtifactTag.markerDetail(.scan), "not editable")
    }

    /// `both` is two chips, not one compound one: the reader is answering two
    /// questions and two answers read faster than a phrase joining them.
    func testBothIsTwoChipsSoNeitherFactIsBuried() {
        XCTAssertEqual(ArtifactTag.chips(for: .pdf).map(\.text), ["PDF"])
        XCTAssertEqual(ArtifactTag.chips(for: .notation).map(\.text), ["MUSICXML"])
        XCTAssertEqual(ArtifactTag.chips(for: .both).map(\.text),
                       ["PDF", "MUSICXML"])
    }

    /// Notation takes the accent chip: clay is this app's "live", and notation
    /// is the half of the pair that can actually be worked on.
    func testNotationReadsAsTheLiveOne() {
        XCTAssertEqual(ArtifactTag.chips(for: .notation).first?.kind, .count)
        XCTAssertEqual(ArtifactTag.chips(for: .pdf).first?.kind, .plain)
    }

    func testAnEmptyArrangementGetsNoChips() {
        XCTAssertTrue(ArtifactTag.chips(files: []).isEmpty)
    }

    /// The consequence a reader cares about, derivable from the tag alone.
    func testTheTagAnswersWhetherAnythingHereCanBePlayedOrEdited() {
        XCTAssertFalse(ArtifactHolding.pdf.hasNotation)
        XCTAssertTrue(ArtifactHolding.notation.hasNotation)
        XCTAssertTrue(ArtifactHolding.both.hasNotation)
    }
}

/// And the tag actually reaches every list the reader looks at (#3, #4).
final class LibraryFormatChipTests: XCTestCase {

    private func version(_ id: String, _ file: String) -> VersionDoc {
        VersionDoc(id: id, file: file, op: "import", time: "2026-09-01T10:00:00",
                   parts: nil, turn: nil)
    }

    private func manifest() -> Manifest {
        let scanned = ScoreDoc(slug: "scan-1", name: "Scanned", title: "Scanned",
                               composer: nil, latest: "v001",
                               versions: [version("v001", "v001.pdf")],
                               sources: nil, piece: "tune")
        let engraved = ScoreDoc(slug: "eng-1", name: "Engraved", title: "Engraved",
                                composer: nil, latest: "v001",
                                versions: [version("v001", "v001.musicxml")],
                                sources: nil, piece: "other")
        let loose = ScoreDoc(slug: "loose", name: "Loose", title: "Loose",
                             composer: nil, latest: "v001",
                             versions: [version("v001", "v001.pdf")],
                             sources: nil, piece: nil)
        return Manifest(generated: nil, scores: [scanned, engraved, loose],
                        pieces: [PieceDoc(slug: "tune", name: "Tune",
                                          arrangements: ["scan-1"], composer: nil,
                                          arranger: nil, tags: nil),
                                 PieceDoc(slug: "other", name: "Other",
                                          arrangements: ["eng-1"], composer: nil,
                                          arranger: nil, tags: nil)],
                        setlists: [SetlistDoc(slug: "gig", name: "Gig",
                                              arrangements: ["scan-1", "eng-1"])],
                        books: nil)
    }

    /// The piece row leads with what it holds: it is the fact that decides
    /// whether anything else on the row can be worked on.
    func testAPieceRowLeadsWithWhatItHolds() {
        let rows = LibraryModel.pieceRows(manifest: manifest())
        XCTAssertEqual(rows.first { $0.id == "tune" }?.chips.first?.text, "PDF")
        XCTAssertEqual(rows.first { $0.id == "other" }?.chips.first?.text, "MUSICXML")
    }

    func testAnUnfiledArrangementIsTaggedToo() {
        let rows = LibraryModel.unfiledRows(manifest: manifest())
        XCTAssertEqual(rows.first?.chips.first?.text, "PDF")
        XCTAssertTrue(rows.first?.chips.contains { $0.text == "UNFILED" } ?? false,
                      "and it keeps the chip it already had")
    }

    /// A set list of one scan and one engraving holds both, which is what a
    /// player needs to know before the gig.
    func testASetListSaysWhatItsRunningOrderHolds() {
        let rows = LibraryModel.setlistRows(manifest: manifest())
        XCTAssertEqual(rows.first?.chips.map(\.text), ["PDF", "MUSICXML", "ORDERED"])
    }

    /// Typing "pdf" now finds the scans, at no cost -- search already reads
    /// the chips.
    func testTypingTheFormatFindsIt() {
        let rows = LibraryModel.pieceRows(manifest: manifest())
        XCTAssertEqual(LibraryModel.searched(rows, query: "pdf").map(\.id), ["tune"])
        XCTAssertEqual(LibraryModel.searched(rows, query: "musicxml").map(\.id), ["other"])
    }

    // MARK: - Images (0.6.x)

    /// An image is a scan, and it says so rather than borrowing "PDF".
    ///
    /// Ali brings scores in as JPEGs and PNGs. They behave exactly like a PDF
    /// -- readable, annotatable, not editable until OMR -- but a reader
    /// looking at the library has to be able to tell a photograph from a PDF,
    /// because those are the two things they actually brought in.
    func testAnImageIsItsOwnTag() {
        XCTAssertEqual(ArtifactTag.label(ArtifactHolding.image), "IMAGE")
        XCTAssertEqual(ArtifactTag.label(ScoreArtifact.Kind.image), "IMAGE")
        XCTAssertEqual(ArtifactTag.markerDetail(.image), "not editable")
    }

    /// Every suffix, from the one place that decides.
    func testTheKindComesFromTheSuffix() {
        for name in ["v001.jpg", "v001.jpeg", "v001.png", "v001.PNG",
                     "v001.heic"] {
            XCTAssertEqual(ScoreArtifact.kind(ofFile: name), .image, name)
        }
        XCTAssertEqual(ScoreArtifact.kind(ofFile: "v001.pdf"), .scan)
        XCTAssertEqual(ScoreArtifact.kind(ofFile: "v001.musicxml"), .notation)
        XCTAssertEqual(ScoreArtifact.kind(ofFile: "v001.mxl"), .notation)
    }

    /// An image that has been OMR'd holds both, the same way a PDF does -- and
    /// says IMAGE rather than PDF, because the thing still on disk to compare
    /// the transcription against is the photograph.
    func testAnOMRdImageHoldsBoth() {
        let holding = ArtifactTag.holding(files: ["v001.png", "v002.musicxml"])
        XCTAssertEqual(holding, [.image, .notation])
        XCTAssertEqual(ArtifactTag.label(holding!), "IMAGE + MUSICXML")
        XCTAssertEqual(ArtifactTag.chips(for: holding!).map(\.text),
                       ["IMAGE", "MUSICXML"])
    }

    /// A PDF and an image in one arrangement. Unusual, and it must still read
    /// as what it is rather than as whichever was checked first.
    func testAPdfAndAnImageAreBothNamed() {
        let holding = ArtifactTag.holding(files: ["v001.pdf", "v002.jpg"])
        XCTAssertEqual(ArtifactTag.label(holding!), "PDF + IMAGE")
        let all = ArtifactTag.holding(files: ["v001.pdf", "v002.jpg",
                                              "v003.musicxml"])
        XCTAssertEqual(ArtifactTag.label(all!), "PDF + IMAGE + MUSICXML")
    }

    /// The question the library actually asks: can anything here be worked on.
    /// An image answers no, exactly as a PDF does.
    func testAnImageHasNoNotation() {
        XCTAssertFalse(ArtifactHolding.image.hasNotation)
        XCTAssertFalse(ArtifactHolding.pdf.hasNotation)
        XCTAssertTrue(ArtifactTag.holding(files: ["v001.png", "v002.mxl"])!
                        .hasNotation)
    }

    /// And the one the row asks to draw its "scan" treatment. It was
    /// `holding == .pdf`, which an image-only arrangement fails while being
    /// exactly as much of a scan.
    func testAnImageOnlyArrangementIsAScan() {
        XCTAssertTrue(ArtifactTag.holding(files: ["v001.png"])!.isScanOnly)
        XCTAssertTrue(ArtifactTag.holding(files: ["v001.pdf"])!.isScanOnly)
        XCTAssertTrue(ArtifactTag.holding(files: ["v001.pdf", "v002.png"])!
                        .isScanOnly)
        XCTAssertFalse(ArtifactTag.holding(files: ["v001.musicxml"])!.isScanOnly)
        XCTAssertFalse(ArtifactTag.holding(files: ["v001.png", "v002.mxl"])!
                        .isScanOnly)
    }

    /// The existing tags are untouched by all of it.
    func testPdfAndNotationStillReadAsTheyDid() {
        XCTAssertEqual(ArtifactTag.label(ArtifactHolding.pdf), "PDF")
        XCTAssertEqual(ArtifactTag.label(ArtifactHolding.notation), "MUSICXML")
        XCTAssertEqual(ArtifactTag.label(ArtifactHolding.both), "PDF + MUSICXML")
        XCTAssertEqual(ArtifactTag.chips(for: .both).map(\.text),
                       ["PDF", "MUSICXML"])
    }
}
