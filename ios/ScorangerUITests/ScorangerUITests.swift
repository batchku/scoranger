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
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary",
                               "-annotateWithFinger"]
        // Portrait, every time. The suite's page-geometry assertions are
        // written for it -- in landscape the fit is bound by HEIGHT, so a page
        // is narrower than the canvas and "zooming fills the width" is simply
        // not true. A screenshot harness that rotates the device left the whole
        // suite reading the wrong geometry.
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        // A system sheet left standing by a previous test swallows every tap
        // that follows it. Launch clears the app's own state; this clears the
        // one thing it cannot.
        if app.otherElements["ActivityListView"].exists { dismissSystemSheet() }
        // The library IS the app now (§4C): no Home, no tab bar, and the
        // search field is the first thing that exists on it.
        XCTAssertTrue(app.descendants(matching: .any)["library-search"]
                        .waitForExistence(timeout: 90),
                      "the app never showed My Library")
        // ...and then wait for the SEED to finish, which is not the same thing.
        //
        // seedLibraryIfEmpty imports the sample scores and only afterwards
        // assigns them to a set list, while the Pieces band appears as soon as
        // the FIRST import lands. Tests that started there were racing the rest
        // of the fixture: two builds running, a different early-alphabetical
        // test failed each time -- one could not find the arrangement it had
        // just made, the next could not find the set list the seed had not
        // reached yet. Waiting for the arrangement every test goes on to use
        // waits for the imports; nothing here retries an assertion.
        let anyRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                        "row-", piece)).firstMatch
        XCTAssertTrue(anyRow.waitForExistence(timeout: 180),
                      "the seeded library never finished importing")
    }

    /// Relaunch with the Pencil stand-in, so a finger can drive the selection
    /// pipeline.
    ///
    /// Said plainly, because a stand-in is how the FIRST selection scheme
    /// fooled itself into looking tested: this exercises everything downstream
    /// of touch classification — which page the lasso landed on, the unit
    /// points, the hit test, the selection, the chip, the handoff to chat — and
    /// it does NOT exercise Pencil input, which no simulator can produce.
    /// Whether a Pencil reaches the recognizer at all is settled by
    /// `LassoGateTests` and by a person holding an iPad.
    ///
    /// It is per-test, never in `setUp`: with it on, every finger drag on the
    /// canvas is a lasso, which would break the pan and zoom tests.
    private func withPencilStandIn() {
        app.terminate()
        // -resetLibrary is dropped: the library was seeded by the first launch
        // and re-seeding costs another engrave
        app.launchArguments = ["-seedTestLibrary", "-annotateWithFinger",
                               "-uiTestPencil"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["library-search"]
                        .waitForExistence(timeout: 90),
                      "the app never came back after the relaunch")
    }

    /// Open an arrangement the way a person now does: the library is already
    /// on screen, so this is its row. Browsing and reading are separate places
    /// (§3), but browsing is now the app's only place (§4C).
    private func openArrangement(_ slug: String) {
        // An arrangement is not a top-level row: a PIECE is, and a piece is not
        // openable (§2). Opening one means opening one of its arrangements, so
        // this goes the way a person does -- the piece row, then the choice.
        let direct = app.buttons["row-\(slug)"]
        if direct.waitForExistence(timeout: 5) { direct.tap(); return }

        // A piece with several arrangements pushes its screen; the arrangement
        // is chosen there. A piece is not openable -- opening one means opening
        // one of its arrangements.
        let pieceRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                        "row-", piece)).firstMatch
        XCTAssertTrue(pieceRow.waitForExistence(timeout: 180),
                      "the library never listed the piece holding \(slug)")
        pieceRow.tap()

        let choice = app.buttons["arrangement-choice-\(slug)"]
        XCTAssertTrue(choice.waitForExistence(timeout: 30),
                      "the piece screen did not list its arrangements")
        choice.tap()
    }

    /// The piece screen -- where the arrangement sheet went (§3.1).
    ///
    /// Reached by the piece row's ☰, which is the one visible control a row
    /// carries. No long press: that is the rule this revision adds.
    private func openPieceSheet() {
        rowMenu(piece)
        XCTAssertTrue(app.buttons["piece-new-arrangement-\(pieceSlug)"]
                        .waitForExistence(timeout: 20),
                      "the piece screen did not open")
    }

    /// A row's ☰. Pushes to the item's screen.
    /// Get back to the library's own list, from wherever the test has got to.
    ///
    /// The score covers the library, and the library keeps a navigation stack,
    /// so both have to be unwound or the next tap goes somewhere unintended.
    private func resetToLibraryRoot() {
        if app.buttons["score-close"].exists { app.buttons["score-close"].tap() }
        for _ in 0..<4 {
            guard app.buttons["segment-pieces"].exists == false else { break }
            let back = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Back to")).firstMatch
            guard back.exists, back.isHittable else { break }
            back.tap()
        }
    }

    private func rowMenu(_ id: String) {
        resetToLibraryRoot()
        // pieces and unfiled arrangements live in the Pieces half; a test that
        // was last looking at set lists would otherwise search the wrong list
        if app.buttons["segment-pieces"].exists { app.buttons["segment-pieces"].tap() }
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                        "row-", id)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 180), "no row for \(id)")
        let menu = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                        "row-menu-", id)).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 20), "no ☰ on the row for \(id)")
        menu.tap()
    }

    /// The arrangement screen: the per-item actions screen (§3.2).
    private func openArrangementScreen(_ slug: String) {
        openPieceSheet()
        tapAnyway(app.buttons["row-menu-\(slug)"], in: app.scrollViews.firstMatch)
        XCTAssertTrue(app.buttons["arrangement-title"].waitForExistence(timeout: 20),
                      "the arrangement screen did not open")
    }

    /// The seeded piece's slug, for the ids the screens carry.
    private var pieceSlug: String { "sous-le-ciel-de-paris" }

    /// A row of the "…" menu, by identifier rather than by element type.
    private func menuRow(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Renaming is tapping the name (0.4.2 simplify pass).
    ///
    /// There is no Rename button anywhere: the value IS the control, so this
    /// taps the title, types, and returns. A button whose only job was to make
    /// the thing beside it editable had nothing left to do.
    func testTappingATitleRenamesItInPlace() {
        openArrangementScreen(firstArrangement)
        let title = app.buttons["arrangement-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 20),
                      "the arrangement screen shows no tappable title")
        title.tap()
        let field = app.textFields["arrangement-title-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10),
                      "tapping the title did not turn it into a field")
        replaceText(field, with: "Tapped rename")
        app.typeText("\n")
        XCTAssertTrue(app.buttons["arrangement-title"].waitForExistence(timeout: 30),
                      "the field did not commit back to a title")
        shot("tap-to-rename")
    }

    /// And no Rename button survives anywhere it used to be.
    func testNothingOffersARenameButton() {
        openArrangementScreen(firstArrangement)
        XCTAssertFalse(app.buttons["edit-rename-\(firstArrangement)"].exists,
                       "the arrangement screen still has a Rename row")
        XCTAssertFalse(app.buttons["bar-rename"].exists,
                       "the action bar still has a Rename button")
    }

    /// Leave a pushed screen.
    ///
    /// By label rather than identifier: a nav bar's back button is a stack
    /// inside a Button, and which of the two XCUITest reports as the queryable
    /// element varies with what else is on the screen. The label is set on the
    /// same element either way and says where it goes.
    /// A freshly seeded arrangement may have exactly one version, and a test
    /// about switching between versions needs two. Make the second rather than
    /// hope for it.
    private func ensureASecondVersion() {
        app.buttons["score-more"].tap()
        // the … menu is layered: Transpose opens its own layer, and the two
        // semitone rows live in there
        let layer = menuRow("more-transpose")
        guard layer.waitForExistence(timeout: 10) else {
            return XCTFail("the … menu has no Transpose")
        }
        layer.tap()
        let up = menuRow("transpose-up")
        guard up.waitForExistence(timeout: 10) else {
            return XCTFail("Transpose opened but offers no semitone up")
        }
        up.tap()
        sleep(25)
        // and come back OUT of the options: transposing pops to the options
        // root, which is a full screen sitting over the canvas -- a test that
        // went straight on to draw was drawing on the options screen
        let back = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Back to")).firstMatch
        if back.exists { back.tap() }
        if app.buttons["score-more"].exists && app.buttons["score-more"].isSelected {
            app.buttons["score-more"].tap()
        }
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 120),
                      "the canvas never came back after transposing")
        sleep(8)
    }

    /// Close Settings, whichever shape it is: a docked panel from the library
    /// (#51), a pushed screen from the score.
    private func closeSettings() {
        if app.buttons["Close settings"].exists {
            app.buttons["Close settings"].tap()
        } else {
            goBack()
        }
    }

    private func goBack() {
        let byId = app.buttons["screen-back"].firstMatch
        if byId.exists && byId.isHittable { byId.tap(); return }
        let byLabel = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Back to")).firstMatch
        XCTAssertTrue(byLabel.waitForExistence(timeout: 10),
                      "no way back from this screen")
        byLabel.tap()
    }

    /// Bring an element into view before touching it.
    ///
    /// A pushed screen scrolls, and `exists` is true for something below the
    /// fold -- so a tap can land on nothing while the assertion before it
    /// passes. That is what made the part rows look unreachable.
    /// Tap something that exists, wherever it is.
    ///
    /// `isHittable` is false for anything below the fold, and scrolling does
    /// not always bring a row inside a nested scroll view into reach. A
    /// coordinate tap goes to the element's own frame and does not care.
    private func tapAnyway(_ element: XCUIElement, in container: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 20),
                      "no element to tap: \(element)")
        if scrollTo(element, in: container) { element.tap(); return }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @discardableResult
    private func scrollTo(_ element: XCUIElement, in container: XCUIElement,
                          tries: Int = 6) -> Bool {
        guard element.waitForExistence(timeout: 10) else { return false }
        for _ in 0..<tries {
            if element.isHittable { return true }
            container.swipeUp(velocity: .slow)
        }
        return element.isHittable
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

    // MARK: - The score view's own chrome (NAVIGATION_SYSTEM.md §4.5)

    /// The pill is gone from the score view. Its duties did not vanish -- they
    /// moved (§8), and this is the list of where to.
    func testTheTopBarCarriesEveryControlAndThereIsNoNavigationBar() {
        openArrangement(firstArrangement)
        XCTAssertTrue(app.buttons["score-close"].waitForExistence(timeout: 180),
                      "no way out of the score")
        XCTAssertTrue(app.buttons["score-ask"].exists, "chat has no button")
        XCTAssertTrue(app.buttons["score-more"].exists, "no … menu")
        XCTAssertTrue(app.buttons["score-edit"].exists, "no Edit")
        XCTAssertTrue(app.buttons["score-spread"].exists,
                      "the spread toggle should be in the top bar, not buried in Settings")
        XCTAssertTrue(app.buttons["score-title"].exists, "no title block to switch from")
        XCTAssertFalse(app.buttons["pill-library"].exists,
                       "the pill's library toggle should be gone: browsing is a tab now")
        XCTAssertFalse(app.navigationBars.element.exists,
                       "the score-first layout has no navigation bar")
        shot("score-top-bar")
    }

    /// Reading happens over the library, and X ALWAYS lands back on it -- there
    /// is nowhere else to land now that Home is gone (§4C).
    func testTheScoreOpensOverTheLibraryAndClosesBack() {
        openArrangement(firstArrangement)
        XCTAssertTrue(app.buttons["score-close"].waitForExistence(timeout: 180))
        XCTAssertFalse(app.descendants(matching: .any)["library-search"].isHittable,
                       "the score covers the library while you are in it")
        app.buttons["score-close"].tap()
        XCTAssertTrue(app.buttons["segment-pieces"].waitForExistence(timeout: 20)
                        || app.buttons.matching(
                            NSPredicate(format: "label BEGINSWITH %@", "Back to")).count > 0,
                      "closing the score did not go back to the library")
        shot("closed-back-to-library")
    }

    func testTheLibraryHasBothHalves() {
        XCTAssertTrue(app.buttons["segment-pieces"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["segment-setlists"].exists)
        XCTAssertTrue(app.otherElements["alphabet-rail"].exists
                        || app.buttons["library-sort"].exists,
                      "the library has no sort control")
        app.buttons["segment-setlists"].tap()
        XCTAssertTrue(app.buttons["segment-setlists"].isSelected)
        shot("library-setlists")
    }

    /// Home's actions, on the library where they now live (§4C) -- less Ask,
    /// which Ali had removed (#47).
    func testTheLibraryCarriesTheMakingActions() {
        XCTAssertTrue(app.buttons["library-import"].waitForExistence(timeout: 30),
                      "the library has no import action")
        XCTAssertTrue(app.buttons["library-new"].exists)
        XCTAssertTrue(app.buttons["library-new-setlist"].exists)
        XCTAssertFalse(app.buttons["library-ask"].exists, "Ask is back")
        shot("library-action-row")
    }

    /// #48-#50: the library's top row is the gear and nothing else. Help and
    /// the inbox were drawn and inert; the engine chip restated in the corner
    /// of every screen a question that Settings answers properly.
    func testTheLibraryTopRowIsJustTheGear() {
        XCTAssertTrue(app.buttons["library-settings"].waitForExistence(timeout: 30),
                      "the gear went with the rest of the top row")
        XCTAssertFalse(app.buttons["Help"].exists, "the ? is back")
        XCTAssertFalse(app.buttons["Inbox"].exists, "the tray is back")
        XCTAssertFalse(app.descendants(matching: .any)["library-engine-chip"].exists,
                       "the engine chip is back")
    }

    /// Import opens the file picker. Nothing else, and nothing first.
    ///
    /// It used to push a "which piece should this land in?" screen, and that
    /// screen could not deliver: naming a new piece popped the navigation
    /// stack and asked to present the picker in the same tick, so SwiftUI
    /// dropped the presentation mid-transition. You named a piece and the
    /// picker never came. Import was unusable, and no test covered it -- which
    /// is why it could break in silence.
    func testImportGoesStraightToTheFilePicker() {
        XCTAssertTrue(app.buttons["library-import"].waitForExistence(timeout: 30),
                      "no Import button")
        XCTAssertFalse(app.buttons["Cancel"].exists,
                       "something was already presented before Import was tapped")
        app.buttons["library-import"].tap()

        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 20),
                      "tapping Import did not open the file picker")
        // and it got there without asking anything first
        XCTAssertFalse(app.textFields["inline-rename-field"].exists,
                       "Import stopped to ask for a name")
        XCTAssertEqual(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Back to")).count, 0,
                       "Import pushed a screen instead of opening the picker")
        shot("import-picker")
        app.buttons["Cancel"].tap()
    }

    /// #53: which build this is, on the screen the app opens to.
    func testTheLibraryShowsWhichBuildThisIs() {
        let stamp = app.staticTexts["build-stamp"]
        XCTAssertTrue(stamp.waitForExistence(timeout: 30),
                      "no build stamp on the library")
        XCTAssertTrue(stamp.label.contains("b"), "the stamp says \(stamp.label)")
    }

    /// #51: Settings is a panel docked at the trailing edge, with the library
    /// still there behind it -- not a screen that covers everything.
    func testSettingsOpensAsAPanelBesideTheLibrary() {
        app.buttons["library-settings"].tap()
        let panel = app.descendants(matching: .any)["settings-panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 20), "Settings did not open")
        XCTAssertTrue(app.descendants(matching: .any)["library-search"].exists,
                      "the library is gone: this is a full-screen Settings again")
        XCTAssertLessThan(panel.frame.width, app.windows.firstMatch.frame.width * 0.75,
                          "the panel covers the screen")
        shot("settings-panel")
        app.buttons["Close settings"].tap()
        XCTAssertTrue(waitForDisappearance(of: panel, timeout: 10))
    }

    /// The tab bar is gone entirely: one live tab and a disabled placeholder
    /// was not a tab bar (§4C).
    func testThereIsNoTabBar() {
        for id in ["tab-home", "tab-library", "tab-shared"] {
            XCTAssertFalse(app.buttons[id].exists, "\(id) survived the merge")
        }
    }

    /// The `+` offered exactly what the action row now shows permanently, so
    /// it went with Home rather than becoming a second way in (§4C).
    func testTheFABIsGone() {
        XCTAssertFalse(app.buttons["library-add"].exists)
        XCTAssertTrue(app.buttons["library-import"].exists,
                      "Import must be permanently visible now that + is gone")
    }

    /// L12: the empty library is the first screen a new user meets, so it is a
    /// STATE with something to do -- not a sentence in the top-left corner.
    func testAnEmptyLibraryIsAStateWithSomethingToDo() {
        app.terminate()
        app.launchArguments = ["-resetLibrary"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["library-search"]
                        .waitForExistence(timeout: 90))
        let state = app.descendants(matching: .any)["library-empty"]
        XCTAssertTrue(state.waitForExistence(timeout: 30), "no empty state")
        XCTAssertTrue(app.buttons["state-action"].exists,
                      "the empty library offers nothing to do about it")
        // and the count says it in words (L11)
        XCTAssertTrue(app.staticTexts["No pieces yet"].exists,
                      "the empty library still counts in digits")
        shot("empty-library")
    }

    // The engine-chip tests went with the chip (#50). What they were really
    // protecting -- that the mode is printed once, and that it says "remote"
    // in remote mode -- now lives where the chip's job moved to, in Settings,
    // and the sweep checks it there.

    /// The score screen has no library overlay any more.

    func testTheLibraryOverlayIsGoneFromTheScore() {
        openArrangement(firstArrangement)
        XCTAssertTrue(app.buttons["score-close"].waitForExistence(timeout: 180))
        XCTAssertFalse(app.staticTexts["PIECES"].exists,
                       "the score view should not carry a library overlay any more")
        // browsing is a tab now, and it is still one tap away
        XCTAssertTrue(app.buttons["score-close"].exists)
    }

    func testChatOverlayOpensFromAsk() {
        openArrangement(firstArrangement)
        XCTAssertTrue(app.buttons["score-ask"].waitForExistence(timeout: 180))
        app.buttons["score-ask"].tap()
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
    func testCanvasFillsTheGapBesideTheChatPanel() {
        let screen = app.windows.firstMatch.frame.width
        let chat: CGFloat = 380
        // the score view only exists once an arrangement has engraved
        openArrangement(firstArrangement)
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
            // FITTED, not fit-to-width. The canvas shows one page fitted to
            // the viewport now, so a portrait page on a landscape canvas is
            // HEIGHT-bound and cannot fill the width -- that is what fit-to-page
            // means, and asserting otherwise was asserting the old layout.
            // What must still hold: the page is inside the canvas, and it fills
            // whichever dimension binds.
            let fitsWide = page.frame.width <= score.frame.width - 16
            let fitsTall = page.frame.height <= score.frame.height + 8
            XCTAssertTrue(fitsWide && fitsTall,
                          "page overflows the canvas with \(what): "
                          + "\(page.frame) in \(score.frame)")
            let fillsWidth = abs(page.frame.width - (score.frame.width - 24)) < 12
            let fillsHeight = abs(page.frame.height - (score.frame.height - 24)) < 24
            XCTAssertTrue(fillsWidth || fillsHeight,
                          "page fills neither dimension with \(what): "
                          + "\(page.frame) in \(score.frame)")
        }

        func assertWidth(_ expected: CGFloat, _ what: String) {
            // a couple of points of slack for panel borders
            XCTAssertEqual(score.frame.width, expected, accuracy: 4,
                           "canvas width with \(what): expected ~\(expected), "
                           + "got \(score.frame.width) of \(screen) available")
        }

        // The library overlay is gone from the score view (§8), so there is
        // one panel left to make room for and two states to check rather than
        // four. The property being protected is unchanged: whatever gap the
        // chrome leaves, the score fills it.
        assertWidth(screen, "nothing open")
        assertPageFillsCanvas("nothing open")
        shot("width-none-open")

        app.buttons["score-ask"].tap()
        XCTAssertTrue(app.buttons["Close chat"].waitForExistence(timeout: 10))
        sleep(1)
        assertWidth(screen - chat, "chat open")
        assertPageFillsCanvas("chat open")
        shot("width-chat-only")

        app.buttons["Close chat"].tap()
        sleep(1)
        assertWidth(screen, "chat closed again")
        assertPageFillsCanvas("chat closed again")
    }

    /// Zoomed in, the page has to be bigger than the region and pannable to
    /// both of its edges -- the build-120 symptom was hard left/right limits
    /// well inside the screen, because the scroll view itself was only 544pt
    /// wide. XCUITest's pinch under-delivers (a requested 2.5 lands near 1.2),
    /// so the canvas publishes its live zoom scale and the test pinches until
    /// it reads high enough.
    func testTheZoomedPageUsesTheWholeCanvas() {
        openArrangement(firstArrangement)
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

        checkRegion("no-panels")
        app.buttons["score-ask"].tap()
        XCTAssertTrue(app.buttons["Close chat"].waitForExistence(timeout: 10))
        sleep(1)
        checkRegion("chat-open")
    }

    /// And the region stays usable under zoom: the page can be panned across
    /// the whole gap rather than being clipped to an inner box.
    func testZoomPansAcrossTheWholeCanvas() {
        openArrangement(firstArrangement)
        let score = app.scrollViews["score-canvas"]
        XCTAssertTrue(score.waitForExistence(timeout: 180))
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
        // and zoomed with the chat panel open, which is where the stale
        // centring inset used to strand the page under the panel. The pan
        // itself is checked by eye from the screenshot: XCUITest pinch scales
        // compound unpredictably, so asserting an exact page frame here is
        // flakier than it is useful. The canvas frame is what stays asserted.
        app.buttons["score-ask"].tap()
        sleep(1)
        score.pinch(withScale: 2.0, velocity: 1.5)
        sleep(1)
        for _ in 0..<3 { score.swipeRight(velocity: .fast) }
        sleep(1)
        // 380, the chat panel: the library overlay it used to be is gone
        XCTAssertEqual(score.frame.width, full - 380, accuracy: 4,
                       "the canvas shrank when the chat panel opened while zoomed")
        shot("width-zoomed-chat-open")
        score.pinch(withScale: 0.3, velocity: -2.0)
    }

    // MARK: - Hierarchy

    /// #N is a position WITHIN a piece, so the numbering is on the piece
    /// screen -- which is where a piece's arrangements live now.
    func testArrangementsAreNumberedWithinPiece() {
        openPieceSheet()
        XCTAssertTrue(element(labelStartingWith: "Arrangement number 1").exists)
        XCTAssertTrue(element(labelStartingWith: "Arrangement number 2").exists)
        shot("numbered-arrangements")
    }

    /// The sidebar's expanding caret is gone: a piece is a place you go to.
    /// What it did -- see this piece's arrangements, and get back -- is the
    /// piece screen and its back button.
    func testAPieceOpensItsOwnScreenAndComesBack() {
        openPieceSheet()
        XCTAssertTrue(app.buttons["arrangement-choice-\(firstArrangement)"].exists,
                      "the piece screen does not list its arrangements")
        XCTAssertFalse(app.buttons["Collapse \(piece)"].exists,
                       "the expanding caret should be gone")
        goBack()
        XCTAssertTrue(app.buttons["segment-pieces"].waitForExistence(timeout: 20),
                      "back did not return to the library")
    }

    func testRowTapOpensArrangement() {
        openArrangement(firstArrangement)
        // the pill's version chip tracks whatever is open
        XCTAssertTrue(app.buttons["score-title"].waitForExistence(timeout: 60),
                      "row tap did not open an arrangement")
    }

    /// Versions used to nest under an arrangement row on a caret. They are a
    /// pushed list off the arrangement screen now -- the same history, somewhere
    /// you can name.
    func testVersionsAreAScreenOffTheArrangement() {
        openArrangementScreen(firstArrangement)
        let versions = app.buttons["edit-versions-\(firstArrangement)"]
        XCTAssertTrue(versions.exists, "the arrangement screen has no Versions row")
        versions.tap()
        XCTAssertTrue(app.buttons["version-\(firstArrangement)-v001"]
                        .waitForExistence(timeout: 20),
                      "the versions screen did not list them")
        shot("versions-screen")
        goBack()
    }

    func testPromptGroupStepsExpand() {

        openArrangementScreen(firstArrangement)
        app.buttons["edit-versions-\(firstArrangement)"].tap()
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

        openArrangementScreen(firstArrangement)
        app.buttons["row-details-\(firstArrangement)"].tap()
        XCTAssertTrue(app.staticTexts["ARRANGEMENT"].waitForExistence(timeout: 10),
                      "the arrangement sheet did not open")
        XCTAssertTrue(app.staticTexts["SCORED FOR"].exists,
                      "the sheet should list what the arrangement is scored for")
        // destructive action sits in the body, last — never in the header
        XCTAssertTrue(app.staticTexts["DANGER"].exists)
        XCTAssertTrue(app.buttons["Delete arrangement…"].exists)
        shot("arrangement-sheet")
        goBack()
        XCTAssertTrue(waitForDisappearance(of: app.staticTexts["ARRANGEMENT"], timeout: 5))
    }

    func testRenameArrangementFromTheSheet() {

        openArrangementScreen(firstArrangement)
        app.buttons["row-details-\(firstArrangement)"].tap()
        let field = app.textFields["arrangement-title"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "title field missing")
        replaceText(field, with: "Renamed arrangement")
        let save = app.buttons["save-metadata"]
        XCTAssertTrue(save.waitForExistence(timeout: 5),
                      "Save should appear once the title differs")
        save.tap()
        XCTAssertTrue(waitForDisappearance(of: save, timeout: 60),
                      "Save still offered after a successful write")
        goBack()            // details -> arrangement screen
        goBack()            // arrangement -> piece screen
        XCTAssertTrue(app.buttons["arrangement-choice-\(firstArrangement)"]
                        .waitForExistence(timeout: 20),
                      "the slug-based identifier must survive a rename")
    }

    /// Ali's build-121 report: the title at the top of the score, the title in
    /// the sidebar and the title in the sheet were three different values, and
    /// only one of them could be edited. One title now, and editing it reaches
    /// the notation — which is checked by reading the metadata back out of the
    /// engraved file (the sheet's mismatch note is derived from it), not just
    /// out of the library document.
    func testTitleAndCreditsAreEditableAndReachTheNotation() {

        openArrangement(firstArrangement)
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "the score never finished engraving")
        openArrangementScreen(firstArrangement)
        app.buttons["row-details-\(firstArrangement)"].tap()

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
        goBack()            // details -> arrangement screen
        goBack()            // arrangement -> the piece it belongs to

        // the row under the piece now carries the same title (its label is
        // built from the numeral, the title and the subtitle, so this is a
        // contains-check)
        let row = app.buttons["arrangement-choice-\(firstArrangement)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        XCTAssertTrue(row.label.contains("Quartet Retitled"),
                      "the sidebar still shows the old title: \(row.label)")

        // and reopening reads the credits back out of the notation
        openArrangementScreen(firstArrangement)
        app.buttons["row-details-\(firstArrangement)"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["arrangement-composer"].value as? String,
                       "Hubert Giraud",
                       "the composer did not survive in the notation")
        XCTAssertEqual(title.value as? String, "Quartet Retitled")
        XCTAssertFalse(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "still engraves")).firstMatch.exists,
                       "the page and the title should now agree")
        shot("metadata-saved")
        goBack()
    }

    /// The point of the whole change, seen on the page: the title engraved at
    /// the top of the score is the arrangement's title. Screenshots before and
    /// after, so the engraving itself can be read (the page is a bitmap, so no
    /// assertion can look at it — the values either side are asserted instead).
    func testTheEngravedTitleFollowsTheArrangementTitle() {

        openArrangement(firstArrangement)
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "the score never finished engraving")
        sleep(2)
        shot("engraved-title-before")

        openArrangementScreen(firstArrangement)
        app.buttons["row-details-\(firstArrangement)"].tap()
        let title = app.textFields["arrangement-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        replaceText(title, with: "Sous le ciel de Paris \u{2014} String Quartet")
        replaceText(app.textFields["arrangement-composer"], with: "Hubert Giraud")
        replaceText(app.textFields["arrangement-arranger"], with: "Gheorghe Branici")
        app.buttons["save-metadata"].tap()
        XCTAssertTrue(waitForDisappearance(of: app.buttons["save-metadata"], timeout: 90))
        goBack()

        // the canvas re-engraves the new version by itself
        sleep(6)
        shot("engraved-title-after")
        goBack()            // arrangement screen -> the piece it belongs to
        let row = app.buttons["arrangement-choice-\(firstArrangement)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20),
                      "the arrangement is not listed under its piece")
        XCTAssertTrue(row.label.contains("String Quartet"),
                      "sidebar out of step with the engraved title: \(row.label)")
    }

    /// Part names are the staff labels engraved on every system, so they are
    /// metadata the user can edit too.
    func testPartNamesAreEditableFromTheSheet() {

        openArrangementScreen(firstArrangement)
        app.buttons["row-details-\(firstArrangement)"].tap()
        XCTAssertTrue(app.staticTexts["SCORED FOR"].waitForExistence(timeout: 20))
        let first = app.buttons["part-0"]
        XCTAssertTrue(scrollTo(first, in: app.scrollViews.firstMatch),
                      "part rows should be editable")
        first.tap()
        // tapping the name opens it in place, and Done commits it -- there is
        // no Rename button anywhere in the app any more
        let field = app.textFields["part-name-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no part name field")
        XCTAssertFalse(app.buttons["Rename"].exists, "nothing offers a Rename button")
        replaceText(field, with: "Violin I")
        field.typeText("\n")
        XCTAssertTrue(app.buttons["part-0"].waitForExistence(timeout: 60))
        XCTAssertTrue(element(labelStartingWith: "Violin I").waitForExistence(timeout: 30),
                      "the part row still shows the old name")
        shot("part-renamed")
        goBack()
    }

    /// Every editable field in the sheet says what it is. A placeholder is not
    /// a label: it vanishes the moment the field has content, which is how Ali
    /// ended up with three unnamed boxes at the top of the sheet.
    func testEveryMetadataFieldIsLabelled() {
        openArrangementScreen(firstArrangement)
        app.buttons["row-details-\(firstArrangement)"].tap()
        XCTAssertTrue(app.staticTexts["ARRANGEMENT"].waitForExistence(timeout: 10))
        for label in ["TITLE", "COMPOSER", "ARRANGER", "SLUG"] {
            XCTAssertTrue(app.staticTexts[label].exists, "no visible \(label) label")
        }
        // and exactly one title field: the old read-only Title row is gone
        XCTAssertFalse(app.staticTexts["Title"].exists,
                       "a second, title-ish row is back in the sheet")
        shot("labelled-metadata-fields")
        goBack()
    }

    /// The slug is the arrangement's handle, not a title — but auto-generated
    /// ones are ugly, so it is editable. Renaming it moves the artifacts and
    /// every reference, so the score has to still open and still have its
    /// history afterwards.
    func testSlugIsEditableAndReferencesSurvive() {

        openArrangement(firstArrangement)
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "the score never finished engraving")
        openArrangementScreen(firstArrangement)
        app.buttons["row-details-\(firstArrangement)"].tap()
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
        // The history came with it. Not an equality: this counts v00* labels
        // anywhere on screen, and after the rename the sidebar shows the
        // arrangement's version rows as well as the sheet, so the number can
        // legitimately grow. What must never happen is losing one -- the engine
        // side of that invariant is check_workflows' "version history stays
        // addressable" journey.
        XCTAssertGreaterThanOrEqual(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "v00")).count, versionsBefore,
                                    "versions were lost in the move")
        shot("slug-renamed")
        goBack()            // details -> arrangement screen
        goBack()            // arrangement -> the piece it belongs to

        // the row is filed under the new slug and still opens its score
        let row = app.buttons["arrangement-choice-paris-quartet"]
        XCTAssertTrue(row.waitForExistence(timeout: 30),
                      "the row under the piece did not follow the slug")
        XCTAssertFalse(app.buttons["arrangement-choice-\(firstArrangement)"].exists,
                       "the old slug is still around")
        row.tap()
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "the score no longer renders after the move")
        shot("slug-renamed-still-renders")
    }
    /// One selection at a time, and it can be cleared: the highlight has to be
    /// something the user chose, never a row the app picked for itself.
    func testSelectionIsSingleAndClearable() {

        openPieceSheet()
        let first = app.buttons["arrangement-choice-\(firstArrangement)"]
        XCTAssertTrue(first.waitForExistence(timeout: 20),
                      "the arrangement is not listed under its piece")
        first.tap()
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180))
        shot("selection-single")
        // step back out to the list the row is on: the score covers it
        app.buttons["score-close"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 20), "never came back to the piece")
        // exactly one row is selected at a time
        XCTAssertEqual(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true",
                        "arrangement-choice-")).count, 1,
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
        closeSettings()
    }

    // MARK: - Order (build 125)

    /// Reordering has to move the numbers with the rows: #N is what Ali types
    /// in chat ("take the violin part from #2"), so a badge that disagrees with
    /// the order is worse than no badge.
    /// #N is a POSITION within a piece, so changing the order changes the
    /// numbers. Dragging one arrangement onto another used to do this; it is
    /// Move up / Move down on the piece screen now, and there is no drag left
    /// in the app at all.
    func testReorderingArrangementsRenumbersThem() {
        openPieceSheet()
        let first = app.buttons["arrangement-choice-\(firstArrangement)"]
        XCTAssertTrue(first.waitForExistence(timeout: 20))
        XCTAssertTrue(first.label.contains("Arrangement number 1"),
                      "expected the quartet at #1: \(first.label)")
        let second = app.buttons["arrangement-choice-under-paris-skies-accordion-solo"]
        XCTAssertTrue(second.exists, "the seed should file two arrangements")
        XCTAssertTrue(second.label.contains("Arrangement number 2"), second.label)

        let moveUp = app.buttons["arr-up-under-paris-skies-accordion-solo"]
        XCTAssertTrue(moveUp.waitForExistence(timeout: 10),
                      "no Move up on the piece screen")
        moveUp.tap()

        // the numbers swapped, and they followed the rows rather than the slugs
        XCTAssertTrue(waitForLabel(second, contains: "Arrangement number 1"),
                      "the moved arrangement kept its old number: \(second.label)")
        XCTAssertTrue(first.label.contains("Arrangement number 2"),
                      "the displaced arrangement was not renumbered: \(first.label)")
        shot("reordered")
    }
    /// And chat is told the new order: the refs it is handed are built from the
    /// same list the badges are.
    func testChatContextFollowsTheNewOrder() {
        openPieceSheet()
        let second = app.buttons["arrangement-choice-under-paris-skies-accordion-solo"]
        XCTAssertTrue(second.waitForExistence(timeout: 20))
        let moveUp = app.buttons["arr-up-under-paris-skies-accordion-solo"]
        XCTAssertTrue(moveUp.waitForExistence(timeout: 10),
                      "no Move up on the piece screen")
        moveUp.tap()
        XCTAssertTrue(waitForLabel(second, contains: "Arrangement number 1"))

        // open the moved arrangement: the pill numeral is the same number the
        // chat context hands the model
        second.tap()
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180))
        app.buttons["score-ask"].tap()
        XCTAssertTrue(app.buttons["Close chat"].waitForExistence(timeout: 10))
        let numeral = element(labelStartingWith: "Arrangement number 1")
        XCTAssertTrue(numeral.exists, "the pill should show the new number")
        shot("reordered-chat")
    }

    // MARK: - Selection (build 124)

    // MARK: - Nudging and resizing a chord symbol

    /// The chip's position-and-size row (docs/size-and-position-spec.md).
    ///
    /// Seeded with a chord chart because neither sample score carries chord
    /// symbols, and the row only appears when everything selected is
    /// adjustable — which today means chord symbols.
    private func openScoreWithChords() {
        app.terminate()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary",
                               "-annotateWithFinger", "-uiTestPencil",
                               "-seedChordChart"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["library-search"]
                        .waitForExistence(timeout: 90))
        openArrangement(firstArrangement)
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "the score never engraved")
        sleep(10)
    }

    // NOT covered end to end: selecting a chord symbol with the Pencil and
    // driving the chip's row. Three attempts at it were deleted rather than
    // left flaky -- a lasso has to land on a small target whose position
    // depends on the engraving, and a sweep from 6% to 46% of the page caught
    // notes and rests but never an all-chord-symbol selection. What IS covered:
    // the row's whole behaviour in ChordAdjustSessionTests (28 cases: the step,
    // the clamps, the ladder, pending, revert, reset, what commits), the
    // fixture above, the Chord symbols screen below, and the engine journey in
    // check_adjust_journey.py. The gap is the gesture, and it is recorded in
    // BACKLOG.md rather than papered over.

    /// The part-wide half: a default every symbol inherits, and the way out of
    /// every override.
    func testTheChordSymbolsScreenCarriesTheDefaultAndTheResetAll() {
        openScoreWithChords()
        app.buttons["score-more"].tap()
        let display = menuRow("more-display")
        XCTAssertTrue(display.waitForExistence(timeout: 20), "no Score display row")
        display.tap()
        let chords = menuRow("display-chords")
        XCTAssertTrue(chords.waitForExistence(timeout: 10), "no Chord symbols row")
        chords.tap()

        XCTAssertTrue(app.staticTexts["chords-size"].waitForExistence(timeout: 10),
                      "no default size on the Chord symbols screen")
        XCTAssertTrue(app.buttons["chords-bigger"].exists)
        XCTAssertTrue(app.buttons["chords-smaller"].exists)

        // reset-all is two-step and inline, never a dialog
        let resetAll = menuRow("chords-reset-all")
        XCTAssertTrue(resetAll.exists, "no reset-all")
        resetAll.tap()
        XCTAssertTrue(app.buttons["chords-confirm-reset"].waitForExistence(timeout: 10),
                      "reset-all should ask first, inline")
        XCTAssertTrue(app.buttons["chords-confirm-reset-keep"].exists,
                      "and offer a way out")
        shot("chords-screen")
    }

    // MARK: - Where am I in the score

    /// The bar readout followed the PAGE, not the viewport: zoomed into bar 30
    /// it still said bar 1, because it took every measure on the visible page.
    /// It reads the visible rect now.
    func testTheBarCounterFollowsTheViewportNotThePage() {
        openArrangement(firstArrangement)
        let canvas = app.scrollViews["score-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 180), "the score never engraved")
        sleep(8)

        let counter = app.staticTexts["counter-bar"]
        XCTAssertTrue(counter.waitForExistence(timeout: 30),
                      "no bar counter in the top bar")
        let atFit = counter.label
        XCTAssertTrue(atFit.hasPrefix("bar "), "the counter should name a bar: \(atFit)")
        let firstBar = Int(atFit.replacingOccurrences(of: "bar ", with: "")) ?? -1
        XCTAssertGreaterThan(firstBar, 0, "a bar number should be positive: \(atFit)")
        shot("bar-counter-at-fit")

        // Zoom in HARD, then pan toward the end of the page. One pinch of 3x
        // only reached 1.17x -- measured -- which left 83% of the page on
        // screen and bar 1 always in it, so the assertion below could not fail
        // for the right reason either.
        for _ in 0..<3 {
            canvas.pinch(withScale: 4.0, velocity: 3.0)
            sleep(1)
        }
        sleep(3)
        for _ in 0..<3 {
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.55))
                .press(forDuration: 0.05,
                       thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)))
            sleep(1)
        }
        sleep(4)

        let after = app.staticTexts["counter-bar"]
        XCTAssertTrue(after.exists, "the counter disappeared once zoomed")
        let laterBar = Int(after.label.replacingOccurrences(of: "bar ", with: "")) ?? -1
        // STRICTLY greater: the page-based counter this replaced would report
        // the same bar no matter where the reader panned, so an >= assertion
        // would pass against the bug it exists to catch.
        XCTAssertGreaterThan(laterBar, firstBar,
            "the counter did not follow the viewport: \(atFit) -> \(after.label) "
            + "pages=\(app.staticTexts["counter-pages"].label)")
        shot("bar-counter-zoomed")
    }

    // MARK: - Share & export

    /// The `Share & export` row used to push to a section with no `case`, so it
    /// landed on a note saying exporting happens in the engine -- which is not
    /// somewhere an iPad user can go. It offers the three formats now.
    func testShareAndExportOffersTheThreeFormats() {
        openArrangement(firstArrangement)
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "the score never engraved")
        app.buttons["score-more"].tap()
        let row = menuRow("more-export")
        XCTAssertTrue(row.waitForExistence(timeout: 20), "no Share & export row")
        row.tap()
        for format in ["musicxml", "midi", "pdf"] {
            XCTAssertTrue(menuRow("export-\(format)").waitForExistence(timeout: 10),
                          "no \(format) row on the export screen")
        }
        shot("share-and-export")
    }

    /// Tapping a format writes a real file and hands it to Apple's share sheet
    /// -- the one modal in the app, and the system's rather than ours.
    func testExportingMusicXMLRaisesTheSystemShareSheet() {
        openArrangement(firstArrangement)
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "the score never engraved")
        app.buttons["score-more"].tap()
        menuRow("more-export").tap()
        let musicxml = menuRow("export-musicxml")
        XCTAssertTrue(musicxml.waitForExistence(timeout: 20))
        musicxml.tap()

        // the share sheet is the system's, so it is identified by what it
        // always carries rather than by an identifier of ours
        let sheet = app.otherElements["ActivityListView"]
        let copy = app.buttons["Copy"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 60) || copy.waitForExistence(timeout: 60),
                      "exporting produced no share sheet")
        shot("share-sheet")
        // and PUT IT AWAY. This is the system's sheet, the one modal the app
        // is allowed, and it was left standing: whichever test ran next then
        // tapped into it instead of the app and failed somewhere unrelated --
        // twice in one evening, in two different tests, at the same assertion.
        dismissSystemSheet()
    }

    /// Close the share sheet, however this iOS names its way out.
    private func dismissSystemSheet() {
        for label in ["Close", "Cancel", "Done"] where app.buttons[label].exists {
            app.buttons[label].tap()
            if waitForDisappearance(of: app.otherElements["ActivityListView"], timeout: 5) {
                return
            }
        }
        // no button: tap the ground above it, which is how a sheet is dismissed
        if app.otherElements["ActivityListView"].exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()
        }
    }

    /// The title in the score bar opens a band listing the piece's other
    /// arrangements and this arrangement's recent versions -- the one place
    /// switching happens while you are reading (§6.3).
    func testTheTitleBandOpensFromTheScoreTitle() {
        openArrangement(firstArrangement)
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "the score never engraved")
        let title = app.buttons["score-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 20), "no title in the score bar")
        title.tap()
        XCTAssertTrue(title.isSelected, "the title does not show that it is open")
        // both columns, by their rows: an identifier on the band itself would
        // be inherited by the columns and swallow every row in them
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "menu-arrangement-"))
                        .firstMatch.waitForExistence(timeout: 20),
                      "the band lists no arrangements")
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "menu-version-"))
                        .firstMatch.waitForExistence(timeout: 20),
                      "tapping the title did not open the band")
        shot("title-band")
        title.tap()
        XCTAssertTrue(waitForDisappearance(of: app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "menu-version-"))
                        .firstMatch, timeout: 10),
                      "the band did not close again")
    }

    /// The old yellow-band highlight is gone, replaced by a real selection.
    func testTheOldHighlightFeatureIsGone() {
        openArrangement(firstArrangement)
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180))
        let more = app.buttons["score-more"]
        XCTAssertTrue(more.isHittable, "the … button is not tappable")
        more.tap()
        XCTAssertTrue(more.isSelected, "the … button did not take: the action never ran")
        XCTAssertFalse(app.buttons["Highlight a passage for chat"].exists,
                       "the bar-estimate highlight toggle is still in the options menu")
        // Performance mode is the app's own PanelToggle now, not a stock iOS
        // Toggle and not a bare label (L33), so it is exposed as a SWITCH --
        // which is what it should have been reported as all along.
        let performance = app.descendants(matching: .any)["more-performance"].firstMatch
        XCTAssertTrue(performance.waitForExistence(timeout: 5),
                      "the … menu did not open (no Performance mode row)")
        XCTAssertTrue(app.switches["Performance mode"].exists,
                      "Performance mode is not a switch to a screen reader")
        // by identifier rather than by type: a menu row is a stack inside a
        // Button, which XCUITest reports as a container rather than a button --
        // the same reason the canvas is looked up this way
        let annotations = menuRow("more-annotations")
        XCTAssertTrue(annotations.waitForExistence(timeout: 5),
                      "the … menu opened but Annotations is unreachable")
        annotations.tap()
        XCTAssertTrue(menuRow("annotations-clear").waitForExistence(timeout: 5),
                      "clearing markup lost its home")
        // the options are SCREENS now, so a sub-screen is left by the same
        // "Back to …" button every other screen uses
        goBack()
    }

    /// Draw across a bar: the elements under the stroke are
    /// selected, the chip says what was caught, chat opens by itself, and the
    /// reference lands in the input ready to be typed against.
    func testLassoSelectsElementsAndHandsThemToChat() {
        withPencilStandIn()
        openArrangement(firstArrangement)
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
        // the chip is now named by its headline ("3 elements from bar 15"),
        // so it is found by identifier rather than by a fixed word
        let chip = app.staticTexts["selection-chip"]
        var caught = false
        for y in [0.30, 0.20, 0.42, 0.55] where !caught {
            let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: y))
            let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: y))
            // hold past the threshold, then drag: the gesture a person makes
            start.press(forDuration: 0.6, thenDragTo: end)
            caught = chip.waitForExistence(timeout: 8)
        }
        XCTAssertTrue(caught, "nothing was selected by any stroke across the page")
        shot("selection-made")

        // Nothing may have reached chat yet: a lasso is not a request to type.
        XCTAssertFalse(app.buttons["Close chat"].exists,
                       "a lasso opened chat by itself; it must wait to be confirmed")

        // the chip says what was caught, in the user's terms
        let headline = chip.label
        XCTAssertTrue(headline.contains("element") && headline.contains("bar"),
                      "the chip should say how many elements and which bar: \(headline)")
        XCTAssertFalse(app.buttons["combine-replace"].exists,
                       "the Replace/Add/Subtract modes should be gone")
        XCTAssertFalse(app.buttons["combine-subtract"].exists)

        // hand it over deliberately
        let confirm = app.buttons["selection-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "no Use in chat button")
        confirm.tap()

        XCTAssertTrue(app.buttons["Close chat"].waitForExistence(timeout: 20),
                      "confirming the selection should open chat")
        let input = app.textFields["chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "no chat input")
        let value = (input.value as? String) ?? ""
        XCTAssertTrue(value.contains("[selection:"),
                      "the selection reference did not reach the chat input: \(value)")
        XCTAssertTrue(value.contains("bar"), "the reference should name bars: \(value)")
        shot("selection-in-chat")
    }
    /// Ali turns edit mode off from the PILL, and the ink bar stayed on screen.
    /// The existing test switches it off with the bar's own "Finish annotating"
    /// button, which is a different path -- and the bar's visibility is decided
    /// by a view that reads the annotation controller without observing it, so
    /// it only updated when something else happened to redraw the score pane.
    func testTheInkBarFollowsThePillToggleBothWays() {
        openArrangement(firstArrangement)
        let markup = app.buttons["score-edit"]
        XCTAssertTrue(markup.waitForExistence(timeout: 60))
        XCTAssertFalse(app.buttons["Draw"].exists, "the ink bar should start hidden")

        markup.tap()
        XCTAssertTrue(app.buttons["Draw"].waitForExistence(timeout: 10),
                      "the ink bar did not appear when edit mode was turned on")

        markup.tap()
        XCTAssertTrue(waitForDisappearance(of: app.buttons["Draw"], timeout: 10),
                      "the ink bar is still on screen after edit mode was turned off")
        XCTAssertFalse(app.buttons["Erase"].exists, "the eraser outlived the mode")
        XCTAssertFalse(app.buttons["Red pen"].exists, "the colours outlived the mode")
        shot("ink-bar-hidden-with-mode-off")

        // and it comes back
        markup.tap()
        XCTAssertTrue(app.buttons["Draw"].waitForExistence(timeout: 10),
                      "the ink bar did not come back when edit mode was turned on again")
        markup.tap()
        XCTAssertTrue(waitForDisappearance(of: app.buttons["Draw"], timeout: 10))
    }

    // MARK: - An arrangement with nothing in it

    /// Ali's device grew a "Morrison's jig" with ZERO versions. Tapping it sat
    /// on "Opening…" for ever: `renderIfNeeded` returns at its guard when there
    /// is no version to display, so nothing was ever in flight and the spinner
    /// was simply the fallback branch with no way out.
    func testAnArrangementWithNoVersionsSaysSoAndCanBeDeleted() {

        app.terminate()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary",
                               "-annotateWithFinger", "-seedBrokenArrangement"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["library-search"]
                        .waitForExistence(timeout: 90))
        app.buttons["segment-pieces"].tap()

        // it has no piece, so it sits in the library on its own
        let broken = app.buttons["row-broken-arrangement"]
        XCTAssertTrue(broken.waitForExistence(timeout: 60),
                      "the version-less arrangement is not in the library")
        XCTAssertTrue(broken.label.contains("0 versions"),
                      "expected it to admit it has no versions: \(broken.label)")
        broken.tap()

        // it must say what is wrong rather than spin
        XCTAssertTrue(app.staticTexts["Nothing to show"].waitForExistence(timeout: 30),
                      "a version-less arrangement should explain itself, not spin")
        XCTAssertFalse(app.staticTexts["Opening…"].exists,
                       "still showing the spinner for an arrangement that can never load")
        shot("version-less-arrangement")

        // and there is a way out, right there
        // found by label: an identifier on the StateView container would be
        // inherited by this button, which is what hid the chip's mode buttons
        let delete = app.buttons["Delete this arrangement"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10),
                      "no way to delete it from the screen that tells you it is broken")
        delete.tap()
        if app.buttons["Delete"].waitForExistence(timeout: 10) { app.buttons["Delete"].tap() }

        XCTAssertTrue(waitForDisappearance(of: broken, timeout: 40),
                      "the broken arrangement is still in the library after deleting it")
        shot("version-less-arrangement-deleted")
    }

    // MARK: - Hold-then-drag, and what it must not break

    /// A finger never selects, at any speed or duration. The hand moves the
    /// paper and nothing else; only the Pencil selects. If this fails the score
    /// is unreadable — every attempt to scroll would lasso instead.
    ///
    /// Launched WITHOUT the Pencil stand-in, so these really are fingers.
    func testAFingerNeverSelectsHoweverItDrags() {
        openArrangement(firstArrangement)
        let canvas = app.scrollViews["score-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 180), "the score never engraved")
        sleep(12)

        // quick drags (a scroll), and slow held ones (what the old finger
        // lasso needed) -- neither may select
        for (hold, dy) in [(0.05, 0.55), (0.05, 0.45), (0.6, 0.40), (1.0, 0.35)] {
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy))
                .press(forDuration: hold,
                       thenDragTo: canvas.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.85, dy: dy)))
        }
        XCTAssertFalse(app.staticTexts["selection-chip"].waitForExistence(timeout: 4),
                       "a finger selected something; fingers only pan and zoom")
        shot("finger-never-selects")
    }

    /// Two fingers, tapped and gone, undo the last stroke -- and it must work
    /// with markup mode OFF, which is where it was lost: the recognizer used to
    /// live on the PencilKit canvas, which only takes touches while markup is on.
    func testTwoFingerTapUndoesEvenWithMarkupOff() {
        openArrangement(firstArrangement)
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "the score never engraved")
        sleep(10)
        app.buttons["score-edit"].tap()
        XCTAssertTrue(app.buttons["Draw"].waitForExistence(timeout: 10), "no ink bar")

        let canvas = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas-"))
            .firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 20), "no annotation canvas")
        func strokes() -> Int {
            Int((canvas.value as? String)?
                .replacingOccurrences(of: " strokes", with: "") ?? "-1") ?? -1
        }
        for _ in 0..<3 where strokes() < 1 {
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.45))
                .press(forDuration: 0.05,
                       thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.45)))
            if strokes() >= 1 { break }
            sleep(2)
        }
        XCTAssertEqual(strokes(), 1, "the stroke did not land")

        // leave markup mode: this is where the gesture used to stop working
        app.buttons["score-edit"].tap()
        XCTAssertTrue(waitForDisappearance(of: app.buttons["Draw"], timeout: 10),
                      "markup mode did not close")

        // tap on the page, not the scroll view: XCUITest cannot compute a
        // two-finger gesture on a scroll view element. The touches land on the
        // recognizer either way -- it lives on the scroll view beneath.
        canvas.twoFingerTap()
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline && strokes() != 0 { usleep(200_000) }
        XCTAssertEqual(strokes(), 0,
                       "two-finger tap did not undo the stroke with markup off")
        shot("two-finger-undo-outside-markup")
    }

    /// The chip describes the selection in the user's terms and hands it over
    /// only when asked. The Replace/Add/Subtract modes are gone: adding is a
    /// held finger now, and the modes were a trap (Subtract emptied the
    /// selection, which hid the chip, which was the only way out of Subtract).
    func testTheChipNamesTheSelectionAndHasNoModes() {
        withPencilStandIn()
        openArrangement(firstArrangement)
        let canvas = app.scrollViews["score-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 180), "the score never engraved")
        sleep(12)

        var caught = false
        for y in [0.30, 0.20, 0.42] where !caught {
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: y))
                .press(forDuration: 0.6,
                       thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: y)))
            caught = app.staticTexts["selection-chip"].waitForExistence(timeout: 8)
        }
        guard caught else { return XCTFail("nothing was selected") }

        let headline = app.staticTexts["selection-chip"].label
        XCTAssertTrue(headline.contains("element"),
                      "the chip should count what was caught: \(headline)")
        XCTAssertTrue(headline.lowercased().contains("bar"),
                      "the chip should name the bar: \(headline)")

        // Staff and voice, which were in every address and never shown.
        //
        // Staff is always there. Voice is not asserted here, and deliberately:
        // layer 0 is the parser's "not layer-specific" marker, and elements
        // that live under the <measure> rather than inside a <layer> -- chord
        // symbols, dynamics -- legitimately have no voice. A lasso can catch
        // only those, and did on this arrangement. That the voice is FORMATTED
        // correctly when there is one is settled by SelectionCombineTests,
        // which can state the addresses exactly instead of hoping a stroke
        // catches the right kind of thing.
        XCTAssertTrue(app.staticTexts["selection-place"].exists,
                      "the chip should say where the selection is")
        let place = app.staticTexts["selection-place"].label
        XCTAssertTrue(place.contains("staff") || place.contains("staves"),
                      "no staff in the chip: \(place)")
        if place.contains("voice") {
            // "staves 3, 4 · voice 1" -- the plural does not contain "staff",
            // which is what my own first version of this assertion assumed
            XCTAssertTrue((place.contains("staff") || place.contains("staves"))
                            && place.contains("·"),
                          "the place line is malformed: \(place)")
        }

        // the modes are gone, and with them the trap
        for mode in ["combine-replace", "combine-add", "combine-subtract"] {
            XCTAssertFalse(app.buttons[mode].exists, "\(mode) is still on the chip")
        }
        shot("selection-chip-redesigned")
    }

    func testANewArrangementCanBeAddedToASetList() {

        // The seed assigns set lists only after every import, so this waits for
        // the fixture it depends on -- in the Setlists half of the library,
        // where a set list is a row like any other.
        resetToLibraryRoot()
        app.buttons["segment-setlists"].tap()
        let seededSetlist = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "row-")).firstMatch
        XCTAssertTrue(seededSetlist.waitForExistence(timeout: 180),
                      "the seed never created a set list to add to")

        openPieceSheet()
        // blank-or-import is two visible rows now, not a menu
        app.buttons["piece-new-arrangement-\(pieceSlug)"].tap()

        // it lands as #3 of the piece (the seed files two)
        let row = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Arrangement number 3")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 180),
                      "the new arrangement never appeared in the piece")
        shot("journey-new-arrangement")

        // into a set list from its own screen, reached by the row's ☰. The new
        // arrangement's slug is not known here, so the ☰ is found by position:
        // it is the one on the row that says #3.
        let menu = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "row-menu-"))
        XCTAssertTrue(menu.count >= 3, "no ☰ on the new arrangement's row")
        tapAnyway(menu.element(boundBy: 2), in: app.scrollViews.firstMatch)
        let addToSet = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "arrangement-setlists-")).firstMatch
        guard addToSet.waitForExistence(timeout: 15) else {
            return XCTFail("the arrangement screen does not offer set lists")
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
        goBack()

        // and it now shows in that set list's own screen, as well as keeping
        // its place in the piece
        resetToLibraryRoot()
        app.buttons["segment-setlists"].tap()
        let setlistRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "row-")).firstMatch
        XCTAssertTrue(setlistRow.waitForExistence(timeout: 40),
                      "no set list \(setlistName) to look in")
        // the ☰, not the row: tapping a set-list row PLAYS it from the top,
        // which is what a set list is for
        let setlistMenu = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "row-menu-")).firstMatch
        XCTAssertTrue(setlistMenu.waitForExistence(timeout: 20), "no ☰ on the set list")
        setlistMenu.tap()
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "setlist-member-"))
                        .firstMatch.waitForExistence(timeout: 30),
                      "nothing is listed under set list \(setlistName)")

        openPieceSheet()
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Arrangement number 3")).firstMatch.exists,
                      "the arrangement lost its place in the piece when it joined a set list")
        shot("journey-in-setlist")
    }

    /// A drawing belongs to the version it was made on. Switching versions must
    /// not carry someone's pencil marks onto a different engraving.
    func testAnnotationsBelongToTheVersionTheyWereMadeOn() {
        openArrangement(firstArrangement)
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "the score never engraved")
        sleep(10)
        ensureASecondVersion()
        app.buttons["score-edit"].tap()
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
        app.buttons["score-edit"].tap()   // leave markup mode

        // switch to an earlier version, from the title dropdown -- which is
        // where switching version lives now, and where a reader would do it
        app.buttons["score-title"].tap()
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "menu-version-"))
                        .firstMatch.waitForExistence(timeout: 20),
                      "the title band never opened")
        let rows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "menu-version-"))
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
    /// L35: the chat box's resize grip STAYS. Ali chose it over a two-width
    /// toggle, and it is one of the two sanctioned drags in the app
    /// (NAV_MODAL_FREE_0.4.2 §4B.1) -- so a future "remove every drag" pass
    /// fails here rather than quietly taking it away.
    func testTheChatBoxKeepsItsResizeGrip() {
        openArrangement(firstArrangement)
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "the score never engraved")
        app.buttons["score-ask"].tap()

        let grip = app.descendants(matching: .any)["chat-input-grip"].firstMatch
        XCTAssertTrue(grip.waitForExistence(timeout: 20),
                      "the chat box's resize grip is gone")
        // the grip publishes the size it is set to, which is what it is for
        let before = grip.value as? String ?? ""
        print("GRIP before: \(before)")

        // Drag whichever way has room. The size is remembered between runs,
        // so a test that always drags UP asserts nothing once someone has left
        // it at the 14-line maximum -- which is exactly how this first failed.
        let lines = Int(before.split(separator: " ").first ?? "") ?? 0
        let canvas = app.windows.firstMatch
        let from = grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = canvas.coordinate(withNormalizedOffset:
                                    CGVector(dx: 0.82, dy: lines >= 8 ? 0.92 : 0.45))
        from.press(forDuration: 0.15, thenDragTo: to)
        sleep(1)
        let after = grip.value as? String ?? ""
        print("GRIP after: \(after)")
        XCTAssertNotEqual(after, before,
                          "dragging the grip did not resize the box (\(before))")
        shot("chat-grip-resized")
        app.buttons["Close chat"].tap()
    }

    /// #44: running an op on a selection keeps the selection, and keeps the
    /// page you were on. Every op makes a version, and the render path used to
    /// treat that exactly like opening a different arrangement -- blanking the
    /// canvas, resetting to page 1, and clearing the selection the op had just
    /// been run on.
    func testATransformKeepsTheSelectionAndThePage() {
        openArrangement(firstArrangement)
        withPencilStandIn()
        openArrangement(firstArrangement)
        let canvas = app.scrollViews["score-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 180), "the score never engraved")
        sleep(12)

        var caught = false
        for y in [0.30, 0.20, 0.42] where !caught {
            let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: y))
            start.press(forDuration: 0.6,
                        thenDragTo: canvas.coordinate(
                            withNormalizedOffset: CGVector(dx: 0.62, dy: y)))
            caught = app.staticTexts["selection-chip"].waitForExistence(timeout: 8)
        }
        guard caught else { return XCTFail("nothing was selected on the page") }
        if app.buttons["Close chat"].exists { app.buttons["Close chat"].tap() }
        let before = app.staticTexts["selection-chip"].label
        let pageBefore = app.staticTexts["counter-pages"].label
        shot("transform-selection-before")

        // a real op through the … menu, which bumps the version
        ensureASecondVersion()

        let chip = app.staticTexts["selection-chip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 40),
                      "the selection was lost by the transform (was \(before))")
        // The page they are ON, not the whole readout: a transform can change
        // how many pages the score HAS -- this one engraves to 8 where it was
        // 9 -- and that is the score changing, not the reader being moved.
        func pageNumber(_ label: String) -> String {
            label.split(separator: "/").first.map {
                $0.trimmingCharacters(in: .whitespaces)
            } ?? label
        }
        XCTAssertEqual(pageNumber(app.staticTexts["counter-pages"].label),
                       pageNumber(pageBefore),
                       "the transform moved the reader off their page "
                       + "(\(pageBefore) -> \(app.staticTexts["counter-pages"].label))")
        XCTAssertTrue(canvas.exists, "the canvas did not come back")
        shot("transform-selection-after")
    }

    /// must not leave a stale selection pointing at bars of a different score.
    func testSwitchingVersionClearsAStaleSelection() {
        openArrangement(firstArrangement)
        withPencilStandIn()
        openArrangement(firstArrangement)
        let canvas = app.scrollViews["score-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 180), "the score never engraved")
        sleep(12)
        ensureASecondVersion()

        var caught = false
        for y in [0.30, 0.20, 0.42] where !caught {
            let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: y))
            start.press(forDuration: 0.6,
                        thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: y)))
            caught = app.staticTexts["selection-chip"].waitForExistence(timeout: 8)
        }
        guard caught else { return XCTFail("nothing was selected on the page") }
        if app.buttons["Close chat"].exists { app.buttons["Close chat"].tap() }

        app.buttons["score-title"].tap()
        // wait for the band, then count: counting a query the instant after a
        // tap counts an empty screen
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "menu-version-"))
                        .firstMatch.waitForExistence(timeout: 20),
                      "the title band never opened")
        let rows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "menu-version-"))
        guard rows.count > 1 else { return XCTFail("need two versions in the dropdown") }
        rows.element(boundBy: rows.count - 1).tap()

        XCTAssertTrue(waitForDisappearance(of: app.staticTexts["selection-chip"], timeout: 40),
                      "the selection from the previous version is still showing")
        shot("journey-selection-cleared-on-version-switch")
    }

    // MARK: - Version selection

    /// Clicking through an arrangement's versions must light exactly one row.
    /// A prompt group's steps include the group's own face version, so the
    /// group row and a step row both claimed the highlight and it read as two
    /// versions being open at once.
    func testOnlyOneVersionRowIsEverHighlighted() {

        openPieceSheet()
        let arrangement = app.buttons["arrangement-choice-\(firstArrangement)"]
        XCTAssertTrue(arrangement.waitForExistence(timeout: 20),
                      "the arrangement is not listed under its piece")
        arrangement.tap()
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "the score never finished engraving")

        // Make the second version this test needs rather than hoping the seed
        // left one behind: how many versions a freshly seeded arrangement has
        // is incidental, and the run where it had one made this test fail for
        // a reason that had nothing to do with highlighting.
        ensureASecondVersion()

        openArrangementScreen(firstArrangement)
        app.buttons["edit-versions-\(firstArrangement)"].tap()

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
    // MARK: - Two pages side by side

    /// The risk in a spread is that the right-hand page selects from its
    /// neighbour: two pages now share a row, and a lasso has to resolve to the
    /// page it was actually drawn on. Bars run forward through the score, so
    /// the right page must give higher bar numbers than the left.
    func testALassoOnTheRightHandPageSelectsFromThatPage() {
        withPencilStandIn()
        setTwoPageSpread(on: true)
        openArrangement(firstArrangement)
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
        closeSettings()
    }

    private func setTwoPageSpread(on: Bool) {
        app.buttons["Settings"].firstMatch.tap()
        let toggle = app.switches["Two pages side by side"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "no two-page toggle in settings")
        if (toggle.value as? String == "1") != on { toggle.tap() }
        XCTAssertEqual(toggle.value as? String, on ? "1" : "0")
        closeSettings()
    }

    /// Drag a lasso across a horizontal band and return the first bar number
    /// of whatever it caught. Which y holds notes depends on where the page
    /// sits, so try a few bands rather than pinning one magic number.
    /// The bar a lasso caught, read from the CHIP rather than from chat.
    ///
    /// The chip says "N elements from bar X" the moment a lasso lands, with no
    /// confirming and no chat -- which matters here because confirming opens
    /// the chat panel, takes 380pt off the canvas, and moves every normalized
    /// offset a second lasso would aim at. Reading the chip leaves the canvas
    /// exactly as it was found.
    private func lassoBars(on canvas: XCUIElement,
                           from dxStart: CGFloat, to dxEnd: CGFloat) -> Int? {
        let chip = app.staticTexts["selection-chip"]
        for dy in [0.30, 0.20, 0.42, 0.55, 0.12] {
            canvas.coordinate(withNormalizedOffset: CGVector(dx: dxStart, dy: dy))
                .press(forDuration: 0.6,
                       thenDragTo: canvas.coordinate(
                        withNormalizedOffset: CGVector(dx: dxEnd, dy: dy)))
            guard chip.waitForExistence(timeout: 8) else { continue }
            if let bar = lastBarNumber(in: chip.label) { return bar }
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
        openArrangement(firstArrangement)
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
    func testPieceIsRenamedByTappingItsName() {

        openPieceSheet()
        let title = app.buttons["piece-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 20), "no piece name to tap")
        title.tap()
        let field = app.textFields["piece-title-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10),
                      "tapping the name should open it for editing in place")
        XCTAssertFalse(app.buttons["Rename"].exists,
                       "nothing offers a Rename button any more")
        replaceText(field, with: "Paris Revisited")
        field.typeText("\n")           // Done commits, as it does for a file name
        XCTAssertTrue(app.buttons["piece-title"].waitForExistence(timeout: 30),
                      "the name never went back to being a name")
        XCTAssertTrue(element(labelStartingWith: "Paris Revisited")
                        .waitForExistence(timeout: 30),
                      "the piece heading still shows the old name")
        shot("piece-renamed")
    }

    /// Ali's build-125 ask: a set list holds ARRANGEMENTS. Creating one asks
    /// for the name first, then offers arrangements to put in it.
    func testNewSetlistAsksForANameThenOffersArrangements() {

        app.buttons["segment-setlists"].tap()
        // New set list is permanently on the action row now; the + that used
        // to hold it is gone (§4C)
        app.buttons["library-new-setlist"].tap()
        // naming happens in a band at the top of the list, not in an alert
        let field = app.textFields["inline-rename-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no field to name it in")
        XCTAssertTrue(app.buttons["inline-rename-save"].exists,
                      "no way to commit the name")
        XCTAssertFalse(app.buttons["OK"].exists, "nothing in this app says OK")
        field.tap()
        field.typeText("Gig night")
        shot("setlist-name-first")
        app.buttons["inline-rename-save"].tap()

        // the picker opens on the new set list, listing arrangements
        XCTAssertTrue(app.staticTexts["Add arrangements"].waitForExistence(timeout: 20),
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
        goBack()

        // and the set list's own screen, reached by its ☰, lists it
        let gigMenu = app.buttons["row-menu-gig-night"]
        XCTAssertTrue(gigMenu.waitForExistence(timeout: 20),
                      "the new set list is not in the library")
        gigMenu.tap()
        XCTAssertTrue(app.buttons["setlist-member-\(firstArrangement)"]
                        .waitForExistence(timeout: 20),
                      "the set list does not list the arrangement")

        // clean up so repeat runs stay deterministic: Edit mode, select, delete
        resetToLibraryRoot()
        app.buttons["segment-setlists"].tap()
        app.buttons["library-edit"].tap()
        let pick = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "row-select-")).firstMatch
        if pick.waitForExistence(timeout: 10) {
            pick.tap()
            if app.buttons["bar-delete"].waitForExistence(timeout: 10) {
                app.buttons["bar-delete"].tap()
            }
        }
    }

    /// The + on an existing set list adds arrangements to it.
    func testAddingAnArrangementToAnExistingSetlist() {
        app.buttons["segment-setlists"].tap()
        // the set list's own ☰ opens its screen; Add arrangements is a row on it
        let menu = app.buttons["row-menu-test-setlist"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20), "no ☰ on the seeded set list")
        menu.tap()
        let add = app.buttons["setlist-add-test-setlist"]
        XCTAssertTrue(add.waitForExistence(timeout: 20),
                      "the set list screen has no way to add arrangements")
        add.tap()
        XCTAssertTrue(app.staticTexts["IN THIS SET LIST"].waitForExistence(timeout: 10),
                      "the add-arrangements screen did not open")
        // the seed puts both arrangements in, so they are all members already
        XCTAssertTrue(app.buttons["picker-remove-\(firstArrangement)"].exists,
                      "the seeded set list should already hold the arrangements")
        shot("setlist-add-arrangements")
        goBack()
    }

    /// And an arrangement can be put in a set list from its own screen.
    ///
    /// Named for the ☰, not a context menu: long-press menus are gone from the
    /// app, and a test whose name says otherwise makes people think they are
    /// still there.
    func testArrangementScreenOffersAddToSetList() {
        openArrangementScreen(firstArrangement)
        let action = app.buttons["arrangement-setlists-\(firstArrangement)"]
        XCTAssertTrue(action.waitForExistence(timeout: 15),
                      "no way to add an arrangement to a set list from its screen")
        action.tap()
        XCTAssertTrue(app.buttons["chooser-test-setlist"].waitForExistence(timeout: 15),
                      "the set list chooser did not open")
        shot("add-to-setlist-chooser")
        goBack()
    }



    func testSettingsIsAPanel() {
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["ON-DEVICE ENGINE"].waitForExistence(timeout: 10),
                      "settings did not open")
        XCTAssertTrue(app.staticTexts["CHAT MODEL"].exists)
        shot("settings-sheet")
        closeSettings()
    }

    // MARK: - Markup

    func testMarkupModeAndTheInkBar() {
        openArrangement(firstArrangement)
        let markup = app.buttons["score-edit"]
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

    /// #45: in ink mode a two-finger pinch zoomed the ANNOTATION layer on its
    /// own -- the ink slid and flipped over a score that stayed put. The score
    /// owns zooming; the canvas is only ever told what scale to draw at.
    func testPinchingInInkModeZoomsTheScoreNotTheInk() {
        openArrangement(firstArrangement)
        let score = app.scrollViews["score-canvas"]
        XCTAssertTrue(score.waitForExistence(timeout: 180), "the score never engraved")
        sleep(5)
        func zoom() -> CGFloat {
            CGFloat(Double((score.value as? String)?
                .replacingOccurrences(of: "zoom ", with: "") ?? "0") ?? 0)
        }
        app.buttons["score-edit"].tap()
        XCTAssertTrue(app.buttons["Draw"].waitForExistence(timeout: 20), "no ink bar")
        let before = zoom()
        for _ in 0..<6 where zoom() < before * 1.4 {
            score.pinch(withScale: 3.0, velocity: 2.0)
        }
        sleep(2)
        XCTAssertGreaterThan(zoom(), before * 1.2,
                             "pinching in ink mode did not zoom the SCORE "
                             + "(\(before) -> \(zoom())) -- the ink layer took it")
        shot("ink-mode-zoom")
        app.buttons["Finish annotating"].tap()
    }

    /// Ali's #3: the ink tools floated over the middle of the score. They dock
    /// in the footer now, and the handle moves them off whatever they are
    /// covering -- with a tap to put them back, so a bar dragged somewhere
    /// awkward is never stranded.
    func testTheInkToolsDockAndCanBeMovedAndPutBack() {
        openArrangement(firstArrangement)
        let score = app.scrollViews["score-canvas"]
        XCTAssertTrue(score.waitForExistence(timeout: 180),
                      "the score never engraved")
        sleep(5)
        app.buttons["score-edit"].tap()
        XCTAssertTrue(app.buttons["Draw"].waitForExistence(timeout: 20),
                      "the ink bar did not open")

        let handle = app.descendants(matching: .any)["ink-bar-handle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 10), "no move handle")

        // docked: in the bottom of the pane, below the music rather than over it
        let docked = handle.frame
        XCTAssertGreaterThan(docked.midY, score.frame.midY,
                             "the tools should start in the footer, not mid-score")

        // the handle moves them
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1,
                   thenDragTo: score.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        sleep(1)
        let moved = handle.frame
        XCTAssertLessThan(moved.midY, docked.midY - 100,
                          "the handle did not move the tools: \(docked) -> \(moved)")

        // ...and a tap puts them back, which is the way home for anyone who
        // cannot drag
        handle.tap()
        sleep(1)
        XCTAssertEqual(handle.frame.midY, docked.midY, accuracy: 8,
                       "tapping the handle did not re-dock the tools")

        app.buttons["Finish annotating"].tap()
    }

    /// The build-116 bug: draw, undo, switch colour, draw, undo. The first
    /// stroke must not come back. Stroke counts are read off the canvas.
    func testAnnotationUndoAcrossColourChange() {
        openArrangement(firstArrangement)
        XCTAssertTrue(app.buttons["score-edit"].waitForExistence(timeout: 90),
                      "the markup toggle never appeared in the pill")
        app.buttons["score-edit"].tap()
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
        openArrangement(firstArrangement)
        // named, not firstMatch: the library panel hosts a scroll view too, and
        // firstMatch was pinching that instead of the score
        let score = app.scrollViews["score-canvas"]
        guard score.waitForExistence(timeout: 180) else {
            return XCTFail("no score canvas")
        }
        score.pinch(withScale: 2.2, velocity: 2.0)
        XCTAssertTrue(app.buttons["score-close"].exists, "the top bar should survive a zoom")
        score.pinch(withScale: 0.5, velocity: -2.0)
        XCTAssertTrue(app.buttons["score-close"].exists)
    }

    // MARK: - Adding

    func testAddMenuCreatesBlankArrangement() {
        openPieceSheet()
        // Blank-or-import used to be a Menu on one button. Menus are gone
        // (0.4.2 §2), so the choice is two visible rows on the piece screen --
        // which is the same choice, said out loud.
        let blank = app.buttons["piece-new-arrangement-\(pieceSlug)"]
        XCTAssertTrue(blank.waitForExistence(timeout: 20),
                      "the piece screen offers no way to make an arrangement")
        XCTAssertTrue(app.buttons["piece-import-\(pieceSlug)"].exists,
                      "...and no way to import one into the piece")
        blank.tap()
        //
        // Alphabetically first, so this is the suite's cold start: it pays for
        // the app launch, the Python engine's first import, the library reset
        // and re-seed, and the engrave of whatever the app opens by itself —
        // and only then waits for another engine round trip. The assertion is
        // unchanged: a new arrangement is #3 of its piece.
        sleep(6)
        XCTAssertTrue(element(labelStartingWith: "Arrangement number 3")
                        .waitForExistence(timeout: 180),
                      "the new arrangement did not appear as #3 of the piece")
    }

    /// Filing and deleting used to be a long press. They are rows on the
    /// arrangement screen now, reached by the row's ☰ -- visible, labelled, and
    /// reachable without knowing a gesture.
    func testTheArrangementScreenOffersFilingAndDeletion() {
        openArrangementScreen(firstArrangement)
        XCTAssertTrue(app.buttons["arrangement-move-\(firstArrangement)"].exists,
                      "no way to file this arrangement")
        XCTAssertTrue(app.buttons["edit-delete-\(firstArrangement)"].exists,
                      "no way to delete this arrangement")
        XCTAssertFalse(app.buttons["Move to piece"].exists,
                       "a long press should reach nothing at all now")
    }
}
