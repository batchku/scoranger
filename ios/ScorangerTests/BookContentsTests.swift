import XCTest

/// The review of a book's proposed tunes, and reading its contents.
///
/// The engine proposes (booksplit.propose, held by check_book_split.py); this
/// is what the reader does to the list before it is kept, and how the reader
/// moves through a kept one. The rules that matter:
///
///   - the list is refused for exactly what the engine would refuse, so the
///     Keep button is never live over a plan that fails on the way in;
///   - every edit keeps the list in PAGE ORDER, or "next tune" would mean
///     something other than the next tune in the book;
///   - an entry keeps its id through a rename and a re-range, so a reader on
///     tune 40 is still on tune 40 after the title is corrected.
final class BookContentsTests: XCTestCase {

    private func entry(_ id: String, _ title: String, _ from: Int, _ to: Int) -> BookEntry {
        BookEntry(id: id, title: title, from: from, to: to, evidence: "heading")
    }

    private var tunebook: BookContents {
        BookContents(entries: [entry("a", "The Abbey", 6, 6),
                               entry("b", "The Arra Mountains", 7, 8),
                               entry("c", "The Kesh (cont.)", 9, 9),
                               entry("d", "Drowsy Maggie", 10, 12)],
                     pages: 134)
    }

    // MARK: - what can be kept

    func testAProposalAsFoundCanBeKept() {
        XCTAssertNil(tunebook.problem)
    }

    func testAnUntitledTuneIsRefusedByNumber() {
        var list = tunebook
        list.rename("b", to: "   ")
        XCTAssertEqual(list.problem, "Tune 2 has no title.")
    }

    func testAnEmptyListIsRefused() {
        var list = tunebook
        for id in ["a", "b", "c", "d"] { list.remove(id) }
        XCTAssertNotNil(list.problem)
    }

    // MARK: - the corrections

    func testAFalseStartFoldsIntoTheTuneBeforeIt() {
        var list = tunebook
        list.mergeWithPrevious("c")
        XCTAssertEqual(list.entries.map(\.id), ["a", "b", "d"])
        XCTAssertEqual(list.entries[1].to, 9, "the tune before now runs to the folded page")
    }

    func testTheFirstTuneHasNothingToFoldInto() {
        var list = tunebook
        list.mergeWithPrevious("a")
        XCTAssertEqual(list, tunebook)
    }

    func testTwoTunesRunTogetherArePartedAtAPage() {
        var list = tunebook
        list.split("d", at: 11, title: "Untitled")
        XCTAssertEqual(list.entries.map(\.title),
                       ["The Abbey", "The Arra Mountains", "The Kesh (cont.)",
                        "Drowsy Maggie", "Untitled"])
        XCTAssertEqual(list.entries[3].to, 10)
        XCTAssertEqual(list.entries[4].from, 11)
        XCTAssertEqual(list.entries[4].to, 12)
        XCTAssertNil(list.entries[4].evidence, "the reader made it, not the detector")
        XCTAssertNotEqual(list.entries[4].id, "d")
    }

    func testAOnePageTuneCannotBeSplit() {
        var list = tunebook
        list.split("a", at: 6, title: "Untitled")
        XCTAssertEqual(list, tunebook)
    }

    func testARangeIsClampedIntoTheBookAndNeverInverted() {
        var list = tunebook
        list.setRange("a", from: 0, to: 500)
        XCTAssertEqual(list.entries.first { $0.id == "a" }?.from, 1)
        XCTAssertEqual(list.entries.first { $0.id == "a" }?.to, 134)
        list.setRange("b", from: 9, to: 3)
        let b = list.entries.first { $0.id == "b" }
        XCTAssertEqual(b?.from, 9)
        XCTAssertEqual(b?.to, 9)
    }

    func testMovingATunesStartKeepsTheListInPageOrder() {
        var list = tunebook
        list.setRange("d", from: 3, to: 4)
        XCTAssertEqual(list.entries.map(\.id), ["d", "a", "b", "c"])
    }

