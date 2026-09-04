import XCTest

/// Untracked QA scaffolding for the designer's sweep: photograph the library's
/// states so the fixes can be looked at rather than assumed.
final class RowShot: XCTestCase {

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testLibraryRows() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedTestLibrary"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 60)
        sleep(2)
        snap(app, "pieces")
        if app.buttons["library-sort"].waitForExistence(timeout: 10) {
            app.buttons["library-sort"].tap()
            sleep(1)
            snap(app, "sort-reveal")
            app.buttons["library-sort"].tap()
        }
        if app.buttons["library-filter"].exists {
            app.buttons["library-filter"].tap()
            sleep(1)
            snap(app, "filter-reveal")
        }
        let setlists = app.descendants(matching: .any)["segment-setlists"].firstMatch
        if setlists.exists, setlists.isHittable {
            setlists.tap(); sleep(2); snap(app, "setlists")
        }
    }

    /// The first screen a new user sees.
    func testEmptyLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetLibrary"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 60)
        sleep(3)
        snap(app, "empty-pieces")
        let setlists = app.descendants(matching: .any)["segment-setlists"].firstMatch
        if setlists.exists, setlists.isHittable {
            setlists.tap(); sleep(1); snap(app, "empty-setlists")
        }
    }
}

extension RowShot {
    /// The title switcher band: how tall it is, and what its version rows say.
    func testTitleBand() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 60)
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-")).firstMatch
        guard row.waitForExistence(timeout: 60) else { return XCTFail("no row") }
        row.tap()
        if app.buttons["score-title"].waitForExistence(timeout: 5) == false {
            let choice = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                      "arrangement-choice-")).firstMatch
            if choice.waitForExistence(timeout: 20) { choice.tap() }
        }
        guard app.buttons["score-title"].waitForExistence(timeout: 180) else {
            return XCTFail("the score never engraved")
        }
        sleep(5)
        snap(app, "score-top-bar")
        app.buttons["score-title"].tap()
        sleep(2)
        let band = app.descendants(matching: .any)["menu-version-v001"].firstMatch
        print("BAND version row frame: \(band.exists ? "\(band.frame)" : "absent")")
        print("BAND canvas: \(app.scrollViews["score-canvas"].frame)")
        snap(app, "title-band")
    }

    override func tearDown() {
        // whatever this test did, the next suite starts upright
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }
}

extension RowShot {
    /// L22/#40/L23: what Edit mode does to a row.
    func testEditMode() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedTestLibrary"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 60)
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-"))
            .firstMatch
        guard row.waitForExistence(timeout: 60) else { return XCTFail("no row") }
        print("EDIT row before: \(row.frame)")
        snap(app, "rows-plain")
        app.buttons["library-edit"].tap()
        sleep(2)
        print("EDIT row after:  \(row.frame)")
        let menu = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-menu-")).firstMatch
        print("EDIT menu in edit mode: \(menu.exists ? "present \(menu.frame)" : "ABSENT")")
        for id in ["edit-versions-", "edit-setlists-", "edit-delete-"] {
            let n = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", id)).count
            print("EDIT per-row \(id): \(n)")
        }
        snap(app, "rows-editing")
        row.tap()
        sleep(1)
        snap(app, "rows-editing-selected")
    }
}

extension RowShot {
    /// L29/L30/L31/L32: the chat panel.
    func testChatPanel() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedTestLibrary"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 60)
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-sous")).firstMatch
        guard row.waitForExistence(timeout: 60) else { return XCTFail("no row") }
        row.tap()
        if app.buttons["score-title"].waitForExistence(timeout: 5) == false {
            let choice = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                      "arrangement-choice-")).firstMatch
            if choice.waitForExistence(timeout: 20) { choice.tap() }
        }
        guard app.scrollViews["score-canvas"].waitForExistence(timeout: 180) else {
            return XCTFail("never engraved")
        }
        sleep(5)
        app.buttons["score-ask"].tap()
        sleep(3)
        let input = app.descendants(matching: .any)["chat-input"].firstMatch
        print("CHAT input: \(input.exists ? "\(input.frame)" : "absent")")
        print("CHAT send: \(app.buttons["chat-send"].exists ? "\(app.buttons["chat-send"].frame)" : "absent")")
        print("CHAT model chip: \(app.buttons["chat-model"].exists ? "\(app.buttons["chat-model"].frame)" : "absent")")
        snap(app, "chat-open")
    }
}

