import XCTest

/// What combining says it will do, which is what the engine's `combine-pieces`
/// actually does. The two descriptions have to agree or the screen lies.
final class CombinePiecesTests: XCTestCase {

    private func piece(_ slug: String, _ name: String, arrangements: [String],
                       composer: String? = nil, arranger: String? = nil,
                       tags: [String]? = nil) -> PieceDoc {
        PieceDoc(slug: slug, name: name, arrangements: arrangements,
                 composer: composer, arranger: arranger, tags: tags)
    }

    /// One piece is not an operation. The bar greys the button; the planner
    /// says so rather than proposing a combine of a thing with itself.
    func testOnePieceIsNotAPlan() {
        let plan = CombinePieces.plan(pieces: [piece("a", "A", arrangements: ["x"])])
        XCTAssertFalse(plan.isPossible)
        XCTAssertTrue(plan.consequences.isEmpty)
    }

    func testNoPiecesIsNotAPlan() {
        XCTAssertFalse(CombinePieces.plan(pieces: []).isPossible)
    }

    /// THE FIRST IN THE LIST SURVIVES, and it is the list's order that decides
    /// -- not the alphabet, not which has more arrangements.
    func testTheFirstListedSurvives() {
        let plan = CombinePieces.plan(pieces: [
            piece("zeta", "Zeta", arrangements: ["z1"]),
            piece("alpha", "Alpha", arrangements: ["a1", "a2", "a3"]),
        ])
        XCTAssertTrue(plan.isPossible)
        XCTAssertEqual(plan.survivor, "zeta")
        XCTAssertEqual(plan.survivorName, "Zeta")
        XCTAssertEqual(plan.absorbed, ["alpha"])
    }

    /// THE NUMBERING, which is the thing a reader notices first: what was #1
    /// stays #1, and the arrivals start after the last one that was there.
    func testTheSurvivorsArrangementsKeepTheirNumbers() {
        let plan = CombinePieces.plan(pieces: [
            piece("drowsy", "Drowsy Maggie", arrangements: ["d1", "d2"]),
            piece("drowsy-2", "Drowsy Maggie (Kenny)", arrangements: ["k1"]),
        ])
        XCTAssertEqual(plan.kept, 2)
        XCTAssertEqual(plan.arriving, 1)
        XCTAssertEqual(plan.total, 3)
        XCTAssertTrue(plan.consequences.contains {
            $0.contains("numbered #3 onwards") && $0.contains("first 2 keep their numbers")
        }, "the numbering consequence is not stated: \(plan.consequences)")
    }

    /// An empty survivor has nothing to keep, so the sentence about keeping
    /// numbers would be a lie. It is not said.
    func testAnEmptySurvivorIsNotToldItKeptNumbers() {
        let plan = CombinePieces.plan(pieces: [
            piece("empty", "Empty", arrangements: []),
            piece("full", "Full", arrangements: ["f1", "f2"]),
        ])
        XCTAssertEqual(plan.kept, 0)
        XCTAssertTrue(plan.consequences.contains { $0 == "2 arrangements move across." })
        XCTAssertFalse(plan.consequences.contains { $0.contains("keep their numbers") })
    }

    /// A CREDIT THE SURVIVOR DOES NOT HAVE is carried across. Combining two
    /// records of one tune usually means one was credited and one was not, and
    /// dropping the credit is the wrong default.
    func testAMissingComposerIsTakenFromTheFirstThatHasOne() {
        let plan = CombinePieces.plan(pieces: [
            piece("sibeag", "Sí Beag Sí Mór", arrangements: ["s1"]),
            piece("sibeag-2", "Si Beag Si Mor", arrangements: ["s2"],
                  composer: "Turlough O'Carolan"),
        ])
        XCTAssertEqual(plan.composerFilled, "Turlough O'Carolan")
        XCTAssertTrue(plan.consequences.contains {
            $0.contains("takes the composer Turlough O'Carolan")
        })
    }

    /// A credit the survivor DOES have is not overwritten -- somebody typed it.
    func testAnExistingCreditIsNotOverwritten() {
        let plan = CombinePieces.plan(pieces: [
            piece("a", "A", arrangements: ["x"], composer: "Trad."),
            piece("b", "B", arrangements: ["y"], composer: "Somebody Else"),
        ])
        XCTAssertNil(plan.composerFilled)
        XCTAssertFalse(plan.consequences.contains { $0.contains("takes the composer") })
    }

    /// Tags are unioned, survivor's first, and deduplicated without regard to
    /// case -- "Ireland" and "ireland" are one tag.
    func testTagsAreUnionedAndDeduplicated() {
        let plan = CombinePieces.plan(pieces: [
            piece("a", "A", arrangements: ["x"], tags: ["Ireland", "session"]),
            piece("b", "B", arrangements: ["y"], tags: ["ireland", "reel"]),
        ])
        XCTAssertEqual(plan.tags, ["Ireland", "session", "reel"])
    }

    /// Several pieces at once, and the sentence counts them rather than
    /// listing them.
    func testSeveralPiecesAreCountedNotListed() {
        let plan = CombinePieces.plan(pieces: [
            piece("a", "A", arrangements: ["x"]),
            piece("b", "B", arrangements: ["y"]),
            piece("c", "C", arrangements: ["z"]),
        ])
        XCTAssertEqual(plan.absorbed, ["b", "c"])
        XCTAssertEqual(plan.total, 3)
        XCTAssertTrue(plan.consequences.contains {
            $0 == "2 pieces are folded into A and stop existing."
        }, "\(plan.consequences)")
    }

    /// THE WARNING IS ALWAYS LAST AND ALWAYS THERE. The screen is the only
    /// route to an operation with no undo, so this is the one line that may
    /// never be conditional.
    func testTheNoUndoWarningIsAlwaysTheLastThingSaid() {
        for pieces in [[piece("a", "A", arrangements: []),
                        piece("b", "B", arrangements: [])],
                       [piece("a", "A", arrangements: ["x"], composer: "Trad."),
                        piece("b", "B", arrangements: ["y"], tags: ["reel"])]] {
            let plan = CombinePieces.plan(pieces: pieces)
            XCTAssertEqual(plan.consequences.last, "There is no undo.")
        }
    }

    /// The bar must offer it only for several pieces, and grey rather than
    /// hide it for one -- the bar may not re-flow as the selection changes.
    func testTheBarOffersCombineForPiecesAndOnlyWithSeveral() {
        XCTAssertTrue(LibraryActions.bar(for: .pieces).contains(.combine))
        XCTAssertFalse(LibraryActions.bar(for: .arrangements).contains(.combine))
        XCTAssertFalse(LibraryActions.bar(for: .setlists).contains(.combine))
        XCTAssertFalse(LibraryActions.bar(for: .mixed).contains(.combine))
        XCTAssertFalse(LibraryActions.isEnabled(.combine, count: 1))
        XCTAssertTrue(LibraryActions.isEnabled(.combine, count: 2))
        XCTAssertFalse(LibraryActions.isEnabled(.combine, count: 0))
    }
}
