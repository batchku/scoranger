import XCTest

/// The sharing round trip, as far as it can be exercised without credentials.
final class ShareRoundTrip: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-resetViewPreferences",
                               "-seedTestLibrary"]
        app.launch()
    }

    private func openSetlists() -> Bool {
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 240)
        let seg = app.descendants(matching: .any)["Setlists"]
        if seg.waitForExistence(timeout: 20) { seg.tap(); return true }
        // segmented control may expose differently
        let alt = app.buttons.matching(NSPredicate(format: "label == %@", "Setlists")).firstMatch
        if alt.waitForExistence(timeout: 10) { alt.tap(); return true }
        return false
    }

    func testTheShareButtonIsOnSetlistRowsAndNotOnPieces() throws {
        XCTAssertTrue(openSetlists(), "could not reach the Setlists segment")
        sleep(3)
        let shareButtons = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-share-"))
        print("DIAG share buttons on Setlists:", shareButtons.count)
        XCTAssertGreaterThan(shareButtons.count, 0,
                             "no share control on any set list row")

        // And NOT on pieces -- books and sources have no share path (§8.2).
        let pieces = app.descendants(matching: .any)["Pieces"]
        if pieces.exists { pieces.tap(); sleep(2) }
        let onPieces = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-share-"))
        print("DIAG share buttons on Pieces:", onPieces.count)
        XCTAssertEqual(onPieces.count, 0,
                       "a share control appeared on a piece row")
    }

    func testTappingShareSignedOutExplainsRatherThanDoingNothing() throws {
        XCTAssertTrue(openSetlists(), "could not reach the Setlists segment")
        sleep(3)
        let share = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-share-"))
            .firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 20), "no share control")
        share.tap()
        sleep(4)
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(30).map(\.label)
        print("DIAG after tap:", texts.filter { $0.contains("Sign in") || $0.contains("Settings") })
        XCTAssertTrue(texts.contains { $0.localizedCaseInsensitiveContains("sign in") },
                      "tapping share while signed out said nothing at all")
    }
}
