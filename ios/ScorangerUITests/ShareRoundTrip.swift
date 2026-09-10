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

    /// Wait for the seeded set lists to be ON SCREEN, rather than sleeping.
    ///
    /// `sleep(3)` failed a gate at zero share buttons while the test right
    /// below it tapped one successfully in the same run: the library is seeded
    /// through the embedded engine, and three seconds is a bet on the host,
    /// not a wait for the app. This is gate.sh's own rule -- never spend a
    /// wall-clock budget across an engine call; wait for what the app raises.
    private func shareButtons() -> XCUIElementQuery {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-share-"))
    }

    private func waitForSeededSetlists(timeout: TimeInterval = 240) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, shareButtons().count == 0 {
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    func testTheShareButtonIsOnSetlistRowsAndNotOnPieces() throws {
        XCTAssertTrue(openSetlists(), "could not reach the Setlists segment")
        waitForSeededSetlists()
        let shareButtons = self.shareButtons()
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
        waitForSeededSetlists()
        let share = shareButtons().firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 240), "no share control")
        share.tap()
        sleep(4)
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(30).map(\.label)
        print("DIAG after tap:", texts.filter { $0.contains("Sign in") || $0.contains("Settings") })
        XCTAssertTrue(texts.contains { $0.localizedCaseInsensitiveContains("sign in") },
                      "tapping share while signed out said nothing at all")
    }
}
