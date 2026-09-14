import XCTest

/// Rename on a book row (0.8.2), which 0.8.0 said it did not have "because
/// the engine has no rename for books". It has one now
/// (`workspace.rename_book`, step 1 of this build), and this is the row that
/// calls it.
///
/// What it asserts is the whole of the feature: the action is on the row, the
/// inline field takes a name, and the LIST shows it afterwards -- which is
/// what proves the engine call landed rather than the field having accepted
/// a keystroke.
final class BookRename: XCTestCase {
    var app: XCUIApplication!

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    func testABookRowRenamesTheBook() { renameFirstRow(inSegment: "books") }

    /// The SAME path on the list it has always been on, so a failure above can
    /// be told apart from a failure in the inline row itself.
    func testASetListRowStillRenames() { renameFirstRow(inSegment: "setlists") }

    private func renameFirstRow(inSegment segment: String) {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-resetViewPreferences",
                               "-seedTestLibrary", "-seedBigBook"]
        app.launch()
        _ = element("library-search").waitForExistence(timeout: 240)
        waitForTheLibraryToSettle(app)
        app.buttons["segment-\(segment)"].firstMatch.tap()

        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND NOT identifier BEGINSWITH %@",
            "row-", "row-menu-")).firstMatch
        guard row.waitForExistence(timeout: 240) else {
            return XCTFail("no row in \(segment)")
        }
        let before = row.label
        let menu = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "row-menu-")).firstMatch
        guard menu.waitForExistence(timeout: 30) else { return XCTFail("no ☰ on the row") }
        menu.tap()

        let rename = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "row-rename-")).firstMatch
        XCTAssertTrue(rename.waitForExistence(timeout: 10),
                      "no Rename on the \(segment) row")
        rename.tap()

        let field = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "inline-")).firstMatch
        guard field.waitForExistence(timeout: 10) else {
            return XCTFail("Rename opened no field")
        }
        field.tap()
        // Clear whatever the draft holds, then a name nothing else could have.
        if let text = field.value as? String, !text.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
        }
        let after = "Renamed by a test"
        field.typeText(after)
        // The field is asserted BEFORE Save: a rename that never landed and a
        // name that never reached the field look identical from the row.
        XCTAssertEqual(field.value as? String, after,
                       "the inline field does not hold the new name")
        let save = element("inline-rename-save")
        XCTAssertTrue(save.exists, "no Save on the inline row")
        save.tap()

        // The engine call is what this waits on: the row's own label changing.
        let renamed = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", after)).firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 120),
                      "the row still reads \"\(before)\": the rename never reached the list")
    }
}