extension RowShot {
    /// L34/L33/L13/#41/L12: options rows, the toggle, the index header.
    func testOptionsAndHeader() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedTestLibrary"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 60)
        sleep(2)
        snap(app, "library-header")
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-sous")).firstMatch
        guard row.waitForExistence(timeout: 60) else { return XCTFail("no row") }
        row.tap()
        if app.buttons["score-title"].waitForExistence(timeout: 5) == false {
            let choice = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                      "arrangement-choice-")).firstMatch
            if choice.waitForExistence(timeout: 20) { choice.tap() }
        }
        guard app.buttons["score-title"].waitForExistence(timeout: 180) else {
            return XCTFail("never engraved")
        }
        sleep(4)
        snap(app, "score-subtitle")
        app.buttons["score-more"].tap()
        sleep(2)
        // "Score display" is gone (0.6.3 #6) and the transport switch that
        // replaced it here went to the top bar (0.6.8), so the first row of the
        // options root is Chord symbols -- which is what this photographs. It
        // is the ROW's geometry that matters, not which row it is.
        let display = app.descendants(matching: .any)["more-chords"].firstMatch
        print("OPTIONS row frame: \(display.exists ? "\(display.frame)" : "absent")")
        snap(app, "score-options")
    }
}

extension RowShot {
    /// #47-#53: the pared-back library bar, the stamp, and Settings as a panel.
    func testLibraryBarAndSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedTestLibrary"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 60)
        sleep(3)
        for id in ["library-ask", "library-engine-chip"] {
            print("BAR \(id): \(app.descendants(matching: .any)[id].exists ? "STILL THERE" : "gone")")
        }
        print("BAR help: \(app.buttons["Help"].exists ? "STILL THERE" : "gone")")
        print("BAR inbox: \(app.buttons["Inbox"].exists ? "STILL THERE" : "gone")")
        print("BAR gear: \(app.buttons["library-settings"].exists ? "present" : "MISSING")")
        print("BAR stamp: \(app.staticTexts["build-stamp"].exists ? "present" : "MISSING")")
        snap(app, "library-bar")
        app.buttons["library-settings"].tap()
        sleep(2)
        print("SETTINGS panel: \(app.descendants(matching: .any)["settings-panel"].exists ? "present" : "MISSING")")
        snap(app, "settings-panel")
        app.buttons["Close settings"].tap()
        sleep(3)
        print("SETTINGS after close, app state: \(app.state.rawValue)")
        print("SETTINGS library still there: \(app.descendants(matching: .any)["library-search"].exists)")
    }
}

extension RowShot {
    func testSpreadToggleFromLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedTestLibrary", "-annotateWithFinger", "-uiTestPencil"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 60)
        sleep(2)
        app.buttons["library-settings"].tap()
        // the spread toggle became one cell of the three-way layout control
        let toggle = app.switches["Two pages"]
        guard toggle.waitForExistence(timeout: 10) else { return XCTFail("no toggle") }
        print("SPREADTEST before: \(String(describing: toggle.value))")
        if (toggle.value as? String) != "1" { toggle.tap() }
        sleep(2)
        print("SPREADTEST after tap, app=\(app.state.rawValue) value=\(String(describing: toggle.value))")
        app.buttons["Close settings"].tap()
        sleep(3)
        print("SPREADTEST after close, app=\(app.state.rawValue)")
        print("SPREADTEST library there: \(app.descendants(matching: .any)["library-search"].exists)")
        snap(app, "after-spread-toggle")
        // and then open a score in spread, which is where the suite died
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-sous")).firstMatch
        if row.waitForExistence(timeout: 10) { row.tap() }
        let choice = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                  "arrangement-choice-")).firstMatch
        if choice.waitForExistence(timeout: 10) { choice.tap() }
        print("SPREADTEST opening, app=\(app.state.rawValue)")
        let ok = app.scrollViews["score-canvas"].waitForExistence(timeout: 180)
        print("SPREADTEST canvas=\(ok) app=\(app.state.rawValue)")
        sleep(8)
        print("SPREADTEST settled app=\(app.state.rawValue)")
        snap(app, "spread-open")
    }
}

extension RowShot {
    /// What Import does now: straight to the system picker.
    func testImportOpensThePicker() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedTestLibrary"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 60)
        sleep(2)
        app.buttons["library-import"].tap()
        sleep(4)
        for probe in ["Cancel", "Browse", "Recents", "Files", "Open"] {
            print("PICKER button[\(probe)] = \(app.buttons[probe].exists)")
        }
        print("PICKER navbars = \(app.navigationBars.count)")
        print("PICKER sheets = \(app.sheets.count)")
        print("PICKER any-name-field = \(app.textFields["inline-rename-field"].exists)")
        print("PICKER back-button = \(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Back to")).count)")
        snap(app, "import-tapped")
    }
}
