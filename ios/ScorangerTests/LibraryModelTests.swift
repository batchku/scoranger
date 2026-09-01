import XCTest

/// The library's own logic: what a row says, what order rows come in, which
/// letter they file under, and what a search finds.
///
/// All of it is derived from the manifest the engine already publishes -- no
/// tag store, no new fields, no engine change (NAVIGATION_SYSTEM.md §7) -- and
/// all of it decides what a person sees, so all of it is stated here rather
/// than only being visible on a screen.
final class LibraryModelTests: XCTestCase {

    private func version(_ id: String, op: String = "transpose",
                         time: String = "2026-08-25T14:02:00") -> VersionDoc {
        VersionDoc(id: id, file: "\(id).musicxml", op: op, time: time, parts: nil, turn: nil)
    }

    private func score(_ slug: String, name: String, composer: String? = nil,
                       piece: String? = nil, versions: [VersionDoc]? = nil,
                       sources: [SourceDoc]? = nil) -> ScoreDoc {
        ScoreDoc(slug: slug, name: name, title: name, composer: composer,
                 latest: (versions ?? [version("v001")]).last?.id,
                 versions: versions ?? [version("v001")], sources: sources, piece: piece)
    }

    private var manifest: Manifest {
        Manifest(generated: nil,
                 scores: [
                    score("cavatina-duo", name: "Accordion duo", composer: "Stanley Myers",
                          piece: "cavatina", versions: [version("v001"), version("v014")]),
                    score("cavatina-solo", name: "Solo", composer: "Stanley Myers",
                          piece: "cavatina"),
                    score("libertango-1", name: "Libertango", composer: "Piazzolla",
                          piece: "libertango"),
                    score("blue-bossa", name: "Blue Bossa", piece: "blue-bossa",
                          versions: [version("v001", op: "import")]),
                    score("loose-sketch", name: "Loose sketch", composer: "nobody"),
                 ],
                 pieces: [
                    PieceDoc(slug: "cavatina", name: "Cavatina",
                             arrangements: ["cavatina-duo", "cavatina-solo"]),
                    PieceDoc(slug: "libertango", name: "Libertango",
                             arrangements: ["libertango-1"]),
                    PieceDoc(slug: "blue-bossa", name: "Blue Bossa",
                             arrangements: ["blue-bossa"]),
                 ],
                 setlists: [
                    SetlistDoc(slug: "friday", name: "Friday at Vinny's",
                               arrangements: ["cavatina-duo", "libertango-1"]),
                 ])
    }

    // MARK: - What a piece row says

    func testAPieceRowCountsItsArrangements() {
        let rows = LibraryModel.pieceRows(manifest: manifest)
        let cavatina = rows.first { $0.title == "Cavatina" }
        XCTAssertEqual(cavatina?.subtitle, "Stanley Myers · 2 arrangements")
        // and only once: the count is in the subtitle, in words. A chip
        // saying "2 ARR" beside it was the same fact twice (0.4.1 §5).
        XCTAssertFalse(cavatina?.chips.contains { $0.text.hasSuffix("ARR") } ?? true,
                       "the count chip should be gone; the subtitle already says it")
    }

    func testASingleArrangementIsNotPluralised() {
        let rows = LibraryModel.pieceRows(manifest: manifest)
        XCTAssertEqual(rows.first { $0.title == "Libertango" }?.subtitle,
                       "Piazzolla · 1 arrangement")
    }

    /// Reversed in 0.5.4. The row used to read "unknown · 1 arrangement", and
    /// after a folder of PDFs is imported -- which carries no metadata at all
    /// -- EVERY row in the library said it. A word where a fact should be, on
    /// forty rows at once, is worse than saying nothing.
    func testAPieceWithNoComposerSaysNothingWhereTheComposerWouldGo() {
        let rows = LibraryModel.pieceRows(manifest: manifest)
        let subtitle = rows.first { $0.title == "Blue Bossa" }?.subtitle

        XCTAssertEqual(subtitle, "1 arrangement")
        XCTAssertFalse(subtitle?.contains("unknown") ?? true)
        XCTAssertFalse(subtitle?.hasPrefix(" · ") ?? true, "a stranded separator")
    }

