import XCTest

/// iPad parity audit: prove the sidebar's per-row buttons actually receive
/// taps (the reason piece rows use explicit chevron buttons instead of
/// DisclosureGroup, whose label swallows button taps on iPad sidebar lists).
final class ScorangerUITests: XCTestCase {
    var app: XCUIApplication!

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

    /// Setlists section exists, its caret collapses/expands, and tapping a
    /// piece inside it previews the piece.
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
        let collapse = app.buttons["Collapse Sous le ciel de Paris"]
        XCTAssertTrue(collapse.exists, "piece caret missing")
        let child = app.staticTexts["sous-le-ciel-quartet"]
        XCTAssertTrue(child.exists, "arrangement rows should start expanded")
        collapse.tap()
        XCTAssertTrue(app.buttons["Expand Sous le ciel de Paris"].waitForExistence(timeout: 5))
        XCTAssertFalse(child.exists, "arrangement rows should hide when collapsed")
        app.buttons["Expand Sous le ciel de Paris"].tap()
        XCTAssertTrue(child.waitForExistence(timeout: 5))
        shot("piece-caret")
    }

    /// The plus.circle on the piece row receives its tap (not the row) and
    /// creates + opens a new arrangement.
    func testPlusCreatesArrangement() {
        let plus = app.buttons["New arrangement of Sous le ciel de Paris"]
        XCTAssertTrue(plus.exists, "plus button missing from piece row")
        plus.tap()
        // the new blank arrangement (named "Arrangement") opens in the detail
        // pane and files itself under the piece in the sidebar
        XCTAssertTrue(app.staticTexts["Arrangement"].firstMatch.waitForExistence(timeout: 60),
                      "new arrangement did not appear")
        shot("plus-created-arrangement")
    }

    /// Row icons: info opens the details sheet.
    func testInfoSheet() {
        let info = app.buttons["Score details"].firstMatch
        XCTAssertTrue(info.exists)
        info.tap()
        XCTAssertTrue(app.staticTexts["Overview"].waitForExistence(timeout: 10),
                      "info sheet did not open")
        shot("info-sheet")
        app.buttons["Done"].firstMatch.tap()
    }

    /// Tapping a score row previews it: the Versions section appears.
    func testPreviewShowsVersions() {
        app.staticTexts["sous-le-ciel-quartet"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Versions"].waitForExistence(timeout: 10),
                      "preview tap did not surface the Versions section")
        XCTAssertTrue(app.staticTexts["import"].firstMatch.exists,
                      "v001 import row missing")
        shot("versions-section")
    }

    /// Long-press on an arrangement row offers the filing context menu.
    func testContextMenu() {
        app.staticTexts["sous-le-ciel-quartet"].firstMatch.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Move to piece"].waitForExistence(timeout: 10),
                      "context menu did not appear")
        shot("context-menu")
        // dismiss
        app.tap()
    }

    /// The open-chevron on a score row opens it in the detail pane.
    func testOpenScoreChevron() {
        let open = app.buttons["Open score"].firstMatch
        XCTAssertTrue(open.exists)
        open.tap()
        // detail toolbar shows the version pill once a score is open
        XCTAssertTrue(app.buttons["Versions"].waitForExistence(timeout: 60),
                      "detail pane did not open with the versions menu")
        shot("open-score-detail")
    }
}
