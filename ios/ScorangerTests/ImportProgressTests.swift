import XCTest

/// Import Book showed nothing while it ran and nothing when it failed.
final class ImportProgressTests: XCTestCase {

    func testABookInFlightBelongsUnderBooks() {
        XCTAssertEqual(ImportTarget.book.segment, .books)
    }

    func testAScoreInFlightStillBelongsUnderPieces() {
        XCTAssertEqual(ImportTarget.arrangement.segment, .pieces)
    }

    /// The regression: a book's progress row must not be filed with the
    /// arrangements, or it appears in a list it will never join.
    func testNoTwoTargetsShareASegment() {
        XCTAssertNotEqual(ImportTarget.book.segment, ImportTarget.arrangement.segment)
    }

    func testAFailureNamesTheBookAndKeepsTheEnginesReason() {
        let message = BookImportStage.failure(name: "The Real Book",
                                              reason: "No module named 'pypdf'")
        XCTAssertTrue(message.contains("The Real Book"))
        XCTAssertTrue(message.contains("pypdf"),
                      "the only report that reaches anyone is the one on screen")
    }

    func testAFailureWithNothingToSayStillSaysItFailed() {
        let message = BookImportStage.failure(name: "The Real Book", reason: "   ")
        XCTAssertTrue(message.contains("The Real Book"))
        XCTAssertFalse(message.hasSuffix(": "))
    }

    func testTheStagesAreDistinctAndReadable() {
        XCTAssertNotEqual(BookImportStage.copying, BookImportStage.reading)
        for stage in [BookImportStage.copying, BookImportStage.reading] {
            XCTAssertFalse(stage.isEmpty)
            XCTAssertEqual(stage, stage.lowercased(),
                           "stages sit under a title in meta type")
        }
    }
}
