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
    func testTheSuffixRuleIsTheOneTheScoreViewUses() {
        XCTAssertEqual(ArtifactTag.holding(files: ["v001.png"]), .pdf)
        XCTAssertEqual(ArtifactTag.holding(files: ["v001.mid"]), .notation)
        XCTAssertEqual(ArtifactTag.holding(for: .notation), .notation)
        XCTAssertEqual(ArtifactTag.holding(for: .scan), .pdf)
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
}
