import XCTest

/// The phone's own pages, photographed at iPhone size (Ph1–Ph6).
///
/// 0.8.0 landed the panel as a page on the phone and said, before it shipped,
/// that the set list's foot strip and the score bar's second row were not in
/// it. This is where those two are looked at: a screenshot cannot fail a
/// build, and the two tests beside it that CAN are `SetlistFootStrip` and
/// `ScoreSecondRow`.
///
/// Run on a phone destination -- on an iPad every frame here is the regular
/// layout and says nothing.
final class PhoneShot: XCTestCase {
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

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// The library, a set list with its foot strip, and a book row's actions.
    func testPhotographThePhoneLibrary() throws {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-resetViewPreferences",
                               "-seedTestLibrary", "-seedBigBook"]
        app.launch()
        _ = element("library-search").waitForExistence(timeout: 240)
        waitForTheLibraryToSettle(app)
        sleep(1)
        snap("phone-library")

        app.buttons["segment-setlists"].tap(); sleep(1)
        snap("phone-setlists")
        let menu = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "row-menu-")).firstMatch
        if menu.waitForExistence(timeout: 10) {
            menu.tap(); sleep(1)
            let screen = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "row-setlist-screen-")).firstMatch
            if screen.exists {
                screen.tap(); sleep(2)
                snap("phone-setlist-screen")
                // The foot strip's four, each pushing its page.
                for tool in ["setlist-tool-add", "setlist-tool-more"] {
                    let button = element(tool)
                    if button.exists {
                        button.tap(); sleep(1); snap("phone-\(tool)")
                        let back = app.buttons["panel-back"].firstMatch
                        if back.exists { back.tap() } else if app.buttons["panel-done"].firstMatch.exists {
                            app.buttons["panel-done"].firstMatch.tap()
                        }
                        sleep(1)
                    }
                }
            }
        }

        // Back to the library for the books segment.
        while app.buttons["screen-back"].firstMatch.exists {
            app.buttons["screen-back"].firstMatch.tap(); sleep(1)
        }
        // A book row, whose actions gained Rename in 0.8.2.
        guard app.buttons["segment-books"].firstMatch.waitForExistence(timeout: 20) else {
            return snap("phone-lost-the-library")
        }
        app.buttons["segment-books"].firstMatch.tap(); sleep(1)
        snap("phone-books")
        let bookMenu = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "row-menu-")).firstMatch
        if bookMenu.waitForExistence(timeout: 10) {
            bookMenu.tap(); sleep(1); snap("phone-book-row-actions")
            let rename = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "row-rename-")).firstMatch
            if rename.exists { rename.tap(); sleep(1); snap("phone-book-rename") }
        }
    }

    /// The score on a phone: the bar, the second row over the tray, More, and
    /// Settings as a split inside the panel.
    func testPhotographThePhoneScore() throws {
        app = XCUIApplication()
        app.launchArguments = ["-resetViewPreferences", "-seedTestLibrary"]
        app.launch()
        _ = element("library-search").waitForExistence(timeout: 240)
        waitForTheLibraryToSettle(app)
        let row = element("row-sous-le-ciel-de-paris")
        guard row.waitForExistence(timeout: 120) else { return XCTFail("no piece row") }
        row.tap(); sleep(2)
        snap("phone-piece-arrangements-panel")
        let choice = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "arrangement-choice-")).firstMatch
        guard choice.waitForExistence(timeout: 60) else { return XCTFail("no arrangement to open") }
        settle(choice)
        choice.tap()
        guard app.buttons["score-title"].waitForExistence(timeout: 240) else {
            return XCTFail("the score never opened")
        }
        let page = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "canvas-")).firstMatch
        _ = page.waitForExistence(timeout: 180)
        settle(page, still: 0.8)
        sleep(1)
        snap("phone-score")

        app.buttons["score-more"].tap(); sleep(1)
        snap("phone-score-more")
        let settings = element("more-settings")
        if settings.exists {
            settings.tap(); sleep(2)
            snap("phone-score-settings-index")
            let engine = app.buttons["settings-engine"].firstMatch
            if engine.waitForExistence(timeout: 5) {
                engine.tap(); sleep(1); snap("phone-score-settings-engine")
            }
        }
    }
}
