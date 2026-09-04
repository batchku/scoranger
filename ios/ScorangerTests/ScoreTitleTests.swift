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

/// The bug reported twice: "v001.mxl" as an arrangement's label, and two
/// arrangements of one piece labelled identically because both carried it.
final class ArrangementLabelTests: XCTestCase {

    func testTheWorkspacesOwnFileNameIsNotAName() {
        XCTAssertTrue(ScoreTitle.isInternalArtifactName("v001.mxl"))
        XCTAssertTrue(ScoreTitle.isInternalArtifactName("v002.musicxml"))
        XCTAssertTrue(ScoreTitle.isInternalArtifactName("v001"))
        // what the first attempt at this fix engraved instead
        XCTAssertTrue(ScoreTitle.isInternalArtifactName("V001"))
    }

    /// Narrow, or it starts refusing real names.
    func testARealNameIsNotAnArtifactName() {
        XCTAssertFalse(ScoreTitle.isInternalArtifactName("Jovano Jovanke"))
        XCTAssertFalse(ScoreTitle.isInternalArtifactName("Variation 3"))
        XCTAssertFalse(ScoreTitle.isInternalArtifactName("V"))
        XCTAssertFalse(ScoreTitle.isInternalArtifactName("Vivaldi"))
        XCTAssertFalse(ScoreTitle.isInternalArtifactName(nil))
    }

    /// PieceScreen read `score.title ?? score.name`, so a poisoned title beat
    /// the real name. It must not.
    func testAPoisonedTitleLosesToTheArrangementsOwnName() {
        XCTAssertEqual(ScoreTitle.arrangementName(title: "v001.mxl",
                                                  name: "Jovano Jovanke accordion",
                                                  slug: "jovano-jovanke-accordion"),
                       "Jovano Jovanke accordion")
        XCTAssertEqual(ScoreTitle.arrangementName(title: "V001", name: "Nature Boy",
                                                  slug: "nature-boy"),
                       "Nature Boy")
    }

    func testARealTitleStillWins() {
        XCTAssertEqual(ScoreTitle.arrangementName(title: "Sous le ciel de Paris",
                                                  name: "sous-le-ciel-quartet",
                                                  slug: "sous-le-ciel-quartet"),
                       "Sous le ciel de Paris")
    }

    /// A file stem still carries the music's name, so it is spelled out rather
    /// than discarded -- and an artifact name is not, because there is no
    /// version of "v001" worth reading.
    func testASlugIsSpelledOutAndAnArtifactNameIsNot() {
        XCTAssertEqual(ScoreTitle.arrangementName(title: "v001.mxl",
                                                  name: "under-paris-skies",
                                                  slug: "x"),
                       "Under paris skies")
        XCTAssertEqual(ScoreTitle.arrangementName(title: "v001.mxl", name: "v001",
                                                  slug: "v001"),
                       "Untitled arrangement")
    }

    func testNoLabelEverContainsAnArtifactName() {
        for (title, name) in [("v001.mxl", "Jovano Jovanke"), ("V001", "v001"),
                              ("v002.musicxml", "under-paris-skies")] {
            let shown = ScoreTitle.arrangementName(title: title, name: name, slug: name)
            XCTAssertFalse(shown.lowercased().contains("v001"), shown)
            XCTAssertFalse(shown.lowercased().contains("v002"), shown)
            XCTAssertFalse(shown.contains(".mxl"), shown)
        }
    }

    // MARK: - two rows of one piece may not read the same

    /// Exactly the screenshot: one piece, two arrangements, both poisoned.
    func testTwoPoisonedArrangementsFallBackToTheirOwnNames() {
        let labels = ScoreTitle.labels(for: [
            .init(title: "v001.mxl", name: "Jovano Jovanke accordion",
                  slug: "jovano-jovanke-accordion"),
            .init(title: "v001.mxl", name: "Jovano Jovanke voice",
                  slug: "jovano-jovanke-voice"),
        ])
        XCTAssertEqual(labels, ["Jovano Jovanke accordion", "Jovano Jovanke voice"])
    }

    /// The names collide too -- which the bulk import can produce, since it
    /// strips "copy" and a leading ordinal off a file stem. The rows are then
    /// told apart by what is IN them.
    func testCollidingNamesAreToldApartByTheirParts() {
        let labels = ScoreTitle.labels(for: [
            .init(title: "v001.mxl", name: "Jovano Jovanke", slug: "jovano-jovanke",
                  parts: ["Accordion"]),
            .init(title: "v001.mxl", name: "Jovano Jovanke", slug: "jovano-jovanke-2",
                  parts: ["Voice", "Guitar"]),
        ])
        XCTAssertEqual(labels, ["Jovano Jovanke — Accordion",
                                "Jovano Jovanke — 2 parts"])
    }

    /// A scan has no parts at all, so what tells it apart is that it is a scan.
    func testAScanIsToldApartFromNotation() {
        let labels = ScoreTitle.labels(for: [
            .init(title: nil, name: "Jovano Jovanke", slug: "a", parts: [], isScan: true),
            .init(title: nil, name: "Jovano Jovanke", slug: "b", parts: [], isScan: false),
        ])
        XCTAssertEqual(labels, ["Jovano Jovanke — scan", "Jovano Jovanke — notation"])
    }

    /// When nothing true distinguishes them, position does -- and the rows are
    /// still different from each other, which is the requirement.
    func testIdenticalArrangementsAreStillNumbered() {
        let labels = ScoreTitle.labels(for: [
            .init(title: nil, name: "Jovano Jovanke", slug: "a"),
            .init(title: nil, name: "Jovano Jovanke", slug: "b"),
            .init(title: nil, name: "Jovano Jovanke", slug: "c"),
        ])
        XCTAssertEqual(labels, ["Jovano Jovanke (1)", "Jovano Jovanke (2)",
                                "Jovano Jovanke (3)"])
        XCTAssertEqual(Set(labels).count, 3)
    }

    /// Arrangements that already differ are left exactly as they are.
    func testDistinctArrangementsAreNotDecorated() {
        let labels = ScoreTitle.labels(for: [
            .init(title: "Jovano Jovanke", name: "a", slug: "a"),
            .init(title: "Nature Boy", name: "b", slug: "b"),
        ])
        XCTAssertEqual(labels, ["Jovano Jovanke", "Nature Boy"])
    }

    func testOneArrangementIsNeverDecorated() {
        XCTAssertEqual(ScoreTitle.labels(for: [.init(title: nil, name: "Nature Boy",
                                                     slug: "nature-boy")]),
                       ["Nature Boy"])
    }
}
