import XCTest

/// The offer to correct titles engraved before the engine guarded the way in.
///
/// The damage is in the NOTATION of versions already written, so no amount of
/// display logic reaches it: the page, and every export off it, still print
/// "v001.mxl".
final class TitleRepairTests: XCTestCase {

    private func score(_ slug: String, title: String?, name: String,
                       file: String = "v002.musicxml") -> ScoreDoc {
        ScoreDoc(slug: slug, name: name, title: title, composer: nil,
                 latest: "v002",
                 versions: [VersionDoc(id: "v002", file: file, op: "omr")],
                 sources: nil, piece: nil)
    }

    func testAnArrangementEngravingAFileNameIsOffered() {
        XCTAssertEqual(TitleRepair.affected([
            score("a", title: "v001.mxl", name: "Jovano Jovanke accordion"),
            score("b", title: "V001", name: "Jovano Jovanke voice"),
        ]), ["a", "b"])
    }

    func testARealTitleIsLeftAlone() {
        XCTAssertEqual(TitleRepair.affected([
            score("a", title: "Jovano Jovanke", name: "Jovano Jovanke"),
            score("b", title: "Jean-Pierre Rampal suite", name: "b"),
        ]), [])
    }

    /// A title that is a file STEM is the same defect, and the same fix.
    func testASlugTitleIsOfferedToo() {
        XCTAssertEqual(TitleRepair.affected([
            score("a", title: "sous-le-ciel-quartet", name: "Sous le ciel de Paris"),
        ]), ["a"])
    }

    /// A scan has no notation to write a correction into, and its title never
    /// came out of a file in the first place.
    func testAScanIsNotOffered() {
        XCTAssertEqual(TitleRepair.affected([
            score("a", title: "v001.mxl", name: "Jovano Jovanke", file: "v001.pdf"),
        ]), [])
    }

    /// Nothing anywhere is a name: the engine reports it rather than inventing
    /// one, so there is nothing to offer here either.
    func testAnArrangementNothingCanNameIsNotOffered() {
        XCTAssertEqual(TitleRepair.affected([
            score("a", title: "v001.mxl", name: "v001"),
        ]), [])
    }

    func testTheOfferExistsOnlyWhileThereIsDamage() {
        XCTAssertNil(TitleRepair.offer(count: 0))
        XCTAssertEqual(TitleRepair.offer(count: 1)?.hasPrefix("1 arrangement has"), true)
        XCTAssertEqual(TitleRepair.offer(count: 40)?.hasPrefix("40 arrangements have"),
                       true)
    }

    /// It says what it will DO, because it adds a version to every one of them.
    func testTheOfferSaysWhatItCosts() {
        let offer = TitleRepair.offer(count: 40) ?? ""
        XCTAssertTrue(offer.contains("adds one version"), offer)
        XCTAssertTrue(offer.contains("step back"), offer)
    }

    func testTheOutcomeCountsWhatHappened() {
        XCTAssertEqual(TitleRepair.outcome(repaired: 0, failed: 0),
                       "Nothing needed fixing.")
        XCTAssertEqual(TitleRepair.outcome(repaired: 1, failed: 0),
                       "Fixed 1 arrangement.")
        XCTAssertEqual(TitleRepair.outcome(repaired: 39, failed: 1),
                       "Fixed 39 arrangements. 1 could not be read and was left alone.")
    }
}
