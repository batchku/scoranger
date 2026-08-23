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
        // -resetLibrary so each test starts from the same seeded library: these
        // tests rename things, and the on-device workspace outlives the app.
        // -lassoWithFinger: selection is finger-held + Pencil, and the
        // simulator has no Pencil. The stand-in lets a finger drag draw the
        // lasso so the rest of the path (hit-test, chip, chat handoff) is
        // covered end to end; the arbitration rule itself is unit-tested.
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary",
                               "-annotateWithFinger", "-lassoWithFinger"]
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

    /// Replace a field's whole contents.
    ///
    /// `typeText` inserts at the cursor and a tap puts the cursor wherever it
    /// landed, so appending is not setting. Command-A never reaches the
    /// simulator, and neither arrow keys nor backspace go through typeText on
    /// this OS — a triple tap selects the whole line the way a finger would,
    /// and typing then replaces the selection.
    private func replaceText(_ field: XCUIElement, with text: String) {
        field.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        field.typeText(text)
    }

    /// Poll a field's value: a write that goes through the engine lands a
    /// moment after the button that started it disappears.
    @discardableResult
    private func waitForValue(_ element: XCUIElement, _ expected: String,
                              timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (element.value as? String) == expected { return true }
            usleep(200_000)
        }
        return false
    }

    /// Poll an element's label: a reorder round-trips through the engine.
    private func waitForLabel(_ element: XCUIElement, contains text: String,
                              timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.label.contains(text) { return true }
            usleep(200_000)
        }
        return false
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

    /// The canvas must fill the gap the panels leave, in every combination.
    /// Build 119 capped the score pane to the spec's 520pt page width, which
    /// left dead bands beside the score and — because the pane is also the
    /// scroll view — put hard limits on how far zoom could pan. Asserted
    /// numerically because eyeballing missed it twice.
    func testCanvasFillsTheGapBesideThePanels() {
        let screen = app.windows.firstMatch.frame.width
        let library: CGFloat = 320
        let chat: CGFloat = 380
        // the score view only exists once an arrangement has engraved
        app.buttons["arrangement-\(firstArrangement)"].tap()
        let score = app.scrollViews["score-canvas"]
        XCTAssertTrue(score.waitForExistence(timeout: 180),
                      "the score never finished engraving")

        // the page itself, via the PencilKit canvas that overlays it: the
        // build-120 second defect was the canvas frame being right while the
        // page stayed centred on the region it had *before* a panel opened.
        let page = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas-"))
            .firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 30), "no page found in the canvas")

        func assertPageFillsCanvas(_ what: String) {
            XCTAssertEqual(page.frame.midX, score.frame.midX, accuracy: 6,
                           "page off-centre in the canvas with \(what): page "
                           + "\(page.frame) in canvas \(score.frame)")
            // 12pt of paper margin either side (ScorePagesView)
            XCTAssertEqual(page.frame.width, score.frame.width - 24, accuracy: 8,
                           "page does not fill the canvas with \(what): "
                           + "\(page.frame.width) of \(score.frame.width)")
        }

        func assertWidth(_ expected: CGFloat, _ what: String) {
            // a couple of points of slack for panel borders
            XCTAssertEqual(score.frame.width, expected, accuracy: 4,
                           "canvas width with \(what): expected ~\(expected), "
                           + "got \(score.frame.width) of \(screen) available")
        }

        // library open (the launch state), chat closed
        assertWidth(screen - library, "library open, chat closed")
        assertPageFillsCanvas("library open, chat closed")
        shot("width-library-open")

        app.buttons["pill-chat"].tap()
        XCTAssertTrue(app.buttons["Close chat"].waitForExistence(timeout: 10))
        sleep(1)
        assertWidth(screen - library - chat, "both panels open")
        assertPageFillsCanvas("both panels open")
        shot("width-both-open")

        app.buttons["pill-library"].tap()
        sleep(1)
        assertWidth(screen - chat, "library closed, chat open")
        assertPageFillsCanvas("library closed, chat open")
        shot("width-chat-only")

        app.buttons["Close chat"].tap()
        sleep(1)
        assertWidth(screen, "both panels closed")
        assertPageFillsCanvas("both panels closed")
        shot("width-none-open")
    }

    /// Zoomed in, the page has to be bigger than the region and pannable to
    /// both of its edges -- the build-120 symptom was hard left/right limits
    /// well inside the screen, because the scroll view itself was only 544pt
    /// wide. XCUITest's pinch under-delivers (a requested 2.5 lands near 1.2),
    /// so the canvas publishes its live zoom scale and the test pinches until
    /// it reads high enough.
    func testTheZoomedPageUsesTheWholeCanvas() {
        app.buttons["arrangement-\(firstArrangement)"].tap()
        let score = app.scrollViews["score-canvas"]
        XCTAssertTrue(score.waitForExistence(timeout: 180),
                      "the score never finished engraving")
        let page = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier ENDSWITH %@", "/p0"))
            .firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 30), "no first page")

        func scale() -> CGFloat {
            CGFloat(Double((score.value as? String)?
                .replacingOccurrences(of: "zoom ", with: "") ?? "0") ?? 0)
        }
        func zoom(toAtLeast target: CGFloat) -> CGFloat {
            // one pinch only multiplies the scale by ~1.15 however large the
            // requested factor, so this walks up to the target
            for _ in 0..<24 where scale() < target {
                score.pinch(withScale: 3.0, velocity: 2.0)
            }
            return scale()
        }

        // a drag rather than swipeLeft/Right: a flick's inertia makes "did we
        // reach the extreme" depend on how many flicks land before the
        // deceleration ends, which is not something to assert on
        func pan(from: CGFloat, to: CGFloat) {
            let a = score.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.5))
            let b = score.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.5))
            a.press(forDuration: 0.05, thenDragTo: b)
        }

        func checkRegion(_ what: String) {
            let z = zoom(toAtLeast: 1.8)
            XCTAssertGreaterThanOrEqual(z, 1.8, "could not zoom in (\(what))")
            let canvas = score.frame
            XCTAssertGreaterThan(page.frame.width, canvas.width,
                                 "at \(z)x the page (\(page.frame.width)) is still "
                                 + "narrower than the canvas (\(canvas.width)) (\(what))")
            // pan to the left extreme: the left of the page has to come to rest
            // at the canvas's own left edge, not at some inner limit
            for _ in 0..<4 { pan(from: 0.1, to: 0.9) }
            sleep(2)
            XCTAssertEqual(page.frame.minX, canvas.minX, accuracy: 30,
                           "at \(z)x the left of the page stops at "
                           + "\(page.frame.minX), canvas starts at \(canvas.minX) (\(what))")
            shot("zoom-left-edge-\(what)")
            for _ in 0..<8 { pan(from: 0.9, to: 0.1) }
            sleep(2)
            XCTAssertEqual(page.frame.maxX, canvas.maxX, accuracy: 30,
                           "at \(z)x the right of the page stops at "
                           + "\(page.frame.maxX), canvas ends at \(canvas.maxX) (\(what))")
            shot("zoom-right-edge-\(what)")
            // back to zoom 1 before the next stage (0.2 lands on the 0.5 floor,
            // from which a couple of pinches climb back)
            score.pinch(withScale: 0.2, velocity: -2.0)
            for _ in 0..<8 where scale() < 1 { score.pinch(withScale: 1.4, velocity: 1.0) }
            sleep(1)
        }

        checkRegion("library-open")
        app.buttons["pill-library"].tap()
        sleep(1)
        checkRegion("no-panels")
        app.buttons["pill-chat"].tap()
        XCTAssertTrue(app.buttons["Close chat"].waitForExistence(timeout: 10))
        sleep(1)
        checkRegion("chat-open")
    }

    /// And the region stays usable under zoom: the page can be panned across
    /// the whole gap rather than being clipped to an inner box.
    func testZoomPansAcrossTheWholeCanvas() {
        app.buttons["arrangement-\(firstArrangement)"].tap()
        let score = app.scrollViews["score-canvas"]
        XCTAssertTrue(score.waitForExistence(timeout: 180))
        app.buttons["pill-library"].tap()
        sleep(2)
        let full = app.windows.firstMatch.frame.width
        XCTAssertEqual(score.frame.width, full, accuracy: 4,
                       "with no panels the canvas should be the whole screen")
        for scale in [2.0, 1.5] {
            score.pinch(withScale: scale, velocity: 1.5)
            sleep(1)
            score.swipeLeft(velocity: .fast)
            score.swipeRight(velocity: .fast)
            XCTAssertEqual(score.frame.width, full, accuracy: 4,
                           "the canvas shrank while zoomed at \(scale)")
            shot("width-zoomed-\(scale)")
        }
        // and zoomed with the library open, which is where the stale
        // centring inset used to strand the page under the panel. The pan
        // itself is checked by eye from the screenshot: XCUITest pinch scales
        // compound unpredictably, so asserting an exact page frame here is
        // flakier than it is useful. The canvas frame is what stays asserted.
        app.buttons["pill-library"].tap()
        sleep(1)
        score.pinch(withScale: 2.0, velocity: 1.5)
        sleep(1)
        for _ in 0..<3 { score.swipeRight(velocity: .fast) }
        sleep(1)
        XCTAssertEqual(score.frame.width, full - 320, accuracy: 4,
                       "the canvas shrank when the library reopened while zoomed")
        shot("width-zoomed-library-open")
        score.pinch(withScale: 0.3, velocity: -2.0)
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
        let field = app.textFields["arrangement-title"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "title field missing")
        replaceText(field, with: "Renamed arrangement")
        let save = app.buttons["save-metadata"]
        XCTAssertTrue(save.waitForExistence(timeout: 5),
                      "Save should appear once the title differs")
        save.tap()
        XCTAssertTrue(waitForDisappearance(of: save, timeout: 60),
                      "Save still offered after a successful write")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["arrangement-\(firstArrangement)"].exists,
                      "the slug-based identifier must survive a rename")
    }

    /// Ali's build-121 report: the title at the top of the score, the title in
    /// the sidebar and the title in the sheet were three different values, and
    /// only one of them could be edited. One title now, and editing it reaches
    /// the notation — which is checked by reading the metadata back out of the
    /// engraved file (the sheet's mismatch note is derived from it), not just
    /// out of the library document.
    func testTitleAndCreditsAreEditableAndReachTheNotation() {
        app.buttons["arrangement-\(firstArrangement)"].tap()
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "the score never finished engraving")
        app.buttons["Arrangement details"].firstMatch.tap()

        let title = app.textFields["arrangement-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "no title field")
        let composer = app.textFields["arrangement-composer"]
        XCTAssertTrue(composer.exists, "composer is metadata too, so it must be editable")
        XCTAssertTrue(app.textFields["arrangement-arranger"].exists, "no arranger field")

        replaceText(title, with: "Quartet Retitled")
        replaceText(composer, with: "Hubert Giraud")
        shot("metadata-editor")

        let save = app.buttons["save-metadata"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "no way to save the edit")
        save.tap()
        XCTAssertTrue(waitForDisappearance(of: save, timeout: 90),
                      "the metadata edit never completed")

        // the edit is a version, like every other change to the notation
        XCTAssertTrue(app.staticTexts["set-metadata"].waitForExistence(timeout: 10),
                      "editing metadata should append a version")
        app.buttons["Done"].firstMatch.tap()

        // the sidebar row now carries the same title (its label is built from
        // the numeral, the title and the subtitle, so this is a contains-check)
        let row = app.buttons["arrangement-\(firstArrangement)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Quartet Retitled"),
                      "the sidebar still shows the old title: \(row.label)")

        // and reopening reads the credits back out of the notation
        app.buttons["Arrangement details"].firstMatch.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["arrangement-composer"].value as? String,
                       "Hubert Giraud",
                       "the composer did not survive in the notation")
        XCTAssertEqual(title.value as? String, "Quartet Retitled")
        XCTAssertFalse(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "still engraves")).firstMatch.exists,
                       "the page and the title should now agree")
        shot("metadata-saved")
        app.buttons["Done"].firstMatch.tap()
    }

    /// The point of the whole change, seen on the page: the title engraved at
    /// the top of the score is the arrangement's title. Screenshots before and
    /// after, so the engraving itself can be read (the page is a bitmap, so no
    /// assertion can look at it — the values either side are asserted instead).
    func testTheEngravedTitleFollowsTheArrangementTitle() {
        app.buttons["arrangement-\(firstArrangement)"].tap()
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "the score never finished engraving")
        sleep(2)
        shot("engraved-title-before")

        app.buttons["Arrangement details"].firstMatch.tap()
        let title = app.textFields["arrangement-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        replaceText(title, with: "Sous le ciel de Paris \u{2014} String Quartet")
        replaceText(app.textFields["arrangement-composer"], with: "Hubert Giraud")
        replaceText(app.textFields["arrangement-arranger"], with: "Gheorghe Branici")
        app.buttons["save-metadata"].tap()
        XCTAssertTrue(waitForDisappearance(of: app.buttons["save-metadata"], timeout: 90))
        app.buttons["Done"].firstMatch.tap()

        // the canvas re-engraves the new version by itself
        sleep(6)
        shot("engraved-title-after")
        let row = app.buttons["arrangement-\(firstArrangement)"]
        XCTAssertTrue(row.label.contains("String Quartet"),
                      "sidebar out of step with the engraved title: \(row.label)")
    }

    /// Part names are the staff labels engraved on every system, so they are
    /// metadata the user can edit too.
    func testPartNamesAreEditableFromTheSheet() {
        app.buttons["arrangement-\(firstArrangement)"].tap()
        app.buttons["Arrangement details"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["SCORED FOR"].waitForExistence(timeout: 20))
        let first = app.buttons["part-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10), "part rows should be editable")
        first.tap()
        let field = app.textFields["part-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no part name field")
        replaceText(field, with: "Violin I")
        app.buttons["Rename"].firstMatch.tap()
        XCTAssertTrue(app.buttons["part-0"].waitForExistence(timeout: 60))
        XCTAssertTrue(element(labelStartingWith: "Rename Violin I").waitForExistence(timeout: 30),
                      "the part row still shows the old name")
        shot("part-renamed")
        app.buttons["Done"].firstMatch.tap()
    }

    /// Every editable field in the sheet says what it is. A placeholder is not
    /// a label: it vanishes the moment the field has content, which is how Ali
    /// ended up with three unnamed boxes at the top of the sheet.
    func testEveryMetadataFieldIsLabelled() {
        app.buttons["Arrangement details"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["ARRANGEMENT"].waitForExistence(timeout: 10))
        for label in ["TITLE", "COMPOSER", "ARRANGER", "SLUG"] {
            XCTAssertTrue(app.staticTexts[label].exists, "no visible \(label) label")
        }
        // and exactly one title field: the old read-only Title row is gone
        XCTAssertFalse(app.staticTexts["Title"].exists,
                       "a second, title-ish row is back in the sheet")
        shot("labelled-metadata-fields")
        app.buttons["Done"].firstMatch.tap()
    }

    /// The slug is the arrangement's handle, not a title — but auto-generated
    /// ones are ugly, so it is editable. Renaming it moves the artifacts and
    /// every reference, so the score has to still open and still have its
    /// history afterwards.
    func testSlugIsEditableAndReferencesSurvive() {
        app.buttons["arrangement-\(firstArrangement)"].tap()
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "the score never finished engraving")
        app.buttons["Arrangement details"].firstMatch.tap()
        let slug = app.textFields["arrangement-slug"]
        XCTAssertTrue(slug.waitForExistence(timeout: 10), "no slug field")
        XCTAssertEqual(slug.value as? String, firstArrangement)
        let versionsBefore = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "v00")).count

        replaceText(slug, with: "Paris Quartet")
        let move = app.buttons["save-slug"]
        XCTAssertTrue(move.waitForExistence(timeout: 5), "no way to apply a new slug")
        move.tap()
        XCTAssertTrue(waitForDisappearance(of: move, timeout: 60), "the move never finished")

        // normalized, not taken literally
        XCTAssertTrue(waitForValue(slug, "paris-quartet"),
                      "slug field shows \(String(describing: slug.value))")
        // the history came with it
        XCTAssertEqual(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "v00")).count, versionsBefore,
                       "versions were lost in the move")
        shot("slug-renamed")
        app.buttons["Done"].firstMatch.tap()

        // the row is filed under the new slug and still opens its score
        let row = app.buttons["arrangement-paris-quartet"]
        XCTAssertTrue(row.waitForExistence(timeout: 20),
                      "the sidebar row did not follow the slug")
        XCTAssertFalse(app.buttons["arrangement-\(firstArrangement)"].exists,
                       "the old slug is still around")
        row.tap()
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "the score no longer renders after the move")
        shot("slug-renamed-still-renders")
    }

    /// Ali's build-122 report: an arrangement moved from Unfiled into a piece
    /// showed no #N badge, and the moved row stayed highlighted with no way to
    /// deselect it while other rows highlighted too.
    func testMovingAnUnfiledArrangementIntoAPieceNumbersIt() {
        // a blank arrangement, unfiled: created in the piece, then unfiled, so
        // the test does not depend on what the seed happens to contain
        app.buttons["arrangement-\(firstArrangement)"].tap()
        app.buttons["Arrangement details"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["ARRANGEMENT"].waitForExistence(timeout: 20))

        // unfile it
        app.buttons["piece-menu"].firstMatch.tap()
        app.buttons["None"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["UNFILED ARRANGEMENTS"].waitForExistence(timeout: 20),
                      "the arrangement never left the piece")
        let row = app.buttons["arrangement-\(firstArrangement)"]
        sleep(2)
        shot("after-unfiling")
        print("UNFILEPROBE row=\(row.label)")
        print("UNFILEPROBE rows=\(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "arrangement-")).count)")
        XCTAssertFalse(row.label.contains("Arrangement number"),
                       "an unfiled arrangement should carry no number: \(row.label)")

        // and back into the piece
        app.buttons["piece-menu"].firstMatch.tap()
        app.buttons[piece].firstMatch.tap()
        XCTAssertTrue(waitForDisappearance(of: app.staticTexts["UNFILED ARRANGEMENTS"],
                                           timeout: 20),
                      "the arrangement never returned to the piece")
        app.buttons["Done"].firstMatch.tap()

        // it is numbered again, and the number is on the row itself
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        XCTAssertTrue(row.label.contains("Arrangement number"),
                      "the moved arrangement has no number badge: \(row.label)")
        shot("moved-into-piece")
    }

    /// One selection at a time, and it can be cleared: the highlight has to be
    /// something the user chose, never a row the app picked for itself.
    func testSelectionIsSingleAndClearable() {
        let first = app.buttons["arrangement-\(firstArrangement)"]
        first.tap()
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180))
        shot("selection-single")
        // exactly one row is selected at a time
        XCTAssertEqual(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true",
                        "arrangement-")).count, 1,
                       "more than one arrangement row is highlighted")
    }

    /// Settings lost its field labels in the design revamp: three unnamed
    /// boxes, one of which is a URL and two of which are secrets.
    func testSettingsFieldsAreLabelled() {
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["ON-DEVICE ENGINE"].waitForExistence(timeout: 10),
                      "settings did not open")
        for label in ["OPENROUTER API KEY", "OMR SERVICE URL", "OMR SERVICE API KEY"] {
            XCTAssertTrue(app.staticTexts[label].exists, "no visible \(label) label")
        }
        // and the key fields say which key is actually in use, rather than
        // showing an empty box that means two different things
        XCTAssertTrue(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "built into this build")).count > 0
            || app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "saved key")).count > 0
            || app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "no key")).count > 0,
            "the key fields do not say which key is in use")
        shot("settings-labelled")
        app.buttons["Done"].firstMatch.tap()
    }

    // MARK: - Order (build 125)

    /// Reordering has to move the numbers with the rows: #N is what Ali types
    /// in chat ("take the violin part from #2"), so a badge that disagrees with
    /// the order is worse than no badge.
    func testReorderingArrangementsRenumbersThem() {
        let first = app.buttons["arrangement-\(firstArrangement)"]
        XCTAssertTrue(first.waitForExistence(timeout: 20))
        XCTAssertTrue(first.label.contains("Arrangement number 1"),
                      "expected the quartet at #1: \(first.label)")
        let second = app.buttons["arrangement-under-paris-skies-accordion-solo"]
        XCTAssertTrue(second.exists, "the seed should file two arrangements")
        XCTAssertTrue(second.label.contains("Arrangement number 2"), second.label)

        // the context menu drives the same op the drag does
        second.press(forDuration: 1.2)
        let moveUp = app.buttons["Move up (become #1)"]
        XCTAssertTrue(moveUp.waitForExistence(timeout: 10),
                      "no reorder action in the arrangement menu")
        moveUp.tap()

        // the numbers swapped, and they followed the rows rather than the slugs
        XCTAssertTrue(waitForLabel(second, contains: "Arrangement number 1"),
                      "the moved arrangement kept its old number: \(second.label)")
        XCTAssertTrue(first.label.contains("Arrangement number 2"),
                      "the displaced arrangement was not renumbered: \(first.label)")
        shot("reordered")
    }

    /// Dragging an arrangement onto a piece heading files it there. This
    /// shipped in an earlier build with no test; it earned one while it was
    /// serving as the control that proved XCUITest *can* drive SwiftUI
    /// drag-and-drop (which is how row-to-row reordering was shown to be a
    /// real gap rather than a harness limit).
    func testDraggingAnUnfiledArrangementOntoAPieceFilesIt() {
        app.buttons["arrangement-\(firstArrangement)"].tap()
        app.buttons["Arrangement details"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["ARRANGEMENT"].waitForExistence(timeout: 20))
        app.buttons["piece-menu"].firstMatch.tap()
        app.buttons["None"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["UNFILED ARRANGEMENTS"].waitForExistence(timeout: 20))
        app.buttons["Done"].firstMatch.tap()

        let row = app.buttons["arrangement-\(firstArrangement)"]
        let pieceHeading = app.buttons["Collapse \(piece)"]
        XCTAssertTrue(pieceHeading.waitForExistence(timeout: 10))
        drag(row, onto: pieceHeading)

        XCTAssertTrue(waitForDisappearance(of: app.staticTexts["UNFILED ARRANGEMENTS"],
                                           timeout: 20),
                      "the dragged arrangement was not filed under the piece")
        shot("dragged-into-piece")
    }

    /// And chat is told the new order: the refs it is handed are built from the
    /// same list the badges are.
    func testChatContextFollowsTheNewOrder() {
        let second = app.buttons["arrangement-under-paris-skies-accordion-solo"]
        XCTAssertTrue(second.waitForExistence(timeout: 20))
        second.press(forDuration: 1.2)
        let moveUp = app.buttons["Move up (become #1)"]
        XCTAssertTrue(moveUp.waitForExistence(timeout: 10))
        moveUp.tap()
        XCTAssertTrue(waitForLabel(second, contains: "Arrangement number 1"))

        // open the moved arrangement: the pill numeral is the same number the
        // chat context hands the model
        second.tap()
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180))
        app.buttons["pill-chat"].tap()
        XCTAssertTrue(app.buttons["Close chat"].waitForExistence(timeout: 10))
        let numeral = element(labelStartingWith: "Arrangement number 1")
        XCTAssertTrue(numeral.exists, "the pill should show the new number")
        shot("reordered-chat")
    }

    // MARK: - Selection (build 124)

    /// The old yellow-band highlight is gone, replaced by a real selection.
    func testTheOldHighlightFeatureIsGone() {
        app.buttons["arrangement-\(firstArrangement)"].tap()
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180))
        app.buttons["pill-options"].tap()
        XCTAssertFalse(app.buttons["Highlight a passage for chat"].exists,
                       "the bar-estimate highlight toggle is still in the options menu")
        XCTAssertTrue(app.buttons["Clear markup"].waitForExistence(timeout: 5),
                      "the options menu did not open")
        // dismiss the menu
        app.buttons["Clear markup"].tap()
    }

    /// Draw across a bar: the elements under the stroke are
    /// selected, the chip says what was caught, chat opens by itself, and the
    /// reference lands in the input ready to be typed against.
    func testLassoSelectsElementsAndHandsThemToChat() {
        app.buttons["arrangement-\(firstArrangement)"].tap()
        let canvas = app.scrollViews["score-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 180),
                      "the score never finished engraving")
        // The canvas existing is not the same as *this* score being on it: the
        // app opens the most recently touched arrangement at launch, so the
        // first canvas to appear can belong to the other one and the stroke
        // would land mid-swap. Wait for the engrave this test asked for.
        sleep(12)

        // A stroke through a system. Which y holds notes depends on where the
        // page sits, so try a few bands rather than pinning one magic number —
        // what is being tested is that a lasso selects and reaches chat.
        let chip = app.staticTexts["Selection"]
        var caught = false
        for y in [0.30, 0.20, 0.42, 0.55] where !caught {
            let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: y))
            let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: y))
            start.press(forDuration: 0.1, thenDragTo: end)
            caught = chip.waitForExistence(timeout: 8)
        }
        XCTAssertTrue(caught, "nothing was selected by any stroke across the page")
        shot("selection-made")

        // chat opened by itself, carrying the reference
        XCTAssertTrue(app.buttons["Close chat"].waitForExistence(timeout: 20),
                      "a finished selection should open chat")
        let input = app.textFields["chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "no chat input")
        let value = (input.value as? String) ?? ""
        XCTAssertTrue(value.contains("[selection:"),
                      "the selection reference did not reach the chat input: \(value)")
        XCTAssertTrue(value.contains("bar"), "the reference should name bars: \(value)")
        shot("selection-in-chat")
    }

    /// Drag one library row onto another thing.
    ///
    /// Not `press(forDuration:thenDragTo:)`: rows carry a context menu, and a
    /// still press of a second opens the menu instead of lifting the drag —
    /// which looked exactly like "the drop was never delivered". Moving off
    /// sooner and holding at the destination is what the drag session needs to
    /// register the target before the finger lifts.
    private func drag(_ source: XCUIElement, onto destination: XCUIElement) {
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.6,
                   thenDragTo: destination.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                   withVelocity: .slow,
                   thenHoldForDuration: 1.2)
    }

    // MARK: - Multi-step journeys
    //
    // The single-feature tests above each guard one thing. These walk chains,
    // because that is where the bugs that reached TestFlight actually lived: a
    // selection that survived a version switch, a drawing filed under the wrong
    // key, a numeral that followed the slug instead of the row.

    /// Make an arrangement and put it in a set list: two engine round trips
    /// and three views of the same thing, which is where numbering and
    /// membership have disagreed before.
    func testANewArrangementCanBeAddedToASetList() {
        app.buttons["Add an arrangement to \(piece)"].tap()
        let blank = app.buttons["New blank arrangement"]
        guard blank.waitForExistence(timeout: 10) else {
            return XCTFail("the add menu does not offer a blank arrangement")
        }
        blank.tap()

        // it lands as #3 of the piece (the seed files two). Match the BUTTON:
        // the label also appears on non-interactive descendants, and a long
        // press on one of those opens no context menu.
        let row = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Arrangement number 3")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 180),
                      "the new arrangement never appeared in the piece")
        shot("journey-new-arrangement")

        // into a set list from its own row
        row.press(forDuration: 1.2)
        let addToSet = app.buttons["Add to set list…"]
        guard addToSet.waitForExistence(timeout: 15) else {
            return XCTFail("the row menu does not offer Add to set list")
        }
        addToSet.tap()
        let chooser = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND NOT identifier CONTAINS %@",
                        "chooser-", "new-setlist")).firstMatch
        guard chooser.waitForExistence(timeout: 15) else {
            return XCTFail("no existing set list offered to add it to")
        }
        let setlistName = chooser.label
            .replacingOccurrences(of: "Add to ", with: "")
            .replacingOccurrences(of: "Remove from ", with: "")
        chooser.tap()
        app.buttons["Done"].firstMatch.tap()

        // and it now shows under that set list as well as under its piece
        let inSet = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "setlist-")).firstMatch
        XCTAssertTrue(inSet.waitForExistence(timeout: 40),
                      "nothing is listed under set list \(setlistName)")
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Arrangement number 3")).firstMatch.exists,
                      "the arrangement lost its place in the piece when it joined a set list")
        shot("journey-in-setlist")
    }

    /// A drawing belongs to the version it was made on. Switching versions must
    /// not carry someone's pencil marks onto a different engraving.
    func testAnnotationsBelongToTheVersionTheyWereMadeOn() {
        app.buttons["arrangement-\(firstArrangement)"].tap()
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "the score never engraved")
        sleep(10)
        app.buttons["pill-markup"].tap()
        XCTAssertTrue(app.buttons["Draw"].waitForExistence(timeout: 10), "no ink bar")

        let canvas = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas-"))
            .firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 20), "no annotation canvas")
        func strokes() -> Int {
            Int((canvas.value as? String)?
                .replacingOccurrences(of: " strokes", with: "") ?? "-1") ?? -1
        }
        let firstKey = canvas.identifier
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.45))
            .press(forDuration: 0.05,
                   thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.45)))
        XCTAssertEqual(strokes(), 1, "the stroke did not land")
        app.buttons["pill-markup"].tap()   // leave markup mode

        // switch to an earlier version
        app.buttons["versions-toggle-\(firstArrangement)"].tap()
        let rows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "version-\(firstArrangement)"))
        guard rows.count > 1 else {
            return XCTFail("need more than one version to switch between")
        }
        rows.element(boundBy: rows.count - 1).tap()
        sleep(12)

        let other = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas-"))
            .firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 60), "the other version never engraved")
        XCTAssertNotEqual(other.identifier, firstKey,
                          "switching versions did not change which canvas is on screen")
        let carried = Int((other.value as? String)?
            .replacingOccurrences(of: " strokes", with: "") ?? "-1") ?? -1
        XCTAssertEqual(carried, 0,
                       "a drawing made on one version showed up on another (\(carried) strokes)")
        shot("journey-annotation-per-version")
    }

    /// A selection is about the engraving it was drawn on: changing version
    /// must not leave a stale selection pointing at bars of a different score.
    func testSwitchingVersionClearsAStaleSelection() {
        app.buttons["arrangement-\(firstArrangement)"].tap()
        let canvas = app.scrollViews["score-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 180), "the score never engraved")
        sleep(12)

        var caught = false
        for y in [0.30, 0.20, 0.42] where !caught {
            let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: y))
            start.press(forDuration: 0.1,
                        thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: y)))
            caught = app.staticTexts["Selection"].waitForExistence(timeout: 8)
        }
        guard caught else { return XCTFail("nothing was selected on the page") }
        if app.buttons["Close chat"].exists { app.buttons["Close chat"].tap() }

        app.buttons["versions-toggle-\(firstArrangement)"].tap()
        let rows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "version-\(firstArrangement)"))
        guard rows.count > 1 else { return XCTFail("need two versions") }
        rows.element(boundBy: rows.count - 1).tap()

        XCTAssertTrue(waitForDisappearance(of: app.staticTexts["Selection"], timeout: 40),
                      "the selection from the previous version is still showing")
        shot("journey-selection-cleared-on-version-switch")
    }

    // MARK: - Version selection

    /// Clicking through an arrangement's versions must light exactly one row.
    /// A prompt group's steps include the group's own face version, so the
    /// group row and a step row both claimed the highlight and it read as two
    /// versions being open at once.
    func testOnlyOneVersionRowIsEverHighlighted() {
        let arrangement = app.buttons["arrangement-\(firstArrangement)"]
        XCTAssertTrue(arrangement.waitForExistence(timeout: 20))
        arrangement.tap()
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "the score never finished engraving")
        app.buttons["versions-toggle-\(firstArrangement)"].tap()

        func highlighted() -> [String] {
            let rows = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@",
                            "version-\(firstArrangement)", "step-\(firstArrangement)"))
            return (0..<rows.count).map { rows.element(boundBy: $0) }
                .filter { $0.exists && $0.isSelected }
                .map { $0.identifier }
        }

        // exactly one to begin with
        var lit = highlighted()
        XCTAssertEqual(lit.count, 1, "expected one highlighted version row, got \(lit)")
        shot("version-highlight-initial")

        // open a prompt group's steps: the highlight must not double up
        let stepsToggle = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@",
                        "steps-toggle-\(firstArrangement)")).firstMatch
        if stepsToggle.exists {
            stepsToggle.tap()
            lit = highlighted()
            XCTAssertEqual(lit.count, 1,
                           "opening a prompt group's steps lit \(lit.count) rows: \(lit)")
            shot("version-highlight-steps-open")
        }

        // click through every version row; each click moves the single highlight
        let rows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@",
                        "version-\(firstArrangement)", "step-\(firstArrangement)"))
        let count = min(rows.count, 4)
        XCTAssertGreaterThan(count, 1, "the fixture needs more than one version to click through")
        for index in 0..<count {
            let row = rows.element(boundBy: index)
            guard row.exists, row.isHittable else { continue }
            let identifier = row.identifier
            row.tap()
            sleep(3)
            lit = highlighted()
            XCTAssertEqual(lit.count, 1,
                           "after opening \(identifier), \(lit.count) rows are highlighted: \(lit)")
            XCTAssertTrue(lit.first?.contains(identifier.replacingOccurrences(
                            of: "step-", with: "").replacingOccurrences(
                            of: "version-", with: "")) ?? false,
                          "the highlight is on \(lit) but \(identifier) was opened")
        }
        shot("version-highlight-after-clicks")
    }

    // MARK: - Dragging

    /// A set list heading takes an arrangement dropped on it. The picker and
    /// the row's "Add to set list…" both still work; this is the shortcut.
    func testDraggingAnArrangementOntoASetlistAddsIt() {
        // a set list the seeded arrangements are not already in
        app.buttons["New setlist"].tap()
        let field = app.textFields["Setlist name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText("Gig night")
        app.buttons["Create"].tap()
        // the picker opens on creation; leave it without adding anything
        XCTAssertTrue(app.staticTexts["ADD AN ARRANGEMENT"].waitForExistence(timeout: 20))
        app.buttons["Done"].firstMatch.tap()

        let heading = app.buttons["Collapse setlist Gig night"]
        XCTAssertTrue(heading.waitForExistence(timeout: 20), "the new set list is not in the sidebar")
        let row = app.buttons["arrangement-\(firstArrangement)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        drag(row, onto: heading)

        XCTAssertTrue(app.buttons["setlist-gig-night-\(firstArrangement)"]
                        .waitForExistence(timeout: 25),
                      "the arrangement dropped on the set list did not join it")
        shot("dragged-into-setlist")

        // leave the library as we found it
        heading.press(forDuration: 1.2)
        if app.buttons["Delete setlist"].waitForExistence(timeout: 10) {
            app.buttons["Delete setlist"].tap()
            if app.buttons["Delete"].waitForExistence(timeout: 5) { app.buttons["Delete"].tap() }
        }
    }

    /// Dropping one arrangement on another inside a piece puts it in that
    /// place, and the numerals follow. Same op as "Move up", by hand.
    func testDraggingOneArrangementOntoAnotherReordersThePiece() {
        let first = app.buttons["arrangement-\(firstArrangement)"]
        let second = app.buttons["arrangement-under-paris-skies-accordion-solo"]
        XCTAssertTrue(first.waitForExistence(timeout: 20))
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        XCTAssertTrue(first.label.contains("Arrangement number 1"), first.label)
        XCTAssertTrue(second.label.contains("Arrangement number 2"), second.label)

        drag(second, onto: first)

        XCTAssertTrue(waitForLabel(second, contains: "Arrangement number 1"),
                      "the dragged arrangement did not take the place it was dropped on: "
                      + second.label)
        XCTAssertTrue(first.label.contains("Arrangement number 2"),
                      "the displaced arrangement was not renumbered: \(first.label)")
        shot("dragged-reorder")
    }

    // MARK: - Two pages side by side

    /// The risk in a spread is that the right-hand page selects from its
    /// neighbour: two pages now share a row, and a lasso has to resolve to the
    /// page it was actually drawn on. Bars run forward through the score, so
    /// the right page must give higher bar numbers than the left.
    func testALassoOnTheRightHandPageSelectsFromThatPage() {
        setTwoPageSpread(on: true)
        app.buttons["arrangement-\(firstArrangement)"].tap()
        let canvas = app.scrollViews["score-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 180),
                      "the score never finished engraving")
        sleep(12)
        shot("two-page-spread")

        guard let left = lassoBars(on: canvas, from: 0.08, to: 0.34) else {
            return XCTFail("nothing was selected anywhere on the left-hand page")
        }
        // chat opened over the canvas; put it away before drawing again
        if app.buttons["Close chat"].exists { app.buttons["Close chat"].tap() }
        sleep(2)
        guard let right = lassoBars(on: canvas, from: 0.66, to: 0.92) else {
            return XCTFail("nothing was selected anywhere on the right-hand page")
        }
        XCTAssertGreaterThan(right, left,
                             "the right-hand page selected bar \(right), which is not "
                             + "later than the left-hand page's bar \(left) — the lasso "
                             + "resolved to the wrong page")
        shot("spread-right-page-selected")
    }

    func testTheSpreadToggleIsInSettingsAndOffByDefault() {
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["READING"].waitForExistence(timeout: 10),
                      "settings has no Reading band")
        let toggle = app.switches["Two pages side by side"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no two-page toggle")
        XCTAssertEqual(toggle.value as? String, "0",
                       "one page at a time is the default")
        app.buttons["Done"].firstMatch.tap()
    }

    private func setTwoPageSpread(on: Bool) {
        app.buttons["Settings"].firstMatch.tap()
        let toggle = app.switches["Two pages side by side"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "no two-page toggle in settings")
        if (toggle.value as? String == "1") != on { toggle.tap() }
        XCTAssertEqual(toggle.value as? String, on ? "1" : "0")
        app.buttons["Done"].firstMatch.tap()
    }

    /// Drag a lasso across a horizontal band and return the first bar number
    /// of whatever it caught. Which y holds notes depends on where the page
    /// sits, so try a few bands rather than pinning one magic number.
    private func lassoBars(on canvas: XCUIElement,
                           from dxStart: CGFloat, to dxEnd: CGFloat) -> Int? {
        let input = app.textFields["chat-input"]
        let before = (input.exists ? (input.value as? String) ?? "" : "")
        for dy in [0.30, 0.20, 0.42, 0.55, 0.12] {
            canvas.coordinate(withNormalizedOffset: CGVector(dx: dxStart, dy: dy))
                .press(forDuration: 0.1,
                       thenDragTo: canvas.coordinate(
                        withNormalizedOffset: CGVector(dx: dxEnd, dy: dy)))
            guard app.staticTexts["Selection"].waitForExistence(timeout: 8) else { continue }
            guard input.waitForExistence(timeout: 20) else { continue }
            let now = (input.value as? String) ?? ""
            guard now.count > before.count, let bar = lastBarNumber(in: now) else { continue }
            return bar
        }
        return nil
    }

    /// The newest selection reference is the last one in the input, since a
    /// reference is appended rather than replacing what is there.
    private func lastBarNumber(in text: String) -> Int? {
        let pattern = try? NSRegularExpression(pattern: "bars? ([0-9]+)")
        let ns = text as NSString
        guard let match = pattern?.matches(
            in: text, range: NSRange(location: 0, length: ns.length)).last else { return nil }
        return Int(ns.substring(with: match.range(at: 1)))
    }

    /// The lasso must never cost the gestures that were already there.
    func testPinchStillZoomsWithTheLassoInstalled() {
        app.buttons["arrangement-\(firstArrangement)"].tap()
        let canvas = app.scrollViews["score-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 180))
        let before = CGFloat(Double((canvas.value as? String)?
            .replacingOccurrences(of: "zoom ", with: "") ?? "1") ?? 1)
        for _ in 0..<6 { canvas.pinch(withScale: 3.0, velocity: 2.0) }
        let after = CGFloat(Double((canvas.value as? String)?
            .replacingOccurrences(of: "zoom ", with: "") ?? "1") ?? 1)
        XCTAssertGreaterThan(after, before,
                             "pinch-zoom stopped working with the lasso installed")
        shot("lasso-installed-zoom")
    }

    /// The piece is metadata as well, and its name was editable nowhere.
    func testPieceIsRenameableFromTheSheet() {
        app.buttons["Arrangement details"].firstMatch.tap()
        let rename = app.buttons["rename-piece"]
        XCTAssertTrue(rename.waitForExistence(timeout: 10), "no way to rename the piece")
        rename.tap()
        let field = app.textFields["piece-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceText(field, with: "Paris Revisited")
        app.buttons["Rename"].firstMatch.tap()
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(element(labelStartingWith: "Paris Revisited")
                        .waitForExistence(timeout: 30),
                      "the piece heading still shows the old name")
        shot("piece-renamed")
    }

    /// Ali's build-125 ask: a set list holds ARRANGEMENTS. Creating one asks
    /// for the name first, then offers arrangements to put in it.
    func testNewSetlistAsksForANameThenOffersArrangements() {
        app.buttons["New setlist"].tap()
        let field = app.textFields["Setlist name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no field in the naming alert")
        XCTAssertTrue(app.buttons["Create"].exists, "the verb should name the action")
        XCTAssertFalse(app.buttons["OK"].exists, "alerts never say OK")
        field.typeText("Gig night")
        shot("setlist-name-first")
        app.buttons["Create"].tap()

        // the picker opens on the new set list, listing arrangements
        XCTAssertTrue(app.staticTexts["ADD AN ARRANGEMENT"].waitForExistence(timeout: 20),
                      "naming a set list should lead straight to picking its arrangements")
        let add = app.buttons["picker-add-\(firstArrangement)"]
        XCTAssertTrue(add.waitForExistence(timeout: 10),
                      "the picker should offer arrangements, not pieces")
        XCTAssertFalse(app.buttons[piece].exists,
                       "a set list holds arrangements; pieces should not be offered")
        add.tap()
        XCTAssertTrue(app.buttons["picker-remove-\(firstArrangement)"]
                        .waitForExistence(timeout: 20),
                      "the arrangement did not move into the set list")
        shot("setlist-picker")
        app.buttons["Done"].firstMatch.tap()

        // and it shows in the sidebar under that set list
        XCTAssertTrue(app.buttons["setlist-gig-night-\(firstArrangement)"]
                        .waitForExistence(timeout: 20),
                      "the set list row does not list the arrangement")

        // clean up so repeat runs stay deterministic
        app.buttons["Collapse setlist Gig night"].press(forDuration: 1.2)
        if app.buttons["Delete setlist"].waitForExistence(timeout: 10) {
            app.buttons["Delete setlist"].tap()
            if app.buttons["Delete"].waitForExistence(timeout: 5) {
                app.buttons["Delete"].tap()
            }
        }
    }

    /// The + on an existing set list adds arrangements to it.
    func testAddingAnArrangementToAnExistingSetlist() {
        let add = app.buttons["add-to-setlist-test-setlist"]
        XCTAssertTrue(add.waitForExistence(timeout: 20), "no + on the seeded set list")
        add.tap()
        XCTAssertTrue(app.staticTexts["IN THIS SET LIST"].waitForExistence(timeout: 10),
                      "the picker did not open")
        // the seed puts both arrangements in, so they are all members already
        XCTAssertTrue(app.buttons["picker-remove-\(firstArrangement)"].exists,
                      "the seeded set list should already hold the arrangements")
        shot("setlist-existing-picker")
        app.buttons["Done"].firstMatch.tap()
    }

    /// And an arrangement can be put in a set list from its own row.
    func testArrangementContextMenuOffersAddToSetList() {
        let row = app.buttons["arrangement-\(firstArrangement)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.press(forDuration: 1.2)
        let action = app.buttons["Add to set list…"]
        XCTAssertTrue(action.waitForExistence(timeout: 15),
                      "no way to add an arrangement to a set list from its row")
        action.tap()
        XCTAssertTrue(app.buttons["chooser-test-setlist"].waitForExistence(timeout: 15),
                      "the set list chooser did not open")
        shot("add-to-setlist-chooser")
        app.buttons["Done"].firstMatch.tap()
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
        // The canvas exists before the page under it has finished engraving, and
        // a stroke drawn in that window lands nowhere. Wait for the count to be
        // readable, then allow the stroke one retry.
        func draw() {
            let before = strokes()
            for _ in 0..<3 {
                canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.45))
                    .press(forDuration: 0.05,
                           thenDragTo: canvas.coordinate(
                            withNormalizedOffset: CGVector(dx: 0.70, dy: 0.45)))
                if strokes() > before { return }
                sleep(3)
            }
        }

        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "the score never engraved")
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
        // named, not firstMatch: the library panel hosts a scroll view too, and
        // firstMatch was pinching that instead of the score
        let score = app.scrollViews["score-canvas"]
        guard score.waitForExistence(timeout: 180) else {
            return XCTFail("no score canvas")
        }
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
        // Alphabetically first, so this is the suite's cold start: it pays for
        // the app launch, the Python engine's first import, the library reset
        // and re-seed, and the engrave of whatever the app opens by itself —
        // and only then waits for another engine round trip. 60s was marginal
        // and eventually lost the race; the rest of the suite allows 180 for an
        // engine round trip. The assertion is unchanged.
        XCTAssertTrue(element(labelStartingWith: "Arrangement number 3")
                        .waitForExistence(timeout: 180),
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
