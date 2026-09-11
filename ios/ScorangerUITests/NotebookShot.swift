import XCTest

/// Photographs of the Notebook's pages and panel, for a person to look at:
/// the library with a row's actions open and the Arrangements panel beside
/// it; Sort; the piece screen with This piece at rest; the set list screen.
/// Written to `SCORANGER_SHOT_DIR` when set. Not in the gate: photographs
/// cannot fail a build.
final class NotebookShot: XCTestCase {
    var app: XCUIApplication!

    private func snap(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["SCORANGER_SHOT_DIR"],
           let png = screenshot.pngRepresentation as NSData? {
            png.write(toFile: directory + "/\(name).png", atomically: true)
        }
    }

    func testPhotographTheNotebook() throws {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-resetViewPreferences", "-seedTestLibrary"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 240)
        let row = app.descendants(matching: .any)["row-sous-le-ciel-de-paris"]
        guard row.waitForExistence(timeout: 180) else { return XCTFail("no piece") }
        waitForTheLibraryToSettle(app)
        sleep(1)
        snap("library-at-rest")

        app.buttons["library-sort"].tap()
        sleep(1)
        snap("library-sort-panel")
        app.buttons["panel-done"].firstMatch.tap()
        // The page widens again as the panel leaves; tap where the ☰ IS.
        settle(row, still: 0.6)

        app.buttons["row-menu-sous-le-ciel-de-paris"].firstMatch.tap()
        sleep(1)
        snap("library-row-actions")
        let arrangements = app.descendants(matching: .any)["row-arrangements-sous-le-ciel-de-paris"].firstMatch
        if arrangements.waitForExistence(timeout: 5) {
            arrangements.tap(); sleep(1)
            snap("library-arrangements-panel")
        }
        let details = app.descendants(matching: .any)["row-details-sous-le-ciel-de-paris"].firstMatch
        if details.exists { details.tap(); sleep(1); snap("library-this-piece-panel") }
        // Back to the Arrangements panel, whose last item is the piece screen.
        if arrangements.exists { arrangements.tap(); sleep(1) }
        let pieceScreen = app.descendants(matching: .any)["piece-screen-sous-le-ciel-de-paris"].firstMatch
        if pieceScreen.waitForExistence(timeout: 5) {
            pieceScreen.tap(); sleep(2)
            snap("piece-screen")
            let menu = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-menu-")).firstMatch
            if menu.exists { menu.tap(); sleep(1); snap("piece-screen-row-actions") }
            let manage = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "arrangement-manage-")).firstMatch
            if manage.exists { manage.tap(); sleep(1); snap("piece-screen-arrangement-panel") }
            app.buttons["screen-back"].firstMatch.tap(); sleep(1)
        }

        app.buttons["segment-setlists"].tap(); sleep(1)
        snap("library-setlists")
        let setlistMenu = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-menu-")).firstMatch
        if setlistMenu.waitForExistence(timeout: 5) {
            setlistMenu.tap(); sleep(1); snap("library-setlist-row-actions")
            let screen = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "row-setlist-screen-")).firstMatch
            if screen.exists {
                screen.tap(); sleep(2); snap("setlist-screen")
                let member = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-menu-")).firstMatch
                if member.exists { member.tap(); sleep(1); snap("setlist-member-actions") }
            }
        }
    }
}

extension NotebookShot {
    /// The score: the rail, More, Chat and the title block's Versions in the
    /// right panel (SC1, SC4, SC5, SC8).
    func testPhotographTheScore() throws {
        app = XCUIApplication()
        app.launchArguments = ["-resetViewPreferences", "-seedTestLibrary"]
        app.launch()
        var step = ""
        guard openTray(app, step: &step) != nil else { return XCTFail(step) }
        sleep(1)
        snap("score-reading")
        app.buttons["score-more"].tap(); sleep(1); snap("score-more-panel")
        let export = app.descendants(matching: .any)["more-export"].firstMatch
        if export.exists { export.tap(); sleep(1); snap("score-export-panel") }
        let bar = app.buttons["score-title"]
        app.buttons["panel-done"].firstMatch.tap(); settle(bar, still: 0.8)
        if app.buttons["score-ask"].exists {
            app.buttons["score-ask"].tap(); sleep(1); snap("score-chat-panel")
            app.buttons["panel-done"].firstMatch.tap(); settle(bar, still: 0.8)
        }
        bar.tap(); sleep(1); snap("score-versions-panel")
        app.buttons["panel-done"].firstMatch.tap(); settle(bar, still: 0.8)
        let add = app.buttons["score-add-setlist"]
        if add.exists { add.tap(); sleep(1); snap("score-setlists-panel"); app.buttons["panel-done"].firstMatch.tap() }
    }
}

extension NotebookShot {
    /// Settings as a split (T1–T10), the Filter panel's groups (L4), and an
    /// arrangement's Details with Tags (A3).
    func testPhotographSettingsFilterAndDetails() throws {
        app = XCUIApplication()
        app.launchArguments = ["-resetViewPreferences", "-seedTestLibrary"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 240)
        waitForTheLibraryToSettle(app)
        let row = app.descendants(matching: .any)["row-sous-le-ciel-de-paris"]
        _ = row.waitForExistence(timeout: 60)
        settle(row, still: 0.6)

        app.buttons["library-filter"].tap(); sleep(1); snap("library-filter-panel")
        app.buttons["panel-done"].firstMatch.tap(); settle(row, still: 0.6)

        app.buttons["library-settings"].tap(); sleep(1); snap("settings-reading")
        let engine = app.buttons["settings-engine"]
        if engine.waitForExistence(timeout: 5) { engine.tap(); sleep(1); snap("settings-engine") }
        let account = app.buttons["settings-account"]
        if account.exists { account.tap(); sleep(1); snap("settings-account") }
        app.buttons["Close settings"].firstMatch.tap(); settle(row, still: 0.6)

        app.buttons["row-menu-sous-le-ciel-de-paris"].firstMatch.tap(); sleep(1)
        let arrangements = app.descendants(matching: .any)["row-arrangements-sous-le-ciel-de-paris"].firstMatch
        if arrangements.waitForExistence(timeout: 5) {
            arrangements.tap(); sleep(1)
            let pieceScreen = app.descendants(matching: .any)["piece-screen-sous-le-ciel-de-paris"].firstMatch
            if pieceScreen.waitForExistence(timeout: 5) {
                pieceScreen.tap(); sleep(2)
                let menu = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-menu-")).firstMatch
                menu.tap(); sleep(1)
                let manage = app.descendants(matching: .any).matching(
                    NSPredicate(format: "identifier BEGINSWITH %@", "arrangement-manage-")).firstMatch
                if manage.waitForExistence(timeout: 5) {
                    manage.tap(); sleep(1); snap("arrangement-panel")
                    let details = app.descendants(matching: .any).matching(
                        NSPredicate(format: "identifier BEGINSWITH %@", "row-details-")).firstMatch
                    if details.exists { details.tap(); sleep(1); snap("arrangement-details-panel") }
                }
            }
        }
    }
}
