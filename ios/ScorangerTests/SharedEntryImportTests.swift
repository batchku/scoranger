import XCTest

/// The two decisions between a downloaded shared entry and an arrangement in
/// the library, against the shapes the bridge really returns. The literal
/// results below are what `bridge.handle` produced on the actual files from a
/// shared set list on 2026-09-10 -- not invented.
final class SharedEntryImportTests: XCTestCase {

    // MARK: - which op

    func testNotationGoesToImport() {
        XCTAssertEqual(SharedEntryImport.op(for: URL(fileURLWithPath: "/t/x-abc.musicxml")), "import")
        XCTAssertEqual(SharedEntryImport.op(for: URL(fileURLWithPath: "/t/x-abc.mxl")), "import")
    }

    func testAScanGoesToImportPdfBecauseImportCannotParseOne() {
        // `import` on a PDF: "ConverterFileException: cannot find format from
        // file extensions". Measured, not assumed.
        XCTAssertEqual(SharedEntryImport.op(for: URL(fileURLWithPath: "/t/x-abc.pdf")), "import-pdf")
        XCTAssertEqual(SharedEntryImport.op(for: URL(fileURLWithPath: "/t/X-ABC.PDF")), "import-pdf")
    }

    // MARK: - where the slug is

    func testTheSlugIsTheScoreStringTheBridgeReturns() {
        // Verbatim from bridge.handle on Swallowtail Jig's shared copy.
        let result: [String: Any] = ["score": "swallowtail-jig",
                                     "version": "01M26H60RJ52JT7JKKN91JHPSD",
                                     "piece": NSNull()]
        XCTAssertEqual(SharedEntryImport.slug(in: result), "swallowtail-jig")
    }

    func testImportPdfReturnsTheSameShape() {
        let result: [String: Any] = ["score": "rocky-road-to-dublin",
                                     "version": "01M26H6ZZZ", "piece": NSNull(),
                                     "kind": "pdf"]
        XCTAssertEqual(SharedEntryImport.slug(in: result), "rocky-road-to-dublin")
    }

    func testTheOldReadingWouldHaveFoundNothing() {
        // What the caller used to do, kept as the record of the bug: treat
        // `score` as a dictionary with a `slug` inside it. On the real shape
        // that is nil, and nil was reported as "could not be prepared for
        // sharing" six times over.
        let result: [String: Any] = ["score": "swallowtail-jig", "version": "v"]
        let oldReading = (result["score"] as? [String: Any])?["slug"] as? String
            ?? result["slug"] as? String
        XCTAssertNil(oldReading)
        XCTAssertNotNil(SharedEntryImport.slug(in: result))
    }

    func testAMissingOrEmptySlugIsNil() {
        XCTAssertNil(SharedEntryImport.slug(in: [:]))
        XCTAssertNil(SharedEntryImport.slug(in: ["score": ""]))
        XCTAssertNil(SharedEntryImport.slug(in: ["score": 42]))
    }
}
