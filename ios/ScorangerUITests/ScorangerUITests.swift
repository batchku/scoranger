import XCTest

/// iPad audit of the score-first layout. The split view is gone: the canvas is
/// the root, the library and chat are overlays, and every control lives in the
/// pill. These tests are written against that, and against the piece →
/// arrangement → version hierarchy the sidebar presents.
///
/// Fixtures come from engine/scripts/make_test_fixture.py via -seedTestLibrary;
/// -annotateWithFinger lets a finger draw, since the simulator has no Pencil.
final class ScorangerUITests: XCTestCase {
    var app: XCUIApplication!

    private let piece = "Sous le ciel de Paris"
    private let firstArrangement = "sous-le-ciel-quartet"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-seedTestLibrary", "-annotateWithFinger"]
        app.launch()
        // the library overlay starts open on iPad; band headers render uppercased
        XCTAssertTrue(app.staticTexts["PIECES"].waitForExistence(timeout: 90),
                      "the library overlay never showed its Pieces band")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(labelStartingWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH[c] %@", prefix))
            .firstMatch
    }

    private func waitForDisappearance(of element: XCUIElement,
                                      timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            usleep(200_000)
        }
        return !element.exists
    }

    // MARK: - The pill is the only chrome (§7.1)

    func testPillCarriesEveryControlAndThereIsNoNavigationBar() {
        XCTAssertTrue(app.buttons["pill-library"].exists, "no library toggle in the pill")
        XCTAssertTrue(app.buttons["pill-chat"].exists, "no chat toggle in the pill")
        XCTAssertTrue(app.buttons["pill-options"].exists, "no options menu in the pill")
        XCTAssertTrue(app.buttons["pill-markup"].exists, "no markup toggle in the pill")
        // the version chip replaces the old toolbar version picker
        XCTAssertTrue(app.buttons["pill-version"].exists, "no version chip in the pill")
        // nothing from the old split view survives
        XCTAssertFalse(app.navigationBars.element.exists,
                       "the score-first layout has no navigation bar")
        shot("pill-and-canvas")
    }

    func testLibraryOverlayTogglesFromThePill() {
        let library = app.buttons["pill-library"]
        XCTAssertTrue(app.staticTexts["PIECES"].exists)
        library.tap()
        XCTAssertTrue(waitForDisappearance(of: app.staticTexts["PIECES"], timeout: 5),
                      "the library did not close")
        library.tap()
        XCTAssertTrue(app.staticTexts["PIECES"].waitForExistence(timeout: 5),
                      "the library did not reopen")
    }

    func testChatOverlayOpensFromThePill() {
        app.buttons["pill-chat"].tap()
        XCTAssertTrue(app.buttons["Close chat"].waitForExistence(timeout: 10),
                      "the chat overlay did not open")
        // the primer and the input are the panel's own, not a system sheet
        XCTAssertTrue(app.textFields["Arrange…"].exists || app.buttons["Send"].exists,
                      "the chat input is missing")
        shot("chat-overlay")
        app.buttons["Close chat"].tap()
        XCTAssertTrue(waitForDisappearance(of: app.buttons["Close chat"], timeout: 5))
    }

    // MARK: - Hierarchy

    func testArrangementsAreNumberedWithinPiece() {
        XCTAssertTrue(element(labelStartingWith: "Arrangement number 1").exists)
        XCTAssertTrue(element(labelStartingWith: "Arrangement number 2").exists)
        shot("numbered-arrangements")
    }

    func testPieceCaretTogglesChildren() {
        let collapse = app.buttons["Collapse \(piece)"]
        XCTAssertTrue(collapse.exists, "piece caret missing")
        let child = app.buttons["arrangement-\(firstArrangement)"]
        XCTAssertTrue(child.exists, "arrangement rows should start expanded")
        collapse.tap()
        XCTAssertTrue(app.buttons["Expand \(piece)"].waitForExistence(timeout: 5))
        XCTAssertFalse(child.exists)
        app.buttons["Expand \(piece)"].tap()
        XCTAssertTrue(child.waitForExistence(timeout: 5))
    }

    func testRowTapOpensArrangement() {
        app.buttons["arrangement-\(firstArrangement)"].tap()
        // the pill's version chip tracks whatever is open
        XCTAssertTrue(app.buttons["pill-version"].waitForExistence(timeout: 60),
                      "row tap did not open an arrangement")
    }

    func testVersionsNestUnderArrangement() {
        let versionRow = app.buttons["version-\(firstArrangement)-v001"]
        XCTAssertFalse(versionRow.exists, "versions should be hidden until expanded")
        let caret = app.buttons["versions-toggle-\(firstArrangement)"]
        XCTAssertTrue(caret.exists, "no versions caret on the arrangement row")
        caret.tap()
        XCTAssertTrue(versionRow.waitForExistence(timeout: 10),
                      "caret did not reveal the versions")
        shot("nested-versions")
        caret.tap()
        XCTAssertTrue(waitForDisappearance(of: versionRow, timeout: 5))
    }

    func testPromptGroupStepsExpand() {
        app.buttons["versions-toggle-\(firstArrangement)"].tap()
        let stepsToggle = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                  "steps-toggle-\(firstArrangement)-"))
            .firstMatch
        XCTAssertTrue(stepsToggle.waitForExistence(timeout: 20),
                      "a multi-step prompt group should offer a caret")
        let step = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                  "step-\(firstArrangement)-"))
            .firstMatch
        XCTAssertFalse(step.exists, "steps hidden until the caret opens")
        stepsToggle.tap()
        XCTAssertTrue(step.waitForExistence(timeout: 10),
                      "the caret did not reveal the intermediate versions")
        shot("prompt-group-steps")
    }

    // MARK: - Panel dialogs (§7.15, §7.16)

    func testArrangementSheetIsAPanelWithRenameAndDeleteLast() {
        app.buttons["Arrangement details"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["ARRANGEMENT"].waitForExistence(timeout: 10),
                      "the arrangement sheet did not open")
        XCTAssertTrue(app.staticTexts["SCORED FOR"].exists,
                      "the sheet should list what the arrangement is scored for")
        // destructive action sits in the body, last — never in the header
        XCTAssertTrue(app.staticTexts["DANGER"].exists)
        XCTAssertTrue(app.buttons["Delete arrangement…"].exists)
        shot("arrangement-sheet")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(waitForDisappearance(of: app.staticTexts["ARRANGEMENT"], timeout: 5))
    }

    func testRenameArrangementFromTheSheet() {
        app.buttons["Arrangement details"].firstMatch.tap()
        let field = app.textFields["Arrangement name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "name field missing")
        field.tap()
        field.typeText(" Renamed")
        let rename = app.buttons["Rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5),
                      "Rename should appear once the name differs")
        rename.tap()
        XCTAssertTrue(waitForDisappearance(of: rename, timeout: 20),
                      "Rename still offered after a successful save")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["arrangement-\(firstArrangement)"].exists,
                      "the slug-based identifier must survive a rename")
    }

    /// The alert is ours: a verb rather than OK, and a field in the body.
    func testNewSetlistUsesAPanelAlertWithAVerb() {
        app.buttons["New setlist"].tap()
        let field = app.textFields["Setlist name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no field in the naming alert")
        XCTAssertTrue(app.buttons["Create"].exists, "the verb should name the action")
        XCTAssertFalse(app.buttons["OK"].exists, "alerts never say OK")
        field.typeText("Gig night")
        shot("panel-alert")
        app.buttons["Create"].tap()

        let add = app.buttons["Add a piece to Gig night"]
        XCTAssertTrue(add.waitForExistence(timeout: 20), "the new setlist did not appear")
        add.tap()
        let candidate = app.buttons[piece]
        XCTAssertTrue(candidate.waitForExistence(timeout: 10))
        candidate.tap()
        XCTAssertTrue(app.buttons["Collapse setlist Gig night"].waitForExistence(timeout: 20))

        // clean up so repeat runs stay deterministic
        app.buttons["Collapse setlist Gig night"].press(forDuration: 1.2)
        if app.buttons["Delete setlist"].waitForExistence(timeout: 10) {
            app.buttons["Delete setlist"].tap()
            if app.buttons["Delete"].waitForExistence(timeout: 5) {
                app.buttons["Delete"].tap()
            }
        }
    }

    func testSettingsIsAPanelSheet() {
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["ON-DEVICE ENGINE"].waitForExistence(timeout: 10),
                      "settings did not open as a panel sheet")
        XCTAssertTrue(app.staticTexts["CHAT MODEL"].exists)
        shot("settings-sheet")
        app.buttons["Done"].firstMatch.tap()
    }

    // MARK: - Markup

    func testMarkupModeAndTheInkBar() {
        let markup = app.buttons["pill-markup"]
        XCTAssertTrue(markup.waitForExistence(timeout: 60))
        XCTAssertFalse(app.buttons["Draw"].exists, "the ink bar should be hidden")
        markup.tap()
        XCTAssertTrue(app.buttons["Draw"].waitForExistence(timeout: 5), "no ink bar")
        XCTAssertTrue(app.buttons["Erase"].exists)
        XCTAssertTrue(app.buttons["Red pen"].exists)
        XCTAssertFalse(app.buttons["Undo annotation"].isEnabled,
                       "undo should be disabled with nothing drawn")
        shot("ink-bar")
        app.buttons["Finish annotating"].tap()
        XCTAssertTrue(waitForDisappearance(of: app.buttons["Draw"], timeout: 5))
    }

    /// The build-116 bug: draw, undo, switch colour, draw, undo. The first
    /// stroke must not come back. Stroke counts are read off the canvas.
    func testAnnotationUndoAcrossColourChange() {
        XCTAssertTrue(app.buttons["pill-markup"].waitForExistence(timeout: 90),
                      "the markup toggle never appeared in the pill")
        app.buttons["pill-markup"].tap()
        XCTAssertTrue(app.buttons["Draw"].waitForExistence(timeout: 10),
                      "the ink bar did not open")

        let canvas = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas-"))
            .firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10), "no annotation canvas")

        func strokes() -> Int {
            Int((canvas.value as? String)?
                .replacingOccurrences(of: " strokes", with: "") ?? "-1") ?? -1
        }
        func draw() {
            let a = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.45))
            let b = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.45))
            a.press(forDuration: 0.05, thenDragTo: b)
        }

        XCTAssertEqual(strokes(), 0, "canvas should start empty")
        draw()
        XCTAssertEqual(strokes(), 1, "the stroke did not land")
        app.buttons["Undo annotation"].tap()
        XCTAssertEqual(strokes(), 0, "undo did not remove the stroke")
        app.buttons["Blue pen"].tap()
        draw()
        XCTAssertEqual(strokes(), 1,
                       "after a colour change there must be exactly one stroke")
        app.buttons["Undo annotation"].tap()
        XCTAssertEqual(strokes(), 0, "undo after a colour change did not work")
        app.buttons["Finish annotating"].tap()
    }

    func testPinchZoomKeepsScoreUsable() {
        let score = app.scrollViews.firstMatch
        guard score.exists else { return XCTFail("no scroll view hosting the score") }
        score.pinch(withScale: 2.2, velocity: 2.0)
        XCTAssertTrue(app.buttons["pill-library"].exists, "the pill should survive a zoom")
        score.pinch(withScale: 0.5, velocity: -2.0)
        XCTAssertTrue(app.buttons["pill-library"].exists)
    }

    // MARK: - Adding

    func testAddMenuCreatesBlankArrangement() {
        app.buttons["Add an arrangement to \(piece)"].tap()
        let blank = app.buttons["New blank arrangement"]
        XCTAssertTrue(blank.waitForExistence(timeout: 10), "add menu did not open")
        blank.tap()
        XCTAssertTrue(element(labelStartingWith: "Arrangement number 3")
                        .waitForExistence(timeout: 60),
                      "the new arrangement did not appear as #3 of the piece")
    }

    func testContextMenuOffersFilingAndDeletion() {
        app.buttons["arrangement-\(firstArrangement)"].press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Move to piece"].waitForExistence(timeout: 10),
                      "context menu did not appear")
        XCTAssertTrue(app.buttons["Delete arrangement"].exists)
        app.tap()
    }
}
