import XCTest

/// Photographs for Ali's second and third lists of 2026-09-14: the score's
/// chrome (8, 9, 10), the settings gear (14), the library's create path
/// (12, 13, 15) and what its rows say they hold (11).
///
/// It asserts nothing about the product and cannot fail a build. It runs
/// against the tree before the change and the tree after, and takes the same
/// pictures either way, so the pair can be put side by side.
///
/// `-seedLibraryShape` is what makes two of them possible at all: a library of
/// one piece can never show a naming row landing off-screen, and the seeded
/// library files every score under a piece, so it can never show the unfiled
/// arrangement row that says "N versions" beside a piece row that says
/// "N arrangements".
final class ChromeShot: XCTestCase {

    private var app: XCUIApplication!

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func pause(_ seconds: TimeInterval) {
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "pause")],
                             timeout: seconds)
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-resetViewPreferences",
                               "-seedTestLibrary"] + extra
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        _ = element("library-search").waitForExistence(timeout: 240)
        // The row to wait for is one the library OPENS on. A LazyVStack has
        // not built a row several screens down, so waiting for the quartet in
        // a shaped library waits out the whole timeout and then carries on.
        let first = extra.contains("-seedLibraryShape")
            ? "row-all-blues" : "row-sous-le-ciel-de-paris"
        _ = element(first).waitForExistence(timeout: 240)
        pause(2)
    }

    // MARK: - 8, 9, 10: the score's chrome

    /// The reading screen, on the page that shows the fault: page 3 of the
    /// seeded quartet carries two systems and the rest of the sheet is blank.
    func testPhotographTheScoreChrome() {
        launch()
        let row = element("row-sous-le-ciel-de-paris")
        guard row.waitForExistence(timeout: 240) else {
            return XCTFail("the library never filled")
        }
        row.tap()
        let choice = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "arrangement-choice-")).firstMatch
        if choice.waitForExistence(timeout: 8) { choice.tap() }
        guard app.buttons["score-close"].waitForExistence(timeout: 240) else {
            return XCTFail("the score never opened")
        }
        pause(6)
        snap("score-chrome-page-1")

        // Page 3: two systems and a blank third of the sheet.
        let thumb = element("thumb-2")
        if thumb.waitForExistence(timeout: 30) {
            thumb.tap()
            pause(4)
            snap("score-chrome-page-3-two-systems")
        } else {
            print("SHOT: no thumbnail rail, so no page 3 picture")
        }
    }

    // MARK: - 14: the settings gear

    func testPhotographTheLibraryTopRow() {
        launch()
        snap("library-top-row-with-the-gear")
    }

    // MARK: - 11, 12, 13, 15: the library's rows and its create path

    /// Scrolled into the middle of a long library, then `+ New` tapped: what a
    /// reader sees, which on Ali's iPad was nothing at all.
    func testPhotographTheCreatePath() {
        launch(["-seedLibraryShape"])
        let list = app.scrollViews.firstMatch
        for _ in 0..<6 { list.swipeUp() }
        pause(1.5)
        snap("create-scrolled-into-the-list")

        element("library-new").tap()
        pause(1.5)
        snap("create-after-tapping-new")

        // The old route needed a second tap inside a panel; the new one does
        // not. Take whichever is there.
        let arrangement = element("library-new-arrangement")
        if arrangement.exists && arrangement.isHittable {
            arrangement.tap()
            pause(1.5)
            snap("create-after-choosing-in-the-panel")
        }
        let field = app.textFields["inline-rename-field"]
        if field.waitForExistence(timeout: 6) {
            let screen = app.windows.firstMatch.frame
            print("SHOT: the naming row exists; frame \(field.frame), "
                  + "screen \(screen), hittable \(field.isHittable)")
            print("SHOT: keyboards on screen = \(app.keyboards.count)")
        } else {
            print("SHOT: no naming row on screen at all")
        }
        snap("create-the-naming-row")

        // And on Set lists, which is the control Ali's own screenshot was.
        if app.buttons["inline-rename-cancel"].exists {
            app.buttons["inline-rename-cancel"].tap(); pause(1)
        }
        element("segment-setlists").tap(); pause(1)
        element("library-new").tap(); pause(1.5)
        let setlistRow = element("library-new-setlist")
        if setlistRow.exists && setlistRow.isHittable { setlistRow.tap(); pause(1.5) }
        snap("create-a-set-list")
    }

    /// The two row kinds in one picture: a piece that says how many
    /// arrangements it holds, and an arrangement that said how many versions
    /// it has.
    func testPhotographWhatTheRowsSayTheyHold() {
        launch(["-seedLibraryShape"])
        snap("rows-top-of-the-pieces-list")
        let unfiled = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                        "row-", "version")).firstMatch
        if unfiled.exists {
            print("SHOT: the unfiled row reads \"\(unfiled.label)\"")
        } else {
            print("SHOT: no row mentions versions")
        }
        let piece = element("row-sous-le-ciel-de-paris")
        if piece.exists { print("SHOT: the piece row reads \"\(piece.label)\"") }
        let list = app.scrollViews.firstMatch
        for _ in 0..<10 { list.swipeUp() }
        pause(1.5)
        snap("rows-further-down-the-pieces-list")
    }
}