    /// Sorting by composer is for finding a composer's pieces. Empty strings
    /// sort first by default, which would bury every named one under the
    /// un-credited ones.
    func testSortingByComposerPutsTheUncreditedLast() {
        let rows = LibraryModel.sorted(LibraryModel.pieceRows(manifest: manifest),
                                       by: .composer)
        let named = rows.prefix { !$0.composer.isEmpty }

        XCTAssertFalse(named.isEmpty, "no credited pieces in the fixture")
        XCTAssertTrue(rows.dropFirst(named.count).allSatisfy { $0.composer.isEmpty },
                      "a credited piece sorted below an un-credited one")
    }

    /// A scan that has never been edited. One version, and that version is the
    /// import -- which is exactly what a fresh scan looks like.
    func testAFreshScanIsMarkedAsAnOMRDraft() {
        let rows = LibraryModel.pieceRows(manifest: manifest)
        let bossa = rows.first { $0.title == "Blue Bossa" }
        XCTAssertTrue(bossa?.chips.contains { $0.text == "OMR DRAFT" } ?? false)
    }

    func testAnEditedScoreIsNoLongerADraft() {
        let rows = LibraryModel.pieceRows(manifest: manifest)
        let cavatina = rows.first { $0.title == "Cavatina" }
        XCTAssertFalse(cavatina?.chips.contains { $0.text == "OMR DRAFT" } ?? true)
    }

    // MARK: - Unfiled arrangements