    func testAnAddedTuneLandsInPageOrder() {
        var list = tunebook
        list.add(title: "Cooley's", from: 8, to: 8)
        XCTAssertEqual(list.entries.map(\.title),
                       ["The Abbey", "The Arra Mountains", "Cooley's",
                        "The Kesh (cont.)", "Drowsy Maggie"])
    }

    func testARenameKeepsTheId() {
        var list = tunebook
        list.rename("b", to: "The Arra Mountains (slip jig)")
        XCTAssertEqual(list.entries[1].id, "b")
    }

    // MARK: - reading a kept one

    func testNextAndPreviousStepThroughTheBookInOrder() {
        let entries = tunebook.entries
        XCTAssertEqual(BookReading.neighbour(of: "b", in: entries, by: 1)?.id, "c")
        XCTAssertEqual(BookReading.neighbour(of: "b", in: entries, by: -1)?.id, "a")
        XCTAssertNil(BookReading.neighbour(of: "a", in: entries, by: -1))
        XCTAssertNil(BookReading.neighbour(of: "d", in: entries, by: 1))
        XCTAssertEqual(BookReading.label(of: "c", in: entries), "Tune 3 of 4")
    }

    func testAnEntryNoLongerInTheListHasNoPlace() {
        XCTAssertNil(BookReading.label(of: "gone", in: tunebook.entries))
        XCTAssertNil(BookReading.neighbour(of: "gone", in: tunebook.entries, by: 1))
    }

    func testPagesAreSaidTheWayAPageIsCited() {
        XCTAssertEqual(BookReading.pages(entry("x", "X", 6, 6)), "p. 6")
        XCTAssertEqual(BookReading.pages(entry("x", "X", 10, 12)), "pp. 10–12")
    }

    // MARK: - what a shared file can become

    func testOnlyOnePDFCanBeABook() {
        let pdf = URL(fileURLWithPath: "/tmp/Tunebook.pdf")
        let upper = URL(fileURLWithPath: "/tmp/TUNEBOOK.PDF")
        let xml = URL(fileURLWithPath: "/tmp/Reel.musicxml")
        XCTAssertTrue(ImportChoice.bookAvailable(for: [pdf]))
        XCTAssertTrue(ImportChoice.bookAvailable(for: [upper]))
        XCTAssertFalse(ImportChoice.bookAvailable(for: [xml]))
        XCTAssertFalse(ImportChoice.bookAvailable(for: [pdf, pdf]),
                       "two files shared at once are two things, not one book")
    }

    // MARK: - the engine's JSON

    /// What book-detect prints, decoded the way LocalEngine decodes it. A key
    /// renamed on either side would otherwise surface as "the tunes could not
    /// be found" on a book whose tunes were found.
    func testTheEnginesProposalDecodes() throws {
        let json = """
        {"book": "comhaltas", "entries": [
            {"id": "01M3", "title": "The Abbey", "from": 6, "to": 6, "evidence": "bookmark"}],
         "unassigned": [1, 134], "matter": [2, 3, 4, 5], "needs_ocr": [],
         "bookmarks": 124, "pages": 134}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let proposal = try decoder.decode(BookProposal.self, from: Data(json.utf8))
        XCTAssertEqual(proposal.entries.first?.title, "The Abbey")
        XCTAssertEqual(proposal.needsOcr, [])
        XCTAssertEqual(proposal.matter, [2, 3, 4, 5])

        let report = """
        {"book": "comhaltas", "arrangements": [
            {"score": "the-abbey", "version": "01M4", "title": "The Abbey", "pages": "6-6",
             "piece": "The Abbey", "joined_existing_piece": false}],
         "pieces_joined": 0, "pieces_created": 1}
        """
        let made = try decoder.decode(BookSplitReport.self, from: Data(report.utf8))
        XCTAssertEqual(made.piecesCreated, 1)
        XCTAssertFalse(made.arrangements[0].joinedExistingPiece)
    }

    /// A manifest written before 0.14.0 has no `contents` on its books.
    func testABookWithoutContentsStillDecodes() throws {
        let json = #"{"slug": "real-book", "name": "The Real Book", "pages": 400}"#
        let book = try JSONDecoder().decode(BookDoc.self, from: Data(json.utf8))
        XCTAssertNil(book.contents)
    }
}
