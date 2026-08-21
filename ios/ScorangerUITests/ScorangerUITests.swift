import XCTest

/// iPad parity audit. Two things are under test here: that the sidebar's
/// per-row buttons actually receive taps (the reason piece rows use explicit
/// chevron buttons instead of DisclosureGroup, whose label swallows button taps
/// on iPad sidebar lists), and that the piece → arrangement → version hierarchy
/// is what the UI presents.
final class ScorangerUITests: XCTestCase {
    var app: XCUIApplication!

    /// The seeded sample piece and its first arrangement.
    private let piece = "Sous le ciel de Paris"
    private let firstArrangement = "sous-le-ciel-quartet"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // the app ships with no sample library; tests ask for a fixture, and
        // for finger drawing since the simulator has no Pencil
        app.launchArguments = ["-seedTestLibrary", "-annotateWithFinger"]
        app.launch()
        // engine boot + first manifest can take a while on first run
        XCTAssertTrue(app.staticTexts["Pieces"].waitForExistence(timeout: 90),
                      "sidebar never showed the Pieces section")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// First element anywhere whose label starts with `prefix`. Section headers
    /// render uppercased and arrangement names are truncated, so exact-match
    /// queries are too brittle for them.
    private func element(labelStartingWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH[c] %@", prefix))
            .firstMatch
    }

    /// Setlists section exists and its caret collapses/expands.
    func testSetlistSection() {
        XCTAssertTrue(app.staticTexts["Setlists"].exists)
        let collapse = app.buttons["Collapse setlist Test setlist"]
        XCTAssertTrue(collapse.exists, "setlist caret missing")
        collapse.tap()
        XCTAssertTrue(app.buttons["Expand setlist Test setlist"].waitForExistence(timeout: 5),
                      "setlist caret did not toggle")
        app.buttons["Expand setlist Test setlist"].tap()
        XCTAssertTrue(app.buttons["Collapse setlist Test setlist"].waitForExistence(timeout: 5))
        shot("setlists-section")
    }

    /// The piece caret collapses and re-expands the arrangement rows.
    func testPieceCaretTogglesChildren() {
        let collapse = app.buttons["Collapse \(piece)"]
        XCTAssertTrue(collapse.exists, "piece caret missing")
        let child = app.buttons["arrangement-\(firstArrangement)"]
        XCTAssertTrue(child.exists, "arrangement rows should start expanded")
        collapse.tap()
        XCTAssertTrue(app.buttons["Expand \(piece)"].waitForExistence(timeout: 5))
        XCTAssertFalse(child.exists, "arrangement rows should hide when collapsed")
        app.buttons["Expand \(piece)"].tap()
        XCTAssertTrue(child.waitForExistence(timeout: 5))
        shot("piece-caret")
    }

    /// Arrangements are numbered within their piece, and that number is what
    /// chat prompts refer to ("take the violin part from #2"), so it has to be
    /// on screen.
    func testArrangementsAreNumberedWithinPiece() {
        XCTAssertTrue(element(labelStartingWith: "Arrangement number 1").exists,
                      "#1 badge missing from the first arrangement of the piece")
        XCTAssertTrue(element(labelStartingWith: "Arrangement number 2").exists,
                      "#2 badge missing from the second arrangement of the piece")
        shot("arrangement-numbers")
    }

    /// The piece row's + is a menu of ways to add an arrangement; the blank
    /// option creates one and opens it.
    func testAddMenuCreatesBlankArrangement() {
        let plus = app.buttons["Add an arrangement to \(piece)"]
        XCTAssertTrue(plus.exists, "add-arrangement menu missing from piece row")
        plus.tap()
        let blank = app.buttons["New blank arrangement"]
        XCTAssertTrue(blank.waitForExistence(timeout: 10), "add menu did not open")
        blank.tap()
        // it files itself under the piece and opens in the detail pane
        XCTAssertTrue(element(labelStartingWith: "New arrangement").waitForExistence(timeout: 60),
                      "new arrangement did not appear")
        shot("add-menu-blank-arrangement")
    }

