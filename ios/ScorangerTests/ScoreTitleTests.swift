import XCTest

/// L18: the score showed "sous-le-ciel-quartet" as its title -- the file it
/// came out of -- in the top bar and engraved on the page.
final class ScoreTitleTests: XCTestCase {

    func testASlugIsNotATitle() {
        XCTAssertTrue(ScoreTitle.isSlugLike("sous-le-ciel-quartet"))
        XCTAssertTrue(ScoreTitle.isSlugLike("under_paris_skies"))
        XCTAssertTrue(ScoreTitle.isSlugLike("my-score.mxl"))
        XCTAssertTrue(ScoreTitle.isSlugLike("Music21 Fragment"))
        XCTAssertTrue(ScoreTitle.isSlugLike("quartet", slug: "quartet"))
        XCTAssertTrue(ScoreTitle.isSlugLike("   "))
    }

    /// The judgement has to be narrow, or it starts refusing real names.
    func testARealTitleIsATitle() {
        XCTAssertFalse(ScoreTitle.isSlugLike("Sous le ciel de Paris"))
        XCTAssertFalse(ScoreTitle.isSlugLike("Nocturne"))
        XCTAssertFalse(ScoreTitle.isSlugLike("Jean-Pierre Rampal suite"))
        XCTAssertFalse(ScoreTitle.isSlugLike("Étude No. 3"))
    }

    func testATitleIsShownWhenThereIsOne() {
        XCTAssertEqual(ScoreTitle.display(title: "Sous le ciel de Paris",
                                          name: "sous-le-ciel-quartet",
                                          slug: "sous-le-ciel-quartet",
                                          pieceName: "Sous le ciel de Paris",
                                          parts: ["Violin I"]),
                       "Sous le ciel de Paris")
    }

    /// The case in the screenshot: everything the score knows about itself is
    /// the slug, so the view says what it knows instead.
    func testASlugTitleFallsBackToThePieceAndItsParts() {
        XCTAssertEqual(ScoreTitle.display(title: "sous-le-ciel-quartet",
                                          name: "sous-le-ciel-quartet",
                                          slug: "sous-le-ciel-quartet",
                                          pieceName: "Sous le ciel de Paris",
                                          parts: ["Violin I", "Violin II", "Viola", "Cello"]),
                       "Sous le ciel de Paris — 4 parts")
    }

    func testFewPartsAreNamedRatherThanCounted() {
        XCTAssertEqual(ScoreTitle.partDescription(["Violin I", "Viola"]),
                       "Violin I, Viola")
        XCTAssertEqual(ScoreTitle.partDescription(["A", "B", "C", "D"]), "4 parts")
    }

    /// OMR leaves unlabelled staves called "Voice", which describes nothing.
    func testUnnamedPartsAreCountedNotListed() {
        XCTAssertEqual(ScoreTitle.partDescription(["Voice", "Voice", "Voice"]),
                       "3 parts")
        XCTAssertEqual(ScoreTitle.partDescription([]), "")
    }

    /// A slug title with no piece to fall back on still must not print the slug.
    func testItNeverPrintsTheSlug() {
        let shown = ScoreTitle.display(title: "orphan-arrangement", name: "orphan-arrangement",
                                       slug: "orphan-arrangement", pieceName: nil, parts: [])
        XCTAssertEqual(shown, "Untitled arrangement")
        XCTAssertFalse(shown.contains("orphan-arrangement"))
    }

    /// The name saves it when the title is the file and the name is not.
    func testTheNameIsUsedWhenTheTitleIsAFile() {
        XCTAssertEqual(ScoreTitle.display(title: "score.mxl", name: "Blue Bossa",
                                          slug: "blue-bossa", pieceName: nil, parts: []),
                       "Blue Bossa")
    }

    // MARK: - The versions trigger at the top of the canvas

    func testTheVersionsLabelCountsThem() {
        XCTAssertEqual(ScoreTitle.versionsLabel(count: 3), "3 versions")
    }

    /// One version is still worth showing: it is the trigger for the dropdown,
    /// and a control that appears only once there are two of something is a
    /// control nobody finds.
    func testOneVersionIsSingular() {
        XCTAssertEqual(ScoreTitle.versionsLabel(count: 1), "1 version")
    }

    func testNoVersionsSaysNothing() {
        XCTAssertNil(ScoreTitle.versionsLabel(count: 0))
    }
}
