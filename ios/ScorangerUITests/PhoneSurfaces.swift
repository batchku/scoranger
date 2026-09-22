import XCTest

/// What 0.8.0 said the phone did not have, asserted (Ph2, Ph4).
///
/// These are not screenshots -- `PhoneShot` takes those. Each of these fails
/// if the behaviour goes, and the first two failed before this build:
///
///   - opening a set list on a phone showed "This set list" and NOT the set
///     list. The panel at rest was pushed over the page it belongs beside,
///     so the running order, the title and Play were all behind it;
///   - the score bar had no layout control, no Perform and no + at reading
///     width, because they were the last four steps of its yield order.
///
/// Run on a PHONE destination. On an iPad the size class is regular, the
/// foot strip is not drawn and the second row is not asked for, so each of
/// these skips rather than asserting something false about the wrong device.
final class PhoneSurfaces: XCTestCase {
    var app: XCUIApplication!

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// True on a phone. Read off the app rather than off the test's own idea
    /// of the device: what decides both surfaces is the horizontal size
    /// class, and an iPad in Slide Over is compact too.
    private var isCompactLayout: Bool {
        app.descendants(matching: .any)["page-foot-strip"].exists
            || app.descendants(matching: .any)["score-second-row"].exists
    }

    private func openTheSetList() -> Bool {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-resetViewPreferences", "-seedTestLibrary"]
        app.launch()
        _ = element("library-search").waitForExistence(timeout: 240)
        waitForTheLibraryToSettle(app)
        app.buttons["segment-setlists"].tap()
        let menu = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "row-menu-")).firstMatch
        guard menu.waitForExistence(timeout: 30) else { return false }
        menu.tap()
        let screen = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "row-setlist-screen-")).firstMatch
        guard screen.waitForExistence(timeout: 10) else { return false }
        screen.tap()
        return element("setlist-title").waitForExistence(timeout: 30)
            || app.buttons["setlist-play"].waitForExistence(timeout: 30)
    }

    /// The page is the page. Nothing the reader did not ask for covers it.
    func testASetListOnAPhoneShowsTheSetList() {
        guard openTheSetList() else { return XCTFail("the set list never opened") }
        guard isCompactLayout else {
            return print("SKIP: regular width -- the tools are the panel beside the page")
        }
        XCTAssertTrue(app.buttons["setlist-play"].exists,
                      "Play is behind something: the page is covered")
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "setlist-member-")).count > 0,
                      "no member rows: the running order is covered")
        XCTAssertFalse(app.buttons["panel-done"].exists,
                       "a panel opened over the set list without being asked for")
    }

    /// And its own tools are on one line at its foot, each reaching the page
    /// the iPad reaches in the panel.
    func testTheFootStripCarriesTheSetListsTools() {
        guard openTheSetList() else { return XCTFail("the set list never opened") }
        guard isCompactLayout else { return print("SKIP: regular width") }
        for tool in ["setlist-tool-add", "setlist-tool-share", "setlist-tool-more"] {
            XCTAssertTrue(element(tool).exists, "no \(tool) on the foot strip")
        }
        // Add reaches the same Add the panel reaches.
        element("setlist-tool-add").tap()
        XCTAssertTrue(element("panel-title").waitForExistence(timeout: 10),
                      "Add opened nothing")
        XCTAssertEqual(element("panel-title").label, "Add",
                       "Add on the strip led somewhere else")
        app.buttons["panel-done"].firstMatch.tap()
        // And More reaches the rest state, which is where Delete lives.
        XCTAssertTrue(element("setlist-tool-more").waitForExistence(timeout: 10))
        element("setlist-tool-more").tap()
        XCTAssertTrue(element("panel-title").waitForExistence(timeout: 10),
                      "More opened nothing")
        XCTAssertEqual(element("panel-title").label, "This set list")
    }

    /// The bar hands three controls to a row over the tray, and keeps the
    /// pencil it used to give up for them.
    func testTheScoreBarsSecondRowCarriesLayoutPerformAndAdd() {
        app = XCUIApplication()
        app.launchArguments = ["-resetViewPreferences", "-seedTestLibrary"]
        app.launch()
        _ = element("library-search").waitForExistence(timeout: 240)
        waitForTheLibraryToSettle(app)
        let row = element("row-sous-le-ciel-de-paris")
        guard row.waitForExistence(timeout: 120) else { return XCTFail("no piece row") }
        row.tap()
        let choice = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "arrangement-choice-")).firstMatch
        guard choice.waitForExistence(timeout: 60) else { return XCTFail("no arrangement") }
        settle(choice)
        choice.tap()
        guard app.buttons["score-title"].waitForExistence(timeout: 240) else {
            return XCTFail("the score never opened")
        }
        let page = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "canvas-")).firstMatch
        _ = page.waitForExistence(timeout: 180)
        settle(page, still: 0.6)

        guard element("score-second-row").exists else {
            return print("SKIP: regular width -- the bar seats all three itself")
        }
        let bar = app.buttons["score-close"].frame
        for control in ["layout-page", "layout-continuous", "score-performance"] {
            let item = app.buttons[control].firstMatch
            XCTAssertTrue(item.exists, "no \(control) anywhere")
            XCTAssertGreaterThan(item.frame.minY, bar.maxY,
                                 "\(control) is still on the bar, not in the second row")
        }
        // What the phone gets for it.
        XCTAssertTrue(app.buttons["score-edit"].exists,
                      "the pencil should be back on the bar now the cells have left it")
        XCTAssertTrue(element("score-select").exists, "⌖ must never yield")
        // And the row's controls WORK, not merely exist.
        app.buttons["layout-continuous"].firstMatch.tap()
        XCTAssertTrue(app.buttons["layout-continuous"].firstMatch
            .waitForExistence(timeout: 10))
    }
}
