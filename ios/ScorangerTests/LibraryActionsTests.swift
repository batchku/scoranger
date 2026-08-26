import XCTest

/// What the Edit-mode action bar offers (NAV_REVISION_0.4.1 §2.2).
///
/// The spec says outright that mixing these up was the first draft's mistake,
/// so the rule is stated where it can be checked: a piece is a FOLDER, and the
/// verbs that belong to arrangements are one level down.
final class LibraryActionsTests: XCTestCase {

    // MARK: - A piece is a folder

    func testAPieceCanBeRenamedFilledOrThrownAway() {
        XCTAssertEqual(LibraryActions.bar(for: .pieces),
                       [.rename, .newArrangement, .delete])
    }

    func testAPieceCannotBeMovedIntoAPiece() {
        XCTAssertFalse(LibraryActions.bar(for: .pieces).contains(.moveToPiece),
                       "a folder does not go inside a folder")
    }

    func testAPieceCannotBeDuplicatedOrPutInASetList() {
        let bar = LibraryActions.bar(for: .pieces)
        XCTAssertFalse(bar.contains(.duplicate), "you duplicate an arrangement, not a piece")
        XCTAssertFalse(bar.contains(.addToSetlist),
                       "a set list holds arrangements; a piece is not one")
    }

    // MARK: - A set list is a running order

    func testASetListCanOnlyBeRenamedOrDeleted() {
        XCTAssertEqual(LibraryActions.bar(for: .setlists), [.rename, .delete])
    }

    // MARK: - An arrangement is the thing the verbs were written for

    func testAnArrangementCarriesTheFullSet() {
        XCTAssertEqual(LibraryActions.bar(for: .arrangements),
                       [.moveToPiece, .addToSetlist, .duplicate, .rename, .delete])
    }

    // MARK: - Mixed selections

    /// A verb that is wrong for half of what is highlighted is worse than one
    /// fewer button.
    func testAMixedSelectionOffersOnlyWhatIsTrueOfEverything() {
        XCTAssertEqual(LibraryActions.bar(for: .mixed), [.delete])
    }

    func testOneKindSelectedIsThatKind() {
        XCTAssertEqual(LibraryActions.kind(of: ["a", "b"], pieces: ["a", "b"],
                                           setlists: []), .pieces)
        XCTAssertEqual(LibraryActions.kind(of: ["s"], pieces: [], setlists: ["s"]),
                       .setlists)
        XCTAssertEqual(LibraryActions.kind(of: ["x"], pieces: [], setlists: []),
                       .arrangements)
    }

    /// The Pieces list holds unfiled ARRANGEMENTS alongside pieces, so this is
    /// a real state and not a hypothetical.
    func testAPieceAndAnUnfiledArrangementTogetherAreMixed() {
        XCTAssertEqual(LibraryActions.kind(of: ["piece", "loose"], pieces: ["piece"],
                                           setlists: []), .mixed)
    }

    // MARK: - What greys, and what never moves

    func testRenameNeedsExactlyOneRow() {
        XCTAssertTrue(LibraryActions.isEnabled(.rename, count: 1))
        XCTAssertFalse(LibraryActions.isEnabled(.rename, count: 3))
    }

    func testDeleteWorksOnManyAtOnce() {
        XCTAssertTrue(LibraryActions.isEnabled(.delete, count: 4))
    }

    func testNothingIsEnabledWithNothingSelected() {
        for action in LibraryAction.allCases {
            XCTAssertFalse(LibraryActions.isEnabled(action, count: 0))
        }
    }

    /// Greyed, not absent: the bar must not re-flow under the user's finger as
    /// they add a second row to the selection.
    func testTheBarKeepsItsShapeWhateverIsSelected() {
        for count in 1...5 {
            XCTAssertEqual(LibraryActions.bar(for: .arrangements).count, 5,
                           "the bar changed length at \(count) selected")
        }
    }

    // MARK: - What the destructive verb says

    func testDeleteNamesWhatItWillDestroy() {
        XCTAssertEqual(LibraryAction.delete.title(count: 3, kind: .pieces),
                       "Delete 3 pieces")
        XCTAssertEqual(LibraryAction.delete.title(count: 2, kind: .setlists),
                       "Delete 2 set lists")
    }

    func testASingleDeleteIsJustDelete() {
        XCTAssertEqual(LibraryAction.delete.title(count: 1, kind: .pieces), "Delete")
    }

    func testEveryActionHasAStableIdentifier() {
        let ids = Set(LibraryAction.allCases.map(\.identifier))
        XCTAssertEqual(ids.count, LibraryAction.allCases.count,
                       "two actions share an accessibility id")
        XCTAssertTrue(ids.contains("bar-move"))
        XCTAssertTrue(ids.contains("bar-duplicate"))
    }
}
