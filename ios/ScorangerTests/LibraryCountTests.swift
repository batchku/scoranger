import XCTest

/// L11: the library's count was a bare number -- "My library 1", and "My
/// library 0" on the screen a new user meets first.
final class LibraryCountTests: XCTestCase {

    private func row(_ id: String, arrangements: Int = 1) -> LibraryRow {
        LibraryRow(id: id, title: id, subtitle: "", chips: [], meta: "",
                   sortName: id, composer: "", changed: "",
                   arrangementCount: arrangements)
    }

    func testItNamesWhatItIsCounting() {
        let phrase = LibraryModel.countPhrase(segment: .pieces,
                                              rows: [row("a", arrangements: 1),
                                                     row("b", arrangements: 2)])
        XCTAssertEqual(phrase, "2 pieces · 3 arrangements")
    }

    func testOneOfSomethingIsSingular() {
        XCTAssertEqual(LibraryModel.countPhrase(segment: .pieces,
                                                rows: [row("a", arrangements: 1)]),
                       "1 piece · 1 arrangement")
    }

    /// Zero is a sentence, not a number: this is the first screen a new user
    /// sees, and "0" tells them nothing about what to do.
    func testAnEmptyLibrarySaysSoInWords() {
        XCTAssertEqual(LibraryModel.countPhrase(segment: .pieces, rows: []),
                       "No pieces yet")
        XCTAssertEqual(LibraryModel.countPhrase(segment: .setlists, rows: []),
                       "No set lists yet")
        for segment in LibrarySegment.allCases {
            XCTAssertFalse(LibraryModel.countPhrase(segment: segment, rows: [])
                .contains("0"), "an empty library still counts in digits")
        }
    }

    func testSetlistsAreCountedAsSetLists() {
        XCTAssertEqual(LibraryModel.countPhrase(segment: .setlists,
                                                rows: [row("a"), row("b")]),
                       "2 set lists")
        XCTAssertEqual(LibraryModel.countPhrase(segment: .setlists, rows: [row("a")]),
                       "1 set list")
    }

    /// A piece with no arrangements still counts as holding one thing rather
    /// than as holding none -- and orphans are swept anyway (0.4.4).
    func testAPieceAlwaysCountsForAtLeastOneArrangement() {
        XCTAssertEqual(LibraryModel.countPhrase(segment: .pieces,
                                                rows: [row("a", arrangements: 0)]),
                       "1 piece · 1 arrangement")
    }

    func testTheNounIsNeverDropped() {
        for count in [0, 1, 2, 17] {
            XCTAssertTrue(LibraryModel.plural(count, "piece").contains("piece"))
        }
        XCTAssertEqual(LibraryModel.plural(0, "piece"), "0 pieces")
    }
}
