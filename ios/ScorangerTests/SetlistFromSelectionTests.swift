import XCTest

/// REDESIGN_BRIEF_0.8 §7.4 and §7.5: what a set list made from checked pieces
/// holds, and what it is called.
final class SetlistFromSelectionTests: XCTestCase {

    private func piece(_ slug: String, _ name: String, _ arrangements: [String],
                       composer: String? = nil) -> PieceDoc {
        var doc = PieceDoc(slug: slug, name: name, arrangements: arrangements)
        doc.composer = composer
        return doc
    }

    // 5. setlistFromSelectionPicksFirstArrangements
    func testThreePiecesGiveTheirFirstArrangementsInOrder() {
        let plan = SetlistFromSelection.plan(pieces: [
            piece("a", "Autumn Leaves", ["a-1", "a-2"]),
            piece("b", "Blue Bossa", ["b-1"]),
            piece("c", "Cavatina", ["c-1", "c-2", "c-3"]),
        ])
        XCTAssertEqual(plan.members, ["a-1", "b-1", "c-1"])
        XCTAssertEqual(plan.skipped, [])
        XCTAssertEqual(plan.severalArrangements, 2)
        XCTAssertEqual(plan.notices,
                       ["Added #1 of 2 pieces with several arrangements. Change them in the set list."])
    }

    func testOneArrangementEachSaysNothing() {
        let plan = SetlistFromSelection.plan(pieces: [piece("a", "A", ["a-1"]), piece("b", "B", ["b-1"])])
        XCTAssertEqual(plan.notices, [], "a notice only when something was assumed")
    }

    // 6. emptyPiecesAreSkippedAndReported
    func testAPieceWithNoArrangementsIsSkippedAndNamed() {
        let plan = SetlistFromSelection.plan(pieces: [
            piece("a", "Autumn Leaves", ["a-1"]),
            piece("e", "Empty Folder", []),
        ])
        XCTAssertEqual(plan.members, ["a-1"])
        XCTAssertEqual(plan.skipped, ["Empty Folder"])
        XCTAssertEqual(plan.notices, ["Empty Folder had no arrangements and was skipped."])
    }

    func testNothingIsMadeFromEmptyPiecesAlone() {
        let plan = SetlistFromSelection.plan(pieces: [piece("e", "E", []), piece("f", "F", [])])
        XCTAssertTrue(plan.members.isEmpty)
        XCTAssertEqual(plan.notices, ["2 pieces had no arrangements and were skipped."])
    }

    // 7. autoNameRules
    private let thursday: Date = {
        var parts = DateComponents(); parts.year = 2026; parts.month = 9; parts.day = 10
        return Calendar(identifier: .gregorian).date(from: parts)!   // a Thursday
    }()
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.locale = Locale(identifier: "en_US"); return c
    }

    func testTwoPiecesGiveTheirJoinedTitles() {
        let name = SetlistNaming.name(for: [.init(title: "Autumn Leaves"), .init(title: "Sous le ciel")],
                                      on: thursday, calendar: calendar)
        XCTAssertEqual(name, "Autumn Leaves, Sous le ciel")
    }

    func testThreeTitlesThatFitAreJoinedAndFourAreNot() {
        XCTAssertEqual(SetlistNaming.name(for: [.init(title: "Bach"), .init(title: "Satie"), .init(title: "Ravel")],
                                          on: thursday, calendar: calendar), "Bach, Satie, Ravel")
        let four = SetlistNaming.name(for: (1...4).map { .init(title: "Piece \($0)") },
                                      on: thursday, calendar: calendar)
        XCTAssertEqual(four, "Thursday set", "four pieces are past rule 1")
    }

    func testJoinedTitlesPastTheBudgetFallThrough() {
        let long = SetlistNaming.name(for: [.init(title: "Sous le ciel de Paris"), .init(title: "Under Paris Skies accordion solo")],
                                      on: thursday, calendar: calendar)
        XCTAssertEqual(long, "Thursday set")
        XCTAssertLessThanOrEqual(long.count, SetlistNaming.budget)
    }

    func testSevenByOneComposerAreNamedForTheComposer() {
        let pieces = (1...7).map { SetlistNaming.Piece(title: "Tango \($0)", composer: "Piazzolla") }
        XCTAssertEqual(SetlistNaming.name(for: pieces, on: thursday, calendar: calendar), "Piazzolla, 7 pieces")
        XCTAssertEqual(SetlistNaming.name(for: [pieces[0]], on: thursday, calendar: calendar), "Piazzolla, 1 piece")
    }

    func testComposerEqualityIsStrict() {
        // Punctuation, case and spacing are forgiven; a different spelling is
        // not -- OMR writes one person three ways, and a wrong match is a lie.
        let same = [SetlistNaming.Piece(title: "A", composer: "J.S. Bach"),
                    SetlistNaming.Piece(title: "B", composer: "js bach"),
                    SetlistNaming.Piece(title: "C", composer: "J. S. Bach"),
                    SetlistNaming.Piece(title: "D", composer: " J.S. BACH ")]
        XCTAssertEqual(SetlistNaming.name(for: same, on: thursday, calendar: calendar), "J.S. Bach, 4 pieces")
        let different = [SetlistNaming.Piece(title: "A", composer: "J.S. Bach"),
                         SetlistNaming.Piece(title: "B", composer: "Johann Sebastian Bach"),
                         SetlistNaming.Piece(title: "C", composer: "Bach"),
                         SetlistNaming.Piece(title: "D", composer: "Bach")]
        XCTAssertEqual(SetlistNaming.name(for: different, on: thursday, calendar: calendar), "Thursday set")
    }

    func testAMixedSevenGetTheWeekday() {
        let pieces = (1...7).map { SetlistNaming.Piece(title: "P\($0)", composer: $0 % 2 == 0 ? "X" : "Y") }
        XCTAssertEqual(SetlistNaming.name(for: pieces, on: thursday, calendar: calendar), "Thursday set")
    }

    func testARepeatGetsACount() {
        let pieces = (1...7).map { SetlistNaming.Piece(title: "P\($0)") }
        XCTAssertEqual(SetlistNaming.name(for: pieces, taken: ["Thursday set"], on: thursday, calendar: calendar),
                       "Thursday set 2")
        XCTAssertEqual(SetlistNaming.name(for: pieces, taken: ["Thursday set", "Thursday set 2"],
                                          on: thursday, calendar: calendar), "Thursday set 3")
    }

    func testNoOutputExceedsTheBudgetExceptAComposersOwnName() {
        for count in 1...9 {
            let pieces = (1...count).map { SetlistNaming.Piece(title: "Some Tune Number \($0)") }
            let name = SetlistNaming.name(for: pieces, on: thursday, calendar: calendar)
            XCTAssertLessThanOrEqual(name.count, SetlistNaming.budget, "\(count) pieces gave \"\(name)\"")
        }
        let long = SetlistNaming.name(for: [.init(title: "A", composer: "Johann Sebastian Bach the Younger of Leipzig")],
                                      on: thursday, calendar: calendar)
        XCTAssertTrue(long.hasPrefix("Johann Sebastian Bach the Younger of Leipzig"))
    }
}
