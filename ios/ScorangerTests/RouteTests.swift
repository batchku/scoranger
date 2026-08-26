import XCTest

/// The navigation rules (NAV_MODAL_FREE_0.4.2 §1, §3.5, §8.6).
final class RouteTests: XCTestCase {

    /// §3.5's rule, in one line: pushing is right when the actions need a
    /// target list or lead to more detail; expanding is right when they are
    /// immediate and positional. The spec flags that two behaviours could read
    /// as inconsistent, so the rule deciding between them is stated once.
    func testARowWhoseActionsNeedATargetPushes() {
        XCTAssertEqual(RowMenuBehaviour.forRow(needsATarget: true), .push)
    }

    func testARowWhoseActionsAreAllOneTapExpands() {
        XCTAssertEqual(RowMenuBehaviour.forRow(needsATarget: false), .expand)
    }

    /// A library row can move to a piece and open its details, so it pushes.
    /// A set-list member can only move up, move down and be removed, so it
    /// expands. Those are the two real cases in the app.
    func testTheTwoRealCases() {
        XCTAssertEqual(RowMenuBehaviour.forRow(needsATarget: true), .push,
                       "an arrangement row leads to Move to piece and Details")
        XCTAssertEqual(RowMenuBehaviour.forRow(needsATarget: false), .expand,
                       "a set-list member's actions are all positional")
    }

    // MARK: - Back labels name the place

    func testTopLevelScreensSayWhereBackGoes() {
        XCTAssertEqual(Route.piece("cavatina").backLabel, "My library")
        XCTAssertEqual(Route.setlist("friday").backLabel, "My library")
        XCTAssertEqual(Route.settings.backLabel, "My library")
    }

    func testDeeperScreensJustSayBack() {
        XCTAssertEqual(Route.moveToPiece(["a"]).backLabel, "Back")
        XCTAssertEqual(Route.versions("a").backLabel, "Back")
    }

    // MARK: - Routes are values, so a stack can hold them

    func testTheSameScreenTwiceIsTheSameRoute() {
        XCTAssertEqual(Route.piece("cavatina"), Route.piece("cavatina"))
        XCTAssertNotEqual(Route.piece("cavatina"), Route.piece("libertango"))
    }

    func testMovingASelectionIsOneScreenForAllOfIt() {
        XCTAssertEqual(Route.moveToPiece(["a", "b"]), Route.moveToPiece(["a", "b"]))
        XCTAssertNotEqual(Route.moveToPiece(["a"]), Route.moveToPiece(["a", "b"]))
    }
}
