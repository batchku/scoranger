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
