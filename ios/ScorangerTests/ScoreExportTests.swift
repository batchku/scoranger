import Foundation
import XCTest

/// What a score exports as, and what the file is called.
///
/// The naming is not cosmetic: an exported file leaves the app and lands in
/// Files, Mail or another program, where "v003.musicxml" tells nobody what it
/// is. It has to carry the arrangement's own title.
final class ScoreExportTests: XCTestCase {

    // MARK: - Which formats exist, and who renders them

    func testThreeFormatsAreOffered() {
        XCTAssertEqual(ScoreExport.Format.allCases.count, 3)
        XCTAssertEqual(Set(ScoreExport.Format.allCases.map(\.label)),
                       ["MusicXML", "MIDI", "PDF"])
    }

    /// The split that matters: the bridge owns two formats, the Swift renderer
    /// owns PDF. Engraving carries chord adjustments and whistle fingerings
    /// that only the Swift pass applies, so a PDF from the bridge would not
    /// match the page on screen.
    func testPDFIsRenderedOnDeviceAndTheOthersAreNot() {
        XCTAssertTrue(ScoreExport.Format.pdf.isRenderedOnDevice)
        XCTAssertFalse(ScoreExport.Format.musicxml.isRenderedOnDevice)
        XCTAssertFalse(ScoreExport.Format.midi.isRenderedOnDevice)
    }

    func testEachFormatHasItsOwnExtension() {
        XCTAssertEqual(ScoreExport.Format.musicxml.fileExtension, "musicxml")
        XCTAssertEqual(ScoreExport.Format.midi.fileExtension, "mid")
        XCTAssertEqual(ScoreExport.Format.pdf.fileExtension, "pdf")
    }

    // MARK: - The filename

    func testTheFilenameIsTheArrangementTitle() {
        XCTAssertEqual(
            ScoreExport.filename(title: "Sous le ciel de Paris", version: nil, format: .musicxml),
            "Sous le ciel de Paris.musicxml")
    }

    /// A pinned version is part of what the file IS, so it is named. The latest
    /// version is not, because that is just "the arrangement".
    func testAPinnedVersionIsNamedAndTheLatestIsNot() {
        XCTAssertEqual(
            ScoreExport.filename(title: "Quartet", version: "v003", format: .pdf),
            "Quartet v003.pdf")
        XCTAssertEqual(
            ScoreExport.filename(title: "Quartet", version: nil, format: .pdf),
            "Quartet.pdf")
    }

    /// Slashes and colons end a save in Files with an error the user cannot
    /// act on, and a title is free text the user typed.
    func testCharactersAFilesystemRefusesAreReplaced() {
        let name = ScoreExport.filename(title: "AC/DC: Live", version: nil, format: .midi)
        XCTAssertFalse(name.contains("/"), name)
        XCTAssertFalse(name.contains(":"), name)
        XCTAssertTrue(name.hasSuffix(".mid"), name)
    }

    func testAnEmptyTitleStillProducesAUsableName() {
        let name = ScoreExport.filename(title: "   ", version: nil, format: .musicxml)
        XCTAssertEqual(name, "score.musicxml")
    }

    func testAVeryLongTitleIsTrimmedButKeepsItsExtension() {
        let long = String(repeating: "a", count: 400)
        let name = ScoreExport.filename(title: long, version: nil, format: .midi)
        XCTAssertLessThanOrEqual(name.count, 120, "\(name.count) is beyond what a filesystem takes")
        XCTAssertTrue(name.hasSuffix(".mid"), name)
    }

    func testLeadingAndTrailingSpaceIsDropped() {
        XCTAssertEqual(
            ScoreExport.filename(title: "  Morrison's Jig  ", version: nil, format: .musicxml),
            "Morrison's Jig.musicxml")
    }

    // MARK: - The seam with the UI test

    /// `ExportFromTheApp` drives the rows by identifier ("export-musicxml")
    /// and carries the extensions in a list of its own, because the UI bundle
    /// has no host app and cannot read this enum. This is the seam between the
    /// two: a format added, renamed or given another extension fails HERE,
    /// naming what that test has to learn, rather than failing there as a row
    /// that is mysteriously not on screen.
    func testTheRowsTheUITestDrivesAreTheFormatsThisEnumHas() {
        XCTAssertEqual(ScoreExport.Format.allCases.map { "export-\($0.rawValue)" },
                       ["export-musicxml", "export-midi", "export-pdf"])
        XCTAssertEqual(ScoreExport.Format.allCases.map(\.fileExtension),
                       ["musicxml", "mid", "pdf"])
    }

    /// A dot in the title must not read as the extension.
    func testADotInTheTitleSurvivesWithoutEatingTheExtension() {
        let name = ScoreExport.filename(title: "No. 4 in G", version: nil, format: .pdf)
        XCTAssertEqual(name, "No. 4 in G.pdf")
    }
}
