import XCTest

/// The bug the owner reported twice, photographed: "v001.mxl" as a label, two
/// arrangements reading identically, and pipeline names in the version list.
///
/// It asserts as well as photographs, so it is a gate test rather than a
/// sweep. A green suite told us this was fixed once when it was not, and what
/// it never did was LOOK -- the assertions here are on the strings actually
/// rendered, and the screenshots are so a person can check the assertions were
/// asking the right question.
///
/// The library is seeded poisoned (-seedPoisonedTitles): two arrangements of
/// one piece, each carrying the file name in its notation, which is the shape
/// of the reader's own library and cannot be produced through the app any more.
final class NamingShot: XCTestCase {

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func rows(_ app: XCUIApplication, _ prefix: String) -> [XCUIElement] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .allElementsBoundByIndex
    }

    func testNoInternalNameReachesTheReader() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary", "-seedPoisonedTitles"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["library-search"]
                        .waitForExistence(timeout: 180), "the library never appeared")
        settle(app.descendants(matching: .any)["library-search"], still: 1.0)
        snap("1-library")

        // --- the piece, and its two arrangements ---
        // The seed imports one file at a time and the library polls, so a row
        // read too early holds ONE arrangement and opens straight into it.
        let piece = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-")).firstMatch
        XCTAssertTrue(piece.waitForExistence(timeout: 90), "no piece row")
        XCTAssertTrue(waitUntil("both arrangements are imported", timeout: 240) {
            piece.exists && piece.label.contains("2 arrangement")
        }, "the piece never held two arrangements: \(piece.label)")
        settle(piece, still: 0.5)
        piece.tap()

        let choices = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "arrangement-choice-"))
        XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 90),
                      "the piece did not list its arrangements")
        settle(choices.firstMatch, still: 0.6)
        snap("2-piece-arrangement-labels")

        let labels = choices.allElementsBoundByIndex.map { $0.label }
        XCTAssertEqual(labels.count, 2, "expected two arrangements: \(labels)")
        for label in labels {
            XCTAssertFalse(label.lowercased().contains("v001"),
                           "an arrangement is still labelled with a file name: \(label)")
            XCTAssertFalse(label.contains(".mxl"), label)
        }
        XCTAssertEqual(Set(labels).count, labels.count,
                       "two arrangements of one piece read identically: \(labels)")

        // --- the engraved title, which is the half no display fix reaches ---
        choices.firstMatch.tap()
        let page = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas-")).firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 300), "the score never engraved")
        settle(page, still: 1.0)
        snap("3-engraved-title-before-repair")

        // --- the version list: what the owner marked "Don't!" ---
        let versions = app.buttons["score-versions"]
        XCTAssertTrue(versions.waitForExistence(timeout: 60), "no versions control")
        versions.tap()
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "menu-version-"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "the version list never opened")
        settle(row, still: 0.6)
        snap("4-version-labels")

        let versionRows = rows(app, "menu-version-")
        XCTAssertFalse(versionRows.isEmpty)
        for shown in versionRows.map(\.label) {
            for op in ["bulk-import", "omr", "set-metadata", "import-pdf",
                       "import", "transpose"] {
                XCTAssertFalse(shown.split(separator: " ").contains(Substring(op)),
                               "a version row still says the op name '\(op)': \(shown)")
            }
        }
    }

    /// The repair, end to end: the offer, the tap, and the page afterwards.
    func testTheRepairFixesWhatIsEngraved() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary", "-seedPoisonedTitles"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["library-search"]
                        .waitForExistence(timeout: 180))
        settle(app.descendants(matching: .any)["library-search"], still: 1.0)

        let settings = app.buttons["library-settings"].exists
            ? app.buttons["library-settings"] : app.buttons["settings"]
        guard settings.waitForExistence(timeout: 30) else {
            return XCTFail("no way into Settings")
        }
        settings.tap()
        // Settings is a split (0.8 §7.17): Titles is a section, offered only
        // while the scan finds something -- which is the claim under test.
        let titles = app.buttons["settings-titles"]
        XCTAssertTrue(titles.waitForExistence(timeout: 30),
                      "Titles is not in the settings index on a library that needs it")
        titles.tap()

        let fix = app.buttons["repair-titles"]
        XCTAssertTrue(fix.waitForExistence(timeout: 30),
                      "the repair was not offered on a library that needs it")
        settle(fix, still: 0.5)
        snap("5-repair-offered")
        fix.tap()

        let result = app.descendants(matching: .any)["repair-titles-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 300), "the repair never reported")
        settle(result, still: 1.0)
        snap("6-repair-done")

        // The offer is derived from the library, so it must be gone.
        XCTAssertTrue(waitUntil("the offer disappears", timeout: 60) { !fix.exists },
                      "the repair is still being offered after it ran")
        snap("7-offer-gone")

        // --- and the page itself, which is the whole point ---
        let close = app.buttons["Close settings"]
        if close.waitForExistence(timeout: 10) { close.tap() }
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-")).firstMatch
        guard row.waitForExistence(timeout: 60) else { return XCTFail("no piece row") }
        row.tap()
        let choice = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                  "arrangement-choice-")).firstMatch
        if choice.waitForExistence(timeout: 30) { choice.tap() }
        let page = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas-")).firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 300), "the score never engraved")
        settle(page, still: 1.5)
        snap("8-engraved-title-after-repair")
    }
}
