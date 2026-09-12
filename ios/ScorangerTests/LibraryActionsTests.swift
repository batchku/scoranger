import XCTest

/// What the Edit-mode action bar offers (NAV_REVISION_0.4.1 §2.2).
///
/// The spec says outright that mixing these up was the first draft's mistake,
/// so the rule is stated where it can be checked: a piece is a FOLDER, and the
/// verbs that belong to arrangements are one level down.
final class LibraryActionsTests: XCTestCase {

    // MARK: - A piece is a folder

    func testAPieceCanBeFilledOrThrownAway() {
        XCTAssertEqual(LibraryActions.bar(for: .pieces), [.newArrangement, .newSetlist, .delete])
    }

    /// There is no Rename anywhere in the bars. A name is edited by TAPPING IT
    /// on the item's own screen: the value is the control, so a button whose
    /// only job was to make it editable has nothing left to do.
    func testNothingOffersARenameButton() {
        for kind in [LibrarySelectionKind.pieces, .setlists, .arrangements, .mixed] {
            XCTAssertFalse(LibraryActions.bar(for: kind)
                            .contains { $0.identifier.contains("rename") },
                           "\(kind) still offers a Rename button")
        }
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

    func testASetListCanOnlyBeDeleted() {
        XCTAssertEqual(LibraryActions.bar(for: .setlists), [.delete])
    }

    // MARK: - An arrangement is the thing the verbs were written for

    func testAnArrangementCarriesTheFullSet() {
        XCTAssertEqual(LibraryActions.bar(for: .arrangements),
                       [.moveToPiece, .addToSetlist, .newSetlist, .duplicate, .delete])
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

    func testNewArrangementNeedsExactlyOnePiece() {
        XCTAssertTrue(LibraryActions.isEnabled(.newArrangement, count: 1))
        XCTAssertFalse(LibraryActions.isEnabled(.newArrangement, count: 3),
                       "which of the three would it go into?")
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

    /// 0.8.0 build 194 (Ali's item 5): checked pieces or arrangements can
    /// become a set list, named for what was checked.
    func testASelectionCanBecomeASetList() {
        XCTAssertTrue(LibraryActions.bar(for: .pieces).contains(.newSetlist))
        XCTAssertTrue(LibraryActions.bar(for: .arrangements).contains(.newSetlist))
        XCTAssertFalse(LibraryActions.bar(for: .setlists).contains(.newSetlist),
                       "a set list of set lists is not a thing")
        XCTAssertTrue(LibraryActions.isEnabled(.newSetlist, count: 1))
        XCTAssertTrue(LibraryActions.isEnabled(.newSetlist, count: 5))
        XCTAssertEqual(LibraryAction.newSetlist.identifier, "bar-new-setlist")
        XCTAssertEqual(LibraryAction.newSetlist.title(count: 3, kind: .pieces), "Set list from 3 pieces")
        XCTAssertEqual(LibraryAction.newSetlist.title(count: 1, kind: .pieces), "Set list from this piece")
    }

    /// The name: the pieces' names while they fit, then a count; never a
    /// date or a number a person has to rename.
    func testTheNewSetListIsNamedForWhatWasChecked() {
        XCTAssertEqual(SetlistNaming.name(for: ["Blue Bossa"]), "Blue Bossa")
        XCTAssertEqual(SetlistNaming.name(for: ["Blue Bossa", "Libertango"]),
                       "Blue Bossa and Libertango")
        XCTAssertEqual(SetlistNaming.name(for: ["Blue Bossa", "Libertango", "Cavatina"]),
                       "Blue Bossa, Libertango and Cavatina")
        XCTAssertEqual(SetlistNaming.name(for: ["Blue Bossa", "Libertango", "Cavatina", "Sous le ciel de Paris"]),
                       "Blue Bossa, Libertango and 2 more")
        XCTAssertEqual(SetlistNaming.name(for: []), "New set list")
        // Taken names get a count, not a collision.
        XCTAssertEqual(SetlistNaming.name(for: ["Blue Bossa"], taken: ["Blue Bossa"]), "Blue Bossa 2")
        XCTAssertEqual(SetlistNaming.name(for: ["Blue Bossa"], taken: ["Blue Bossa", "Blue Bossa 2"]), "Blue Bossa 3")
    }
}
