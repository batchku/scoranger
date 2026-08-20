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
        let collapse = app.buttons["Collapse setlist Samples"]
        XCTAssertTrue(collapse.exists, "setlist caret missing")
        collapse.tap()
        XCTAssertTrue(app.buttons["Expand setlist Samples"].waitForExistence(timeout: 5),
                      "setlist caret did not toggle")
        app.buttons["Expand setlist Samples"].tap()
        XCTAssertTrue(app.buttons["Collapse setlist Samples"].waitForExistence(timeout: 5))
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
        // and the sidebar's version history follows what the score pane shows
        XCTAssertTrue(element(labelStartingWith: "Versions of #1").waitForExistence(timeout: 10),
                      "sidebar did not show the open arrangement's versions")
        shot("row-tap-opens")
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