    /// `#N` is only meaningful inside a piece (§2), so an unfiled arrangement
    /// has no number -- and the row must not reserve space for one.
    func testUnfiledArrangementsAreListedAndMarked() {
        let rows = LibraryModel.unfiledRows(manifest: manifest)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.title, "Loose sketch")
        XCTAssertTrue(rows.first?.chips.contains { $0.text == "UNFILED" } ?? false)
    }

    func testAFiledArrangementIsNotListedAsUnfiled() {
        let rows = LibraryModel.unfiledRows(manifest: manifest)
        XCTAssertFalse(rows.contains { $0.title == "Accordion duo" })
    }

    // MARK: - Setlists name their running order

    /// Our setlists hold ARRANGEMENTS, not pieces, so the subtitle has to say
    /// which arrangement of which piece -- the way chat names them.
    func testASetlistSubtitleIsItsRunningOrderByNumber() {
        let rows = LibraryModel.setlistRows(manifest: manifest)
        XCTAssertEqual(rows.first?.subtitle,
                       "2 arrangements · Cavatina #1 · Libertango #1")
    }

    /// Set list subtitles gained the same wording pieces use, so the count
    /// reads the same way in both halves of the library.
    func testASetlistCountsWhatIsInItInWords() {
        let rows = LibraryModel.setlistRows(manifest: manifest)
        XCTAssertTrue(rows.first?.subtitle.hasPrefix("2 arrangements · ") ?? false,
                      "expected the count spelled out first: \(rows.first?.subtitle ?? "")")
        XCTAssertFalse(rows.first?.chips.contains { $0.text.hasSuffix("ARR") } ?? true)
    }

    // MARK: - Sorting

    private var rows: [LibraryRow] { LibraryModel.pieceRows(manifest: manifest) }

    func testSortingByNameIsAlphabetical() {
        let sorted = LibraryModel.sorted(rows, by: .name).map(\.title)
        XCTAssertEqual(sorted, ["Blue Bossa", "Cavatina", "Libertango"])
    }

    func testSortingByArrangementCountPutsTheBiggestFirst() {
        let sorted = LibraryModel.sorted(rows, by: .arrangements).map(\.title)
        XCTAssertEqual(sorted.first, "Cavatina")
    }

    /// The rail is shown ONLY under name. Under any other sort the letters
    /// would not agree with the order of the rows, so it hides rather than
    /// points at nothing.
    func testTheAlphabetRailOnlyExistsUnderNameSort() {
        XCTAssertTrue(LibrarySort.name.showsAlphabetRail)
        for sort in LibrarySort.allCases where sort != .name {
            XCTAssertFalse(sort.showsAlphabetRail, "\(sort) cannot honestly show a rail")
        }
    }

    // MARK: - Search

    func testSearchFindsPartOfATitle() {
        XCTAssertEqual(LibraryModel.searched(rows, query: "tango").map(\.title), ["Libertango"])
    }

    func testSearchIgnoresCaseAndAccents() {
        XCTAssertEqual(LibraryModel.searched(rows, query: "CAVATÍNA").map(\.title), ["Cavatina"])
    }

    func testSearchFindsAComposer() {
        XCTAssertEqual(LibraryModel.searched(rows, query: "Piazzolla").map(\.title),
                       ["Libertango"])
    }

    func testAnEmptySearchChangesNothing() {
        XCTAssertEqual(LibraryModel.searched(rows, query: "   ").count, rows.count)
    }

    func testSearchingForNothingFindsNothingRatherThanEverything() {
        XCTAssertTrue(LibraryModel.searched(rows, query: "zzzz").isEmpty)
    }

    // MARK: - The A–Z rail

    func testRowsFileUnderTheirFirstLetter() {
        let cavatina = rows.first { $0.title == "Cavatina" }!
        XCTAssertEqual(LibraryModel.indexLetter(for: cavatina), "C")
    }

    func testAccentsFileUnderThePlainLetter() {
        let row = LibraryRow(id: "x", title: "Étude", subtitle: "", chips: [], meta: "",
                             sortName: "Étude", composer: "", changed: "", arrangementCount: 1)
        XCTAssertEqual(LibraryModel.indexLetter(for: row), "E")
    }

    func testANumberedTitleFilesUnderHash() {
        let row = LibraryRow(id: "x", title: "3 Gymnopédies", subtitle: "", chips: [], meta: "",
                             sortName: "3 Gymnopédies", composer: "", changed: "",
                             arrangementCount: 1)
        XCTAssertEqual(LibraryModel.indexLetter(for: row), "#")
    }

    func testTheRailKnowsWhichLettersHaveContent() {
        let present = LibraryModel.lettersPresent(in: rows)
        XCTAssertEqual(present, ["B", "C", "L"])
        XCTAssertFalse(present.contains("Z"))
    }

    func testTheRailEndsWithHash() {
        XCTAssertEqual(LibraryModel.alphabet.first, "A")
        XCTAssertEqual(LibraryModel.alphabet.last, "#")
        XCTAssertEqual(LibraryModel.alphabet.count, 27)
    }

    func testGroupingIsAlphabeticalWithHashLast() {
        let extra = rows + [LibraryRow(id: "n", title: "9 Bagatelles", subtitle: "", chips: [],
                                       meta: "", sortName: "9 Bagatelles", composer: "",
                                       changed: "", arrangementCount: 1)]
        XCTAssertEqual(LibraryModel.grouped(extra).map(\.letter), ["B", "C", "L", "#"])
    }

    func testAnEmptyLibraryGroupsIntoNothing() {
        XCTAssertTrue(LibraryModel.grouped([]).isEmpty)
    }

    // MARK: - There are two halves of one place, not three tabs

    /// The tab bar is gone (§4C), and with it the disabled Shared placeholder
    /// that was the point of the test this replaces. The library's halves are
    /// the app's only place-switcher -- and a new kind of thing arrives as a
    /// SEGMENT here rather than as a resurrected tab, which is exactly how
    /// Books arrived.
    func testTheLibraryIsTheOnlyPlaceSwitcher() {
        XCTAssertEqual(LibrarySegment.allCases, [.pieces, .setlists, .books])
        XCTAssertEqual(LibrarySegment.pieces.title, "Pieces")
        XCTAssertEqual(LibrarySegment.setlists.title, "Setlists")
        XCTAssertEqual(LibrarySegment.books.title, "Books")
    }

    func testEveryModeSaysWhatThePencilDoes() {
        XCTAssertEqual(ScoreMode.read.pencilMeaning, "Pencil: select")
        XCTAssertEqual(ScoreMode.edit.pencilMeaning, "Pencil: ink")
        XCTAssertEqual(ScoreMode.performance.pencilMeaning, "Pencil: turn")
    }
}
