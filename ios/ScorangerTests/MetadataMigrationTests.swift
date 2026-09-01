import XCTest

/// Bringing Newzik's metadata across (`MetadataMigration`).
///
/// The arrangements came over as PDFs, which carry no metadata: 34 of the 44
/// files had a title, and those titles said things like "TEMP_PDF". Everything
/// the reader had corrected -- composer, tags, spelling -- stayed in Newzik and
/// reached the export only as folder names. So it comes across separately and
/// is matched by name, which is the part that can go quietly wrong.
final class MetadataMigrationTests: XCTestCase {

    private func piece(_ name: String, slug: String? = nil, composer: String? = nil,
                       arranger: String? = nil, tags: [String]? = nil) -> PieceDoc {
        PieceDoc(slug: slug ?? name.lowercased().replacingOccurrences(of: " ", with: "-"),
                 name: name, arrangements: ["a1"], composer: composer,
                 arranger: arranger, tags: tags)
    }

    private func entry(_ match: String, title: String? = nil, composer: String = "",
                       arranger: String = "", tags: [String] = []) -> MetadataMigration.Entry {
        .init(match: match, title: title, composer: composer, arranger: arranger, tags: tags)
    }

    /// The case that made normalising necessary. A filesystem will not take a
    /// question mark, so the exported folder -- and therefore the imported
    /// piece -- is spelled with hyphens where the title has "?".
    func testAPieceMatchesTheFolderNameTheFilesystemForcedOnIt() {
        let plan = MetadataMigration.plan(
            entries: [entry("Imate li vino? (Do you have Wine?)", tags: ["Macedonia"])],
            pieces: [piece("Imate li vino- (Do you have Wine-)", slug: "imate-li-vino")])

        XCTAssertEqual(plan.unmatched, [])
        XCTAssertEqual(plan.actions.first?.slug, "imate-li-vino")
        XCTAssertEqual(plan.actions.first?.tags, ["Macedonia"])
    }

    /// Accents and case are levelled too -- "București" survives the round trip
    /// through a folder name in more than one spelling.
    func testAccentsAndCaseDoNotDecideTheMatch() {
        let plan = MetadataMigration.plan(
            entries: [entry("Geamparalele din București", arranger: "transcript: Liviu Gîgiu")],
            pieces: [piece("geamparalele din bucuresti", slug: "geam")])

        XCTAssertEqual(plan.actions.first?.slug, "geam")
        XCTAssertEqual(plan.actions.first?.arranger, "transcript: Liviu Gîgiu")
    }

    /// A typo the reader asked to fix. The piece is FOUND by its imported name
    /// and renamed to the corrected one.
    func testACorrectedTitleRenamesThePieceItMatched() {
        let plan = MetadataMigration.plan(
            entries: [entry("The Star of Country Down",
                            title: "The Star of the County Down", tags: ["Ireland"])],
            pieces: [piece("The Star of Country Down", slug: "star")])

        XCTAssertEqual(plan.actions.first?.rename, "The Star of the County Down")
    }

    /// No rename when the name is already right -- most of the library.
    func testAPieceWhoseNameIsAlreadyRightIsNotRenamed() {
        let plan = MetadataMigration.plan(
            entries: [entry("Kopanitsa", title: "Kopanitsa", tags: ["Bulgaria"])],
            pieces: [piece("Kopanitsa", slug: "kopanitsa")])

        XCTAssertNil(plan.actions.first?.rename)
    }

    /// This fills a library in; it does not overwrite work done since. A piece
    /// that already carries a composer keeps the one it has.
    func testWhatThePieceAlreadySaysIsLeftAlone() {
        let plan = MetadataMigration.plan(
            entries: [entry("Pravo Horo", composer: "Boris Karlov", tags: ["Bulgaria"])],
            pieces: [piece("Pravo Horo", slug: "pravo", composer: "Someone Else")])

        XCTAssertEqual(plan.actions.first?.composer, "", "it overwrote an existing credit")
        XCTAssertEqual(plan.actions.first?.tags, ["Bulgaria"], "tags were absent, so they apply")
    }

    /// Nothing to say means no action at all, so running it twice is harmless.
    func testAPieceThatAlreadyHasEverythingProducesNoAction() {
        let entries = [entry("Medeno Kolo", composer: "Ljubisa Pavkovic", tags: ["Serbia"])]
        let done = [piece("Medeno Kolo", slug: "medeno",
                          composer: "Ljubisa Pavkovic", tags: ["Serbia"])]

        XCTAssertTrue(MetadataMigration.plan(entries: entries, pieces: done).actions.isEmpty)
    }

    /// A piece that is not in the library is REPORTED, never approximated onto
    /// whichever name looked closest.
    func testAnEntryWithNoPieceIsReportedNotGuessed() {
        let plan = MetadataMigration.plan(
            entries: [entry("Real Book"), entry("Kopanitsa", tags: ["Bulgaria"])],
            pieces: [piece("Kopanitsa", slug: "kopanitsa")])

        XCTAssertEqual(plan.unmatched, ["Real Book"])
        XCTAssertEqual(plan.actions.count, 1)
    }

    /// The file that ships with the app is the real one, and it has to parse.
    func testTheBundledFileParsesAndCarriesTheCorrections() {
        let entries = MetadataMigration.bundled(Bundle(for: type(of: self)))
        guard !entries.isEmpty else { return }   // resource not in the test bundle

        XCTAssertEqual(entries.count, 40)
        XCTAssertEqual(entries.first { $0.match == "Nature Boy (Real Book)" }?.composer,
                       "eden ahbez")
        XCTAssertEqual(entries.first { $0.match == "The Star of Country Down" }?.title,
                       "The Star of the County Down")
    }
}
