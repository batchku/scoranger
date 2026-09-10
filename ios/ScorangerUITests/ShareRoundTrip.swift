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

    /// The recipient's half (§6A.5), as far as it goes without an account.
    ///
    /// `-seedSharedSetlist` binds a local set list to a share somebody else
    /// owns, which is the exact state a library is in after joining. Two
    /// things then have to be true, and neither was: the row reads as SHARED
    /// (the two-people glyph, labelled "Sharing for"), and tapping that glyph
    /// opens the shared screen -- who is in it, the link again -- rather than
    /// running the whole promotion again and minting a fresh link.
    func testAJoinedSetlistReadsAsSharedAndOpensTheSharedScreen() throws {
        app.terminate()
        app.launchArguments = ["-resetLibrary", "-resetViewPreferences",
                               "-seedTestLibrary", "-seedSharedSetlist"]
        app.launch()
        XCTAssertTrue(openSetlists(), "could not reach the Setlists segment")
        waitForSeededSetlists()

        let sharing = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Sharing for"))
            .firstMatch
        XCTAssertTrue(sharing.waitForExistence(timeout: 240),
                      "the joined set list's row does not read as shared")
        // And a plain, unshared seed row still offers to share.
        let plain = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Share "))
            .firstMatch
        XCTAssertTrue(plain.exists, "an unshared set list lost its share button")

        sharing.tap()
        let screen = app.descendants(matching: .any)["screen-shared-setlist"]
        XCTAssertTrue(screen.waitForExistence(timeout: 30),
                      "tapping the shared glyph did not open the shared screen")
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