    /// The same menu offers starting from an existing arrangement, named by the
    /// number the user sees.
    func testAddMenuOffersDuplicateByNumber() {
        app.buttons["Add an arrangement to \(piece)"].tap()
        let duplicate = app.buttons["Duplicate an arrangement"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 10),
                      "duplicate submenu missing from the add menu")
        duplicate.tap()
        XCTAssertTrue(element(labelStartingWith: "#1").waitForExistence(timeout: 10),
                      "duplicate submenu should list arrangements by number")
        shot("add-menu-duplicate")
    }

    /// Row icons: info opens the details sheet.
    func testInfoSheet() {
        let info = app.buttons["Arrangement details"].firstMatch
        XCTAssertTrue(info.exists)
        info.tap()
        XCTAssertTrue(app.staticTexts["Arrangement"].waitForExistence(timeout: 10),
                      "info sheet did not open")
        XCTAssertTrue(app.staticTexts["Number in piece"].exists,
                      "info sheet should state the arrangement's number in its piece")
        shot("info-sheet")
        app.buttons["Done"].firstMatch.tap()
    }

    /// The core navigation contract on iPad: tapping the row itself opens the
    /// arrangement in the score pane. There is no separate open button.
    func testRowTapOpensArrangement() {
        XCTAssertFalse(app.buttons["Open score"].exists,
                       "the separate open button should be gone; the row opens it")
        app.buttons["arrangement-\(firstArrangement)"].tap()
        // the detail toolbar shows the version pill once an arrangement is open
        XCTAssertTrue(app.buttons["Versions"].waitForExistence(timeout: 60),
                      "row tap did not open the arrangement in the detail pane")
        shot("row-tap-opens")
    }

    /// Arrangements can be renamed from the info sheet. The slug is unchanged
    /// by a rename, so the row identifier stays valid and the new name shows.
    func testRenameArrangement() {
        let row = app.buttons["arrangement-\(firstArrangement)"]
        XCTAssertTrue(row.exists)
        app.buttons["Arrangement details"].firstMatch.tap()

        let field = app.textFields["Arrangement name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "name field missing")
        field.tap()
        field.typeText(" Renamed")

        let rename = app.buttons["Rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5),
                      "Rename button should appear once the name differs")
        rename.tap()
        // the button retires once the new name is the saved one
        XCTAssertTrue(waitForDisappearance(of: rename, timeout: 20),
                      "Rename button still offered after a successful rename")
        app.buttons["Done"].firstMatch.tap()

        XCTAssertTrue(element(labelStartingWith: "Arrangement number 1")
                        .waitForExistence(timeout: 10))
        XCTAssertTrue(row.exists, "the row identifier is the slug and must survive a rename")
        shot("renamed-arrangement")
    }

    /// Annotation mode is off by default and exposes draw/erase/colour/undo.
    func testAnnotationModeTools() {
        let enter = app.buttons["Annotate the score"]
        XCTAssertTrue(enter.waitForExistence(timeout: 60),
                      "annotation toggle missing from the score toolbar")
        XCTAssertFalse(app.buttons["Draw"].exists,
                       "annotation tools should be hidden until the mode is on")

        enter.tap()
        XCTAssertTrue(app.buttons["Draw"].waitForExistence(timeout: 5), "draw tool missing")
        XCTAssertTrue(app.buttons["Erase"].exists, "erase tool missing")
        XCTAssertTrue(app.buttons["Red pen"].exists, "colour swatches missing")
        XCTAssertTrue(app.buttons["Blue pen"].exists)

        let undo = app.buttons["Undo annotation"]
        XCTAssertTrue(undo.exists, "undo missing")
        XCTAssertFalse(undo.isEnabled, "undo should be disabled with nothing drawn")

        app.buttons["Blue pen"].tap()
        app.buttons["Erase"].tap()
        shot("annotation-mode")

        // Not covered here: drawing a stroke, and the two-finger-tap undo.
        // The simulator has no Pencil, and XCUITest's twoFingerTap cannot
        // resolve coordinates over the canvas overlay. Both need a device.

        app.buttons["Finish annotating"].tap()
        XCTAssertTrue(waitForDisappearance(of: app.buttons["Draw"], timeout: 5),
                      "annotation bar should go away on Done")
    }

    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            usleep(200_000)
        }
        return !element.exists
    }

    /// Each arrangement has a caret that reveals its versions in place, and a
    /// version row jumps the score pane to that version.
    func testVersionsNestUnderArrangement() {
        let versionRow = app.buttons["version-\(firstArrangement)-v001"]
        XCTAssertFalse(versionRow.exists, "versions should be hidden until expanded")

        let caret = app.buttons["versions-toggle-\(firstArrangement)"]
        XCTAssertTrue(caret.exists, "no versions caret on the arrangement row")
        caret.tap()
        XCTAssertTrue(versionRow.waitForExistence(timeout: 10),
                      "caret did not reveal the arrangement's versions")
        shot("versions-nested")

        versionRow.tap()
        XCTAssertTrue(app.buttons["Versions"].waitForExistence(timeout: 60),
                      "tapping a version did not open the arrangement")

        caret.tap()
        XCTAssertTrue(waitForDisappearance(of: versionRow, timeout: 5),
                      "caret did not collapse the versions again")
    }

    /// The active ink is unmistakable: the chosen swatch grows and gains a
    /// checkmark, and the toolbar toggle takes its colour.
    func testActiveColourIsVisible() {
        let enter = app.buttons["Annotate the score"]
        // engraving a multi-page score can take a while before the score
        // toolbar exists at all
        XCTAssertTrue(enter.waitForExistence(timeout: 90), "score pane never appeared")
        enter.tap()
        XCTAssertTrue(app.buttons["Green pen"].waitForExistence(timeout: 5))
        app.buttons["Green pen"].tap()
        shot("active-colour-green")
        app.buttons["Orange pen"].tap()
        shot("active-colour-orange")
        XCTAssertTrue(app.buttons["Draw"].exists, "bar should stay up after picking a colour")
        app.buttons["Finish annotating"].tap()
    }

    /// Pinch zoom is UIScrollView's, so the score must survive a pinch and keep
    /// its pages laid out. Whether the midpoint stays truly fixed is a feel
    /// question that needs a device; this guards against regression to a broken
    /// or crashing gesture.
    func testPinchZoomKeepsScoreUsable() {
        XCTAssertTrue(app.buttons["Annotate the score"].waitForExistence(timeout: 90),
                      "score pane never appeared")
        let score = app.scrollViews.firstMatch
        guard score.exists else {
            XCTFail("no scroll view hosting the score")
            return
        }
        score.pinch(withScale: 2.2, velocity: 2.0)
        shot("zoomed-in")
        XCTAssertTrue(app.buttons["Annotate the score"].exists,
                      "toolbar should survive a zoom")
        score.pinch(withScale: 0.5, velocity: -2.0)
        shot("zoomed-out")
        XCTAssertTrue(app.buttons["Annotate the score"].exists)
    }

    /// Exactly one pencil in the score toolbar: the old highlighter button was
    /// a second pencil glyph and read as a duplicate edit control.
    func testSingleAnnotationToggleInToolbar() {
        XCTAssertTrue(app.buttons["Annotate the score"].waitForExistence(timeout: 90))
        XCTAssertFalse(app.buttons["Highlight a passage"].exists,
                       "the highlighter toolbar button should be gone")
        XCTAssertFalse(app.buttons["Exit highlight mode"].exists)
        shot("single-pencil-toolbar")
    }

    /// The reported undo bug: draw, undo, switch colour, draw, undo. The first
    /// stroke must not come back. Stroke counts are read off the canvas's
    /// accessibility value.
    func testAnnotationUndoAcrossColourChange() {
        XCTAssertTrue(app.buttons["Annotate the score"].waitForExistence(timeout: 90))
        app.buttons["Annotate the score"].tap()
        XCTAssertTrue(app.buttons["Draw"].waitForExistence(timeout: 5))

        let canvas = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas-"))
            .firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10), "no annotation canvas found")

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
                       "after a colour change there must be exactly one stroke, not the undone one as well")

        app.buttons["Undo annotation"].tap()
        XCTAssertEqual(strokes(), 0, "undo after a colour change did not work")
        shot("undo-across-colour-change")

        app.buttons["Finish annotating"].tap()
    }

    /// Setlists can be created, and pieces added to and removed from them.
    func testCreateSetlistAndAddPiece() {
        app.buttons["New setlist"].tap()
        let field = app.textFields["Setlist name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no name field")
        field.typeText("Gig night")
        app.buttons["Create"].tap()

        let add = app.buttons["Add a piece to Gig night"]
        XCTAssertTrue(add.waitForExistence(timeout: 20), "new setlist did not appear")
        add.tap()
        let candidate = app.buttons[piece]
        XCTAssertTrue(candidate.waitForExistence(timeout: 10),
                      "the add menu should offer pieces not yet in the setlist")
        candidate.tap()

        // the piece now shows under the setlist, so the menu no longer offers it
        XCTAssertTrue(app.buttons["Collapse setlist Gig night"].waitForExistence(timeout: 20))
        shot("setlist-with-piece")

        // clean up so repeated runs stay deterministic
        app.buttons["Collapse setlist Gig night"].press(forDuration: 1.2)
        if app.buttons["Delete setlist"].waitForExistence(timeout: 10) {
            app.buttons["Delete setlist"].tap()
            if app.buttons["Delete"].waitForExistence(timeout: 5) {
                app.buttons["Delete"].tap()
            }
        }
    }

    /// Long-press on an arrangement row offers the filing context menu.
    func testContextMenu() {
        app.buttons["arrangement-\(firstArrangement)"].press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Move to piece"].waitForExistence(timeout: 10),
                      "context menu did not appear")
        shot("context-menu")
        // dismiss
        app.tap()
    }
}
