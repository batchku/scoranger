import XCTest

/// The reset is total, or the suite cannot run in parallel.
///
/// Parallel workers make every test potentially FIRST, and potentially second
/// after any other test. Which means a preference one test changes is a
/// preference every other test may inherit, and the order that exposes it
/// changes run to run. The old reset set the score layout and cleared the
/// drawings and left `chatInputLines2`, `showTransport`, `didRevealTransport`
/// and `touchDiagnostics` behind, so this is the test that says the reset now
/// clears whatever the app has stored rather than whatever someone listed.
///
/// Three preferences are driven and read back, chosen to be different in kind:
/// a string (`scoreLayout`), a boolean that defaults FALSE (`touchDiagnostics`)
/// and a boolean that defaults TRUE (`useLocalEngine`). They are not a list to
/// keep up to date: `TestReset.wipeDefaults` removes the persistent domain, so
/// one key surviving would mean all of them survived.
///
/// The last one was `showTransport` until 0.8 retired the switch with the
/// tray (§7.7). The on-device engine switch is the same kind of thing -- on
/// by default, and a leak leaves it OFF for the next test, which then finds
/// playback unavailable and blames the engine.
final class StateReset: XCTestCase {

    private var app: XCUIApplication!
    private let piece = "Sous le ciel de Paris"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testAFreshLaunchInheritsNoPreferenceFromTheLaunchBeforeIt() {
        launch(["-resetLibrary", "-seedTestLibrary"])

        // --- leave the state a previous test would leave ---
        openSettings()
        setToggle("Continuous", to: true)
        setToggle("Show what the canvas is receiving", to: true)
        setToggle("Use on-device engine", to: false)
        closeSettings()

        // --- and come back the way a parallel worker's next test does ---
        // No -resetLibrary: the library is deliberately kept, so what this
        // asserts is the PREFERENCE reset and not the workspace being thrown
        // away underneath it.
        app.terminate()
        launch(["-resetViewPreferences", "-seedTestLibrary"])

        openSettings()
        XCTAssertEqual(toggle("One page").value as? String, "1",
                       "the layout did not come back to one page")
        XCTAssertEqual(toggle("Continuous").value as? String, "0",
                       "scoreLayout survived the reset")
        XCTAssertEqual(toggle("Show what the canvas is receiving").value as? String, "0",
                       "touchDiagnostics survived the reset")
        XCTAssertEqual(toggle("Use on-device engine").value as? String, "1",
                       "useLocalEngine survived the reset: the next test would find "
                       + "playback unavailable and blame the engine")
        closeSettings()

        XCTAssertFalse(app.descendants(matching: .any)["touch-diagnostics"].exists,
                       "the diagnostics overlay is still on screen")

        // And the tray is there on the first arrangement, as it always is now
        // (0.8 §7.7): no preference decides it.
        openFirstArrangement()
        XCTAssertTrue(app.otherElements["transport"].waitForExistence(timeout: 60),
                      "no tray on the score")
    }

    // MARK: - the small amount of driving this needs

    private func launch(_ arguments: [String]) {
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["library-search"]
                        .waitForExistence(timeout: 90),
                      "the app never showed My Library")
        let anyRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                        "row-", piece)).firstMatch
        XCTAssertTrue(anyRow.waitForExistence(timeout: 180),
                      "the seeded library never finished importing")
    }

    /// Settings is a split (0.8 §7.17): one section at a time, so the toggle's
    /// section is opened from the index before the toggle is looked for.
    private func toggle(_ title: String) -> XCUIElement {
        let section: String
        switch title {
        case "Show what the canvas is receiving": section = "settings-diagnostics"
        case "Use on-device engine":              section = "settings-engine"
        default:                                  section = "settings-reading"
        }
        let item = app.buttons[section]
        if item.waitForExistence(timeout: 10), !item.isSelected { item.tap() }
        return app.switches[title].firstMatch
    }

    private func setToggle(_ title: String, to wanted: Bool) {
        let t = toggle(title)
        XCTAssertTrue(t.waitForExistence(timeout: 20), "no toggle titled \(title)")
        if (t.value as? String == "1") != wanted { t.tap() }
        XCTAssertTrue(waitForValue(t, wanted ? "1" : "0"),
                      "\(title) would not go \(wanted ? "on" : "off")")
    }

    private func openSettings() {
        app.buttons["library-settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings-panel"].firstMatch
                        .waitForExistence(timeout: 20),
                      "Settings did not open")
    }

    private func closeSettings() {
        let close = app.buttons["Close settings"]
        if close.waitForExistence(timeout: 10) { close.tap() }
        XCTAssertTrue(waitForDisappearance(
            of: app.descendants(matching: .any)["settings-panel"].firstMatch, timeout: 15),
                      "Settings would not close")
    }

    /// A piece is not openable: its row pushes a screen, and the arrangement is
    /// chosen there.
    private func openFirstArrangement() {
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                        "row-", piece)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 180), "the library never listed the piece")
        row.tap()
        let choice = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "arrangement-choice-")).firstMatch
        if !choice.waitForExistence(timeout: 15), row.exists, row.isHittable { row.tap() }
        XCTAssertTrue(choice.waitForExistence(timeout: 30),
                      "the piece screen did not list its arrangements")
        choice.tap()
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "the score never finished engraving")
    }

    @discardableResult
    private func waitForValue(_ element: XCUIElement, _ expected: String,
                              timeout: TimeInterval = 20) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.value as? String == expected { return true }
            usleep(150_000)
        }
        return element.value as? String == expected
    }

    private func waitForDisappearance(of element: XCUIElement,
                                      timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            usleep(150_000)
        }
        return !element.exists
    }
}
