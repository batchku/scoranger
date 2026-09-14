import XCTest

/// REDESIGN_BRIEF_0.8 §7.6, the acceptance a screen has to give: the inline
/// naming row sits on the list's grid at one height, its parts are
/// addressable, and a set list made from a selection arrives with its
/// proposed name selected so one keystroke replaces it.
final class InlineCreate: XCTestCase {

    private var app: XCUIApplication!

    private func launch(size: String? = nil) {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-resetViewPreferences", "-seedTestLibrary"]
        if let size { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        let search = app.descendants(matching: .any)["library-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 240), "the library never appeared")
        _ = app.descendants(matching: .any)["row-sous-le-ciel-de-paris"].waitForExistence(timeout: 180)
        sleep(1)
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func openCreateRow(in segment: String) -> XCUIElement {
        element("segment-\(segment)").tap(); sleep(1)
        element("library-new").tap(); sleep(1)
        element(segment == "setlists" ? "library-new-setlist" : "library-new-arrangement").tap()
        let field = app.textFields["inline-rename-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no inline row in \(segment)")
        return field
    }

    // 1. inlineCreateAlignsWithTheList  3. inlineNameFieldIsAddressable
    func testTheRowSitsOnTheListsGridAndIsAddressable() {
        launch()
        // Set lists: the field at the title edge, Save at the ☰ column's edge.
        let field = openCreateRow(in: "setlists")
        XCTAssertTrue(element("inline-create-row").exists, "the container has no identifier")
        let row = element("row-test-setlist")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no seeded set list row")
        XCTAssertEqual(field.frame.minX, row.frame.minX + 20, accuracy: 1,
                       "the field's leading edge is not the row title's (s20)")
        // Save ends at the row's control edge (s8 in from the row's edge),
        // which is where the row's last control -- ☰, or Play on a set list
        // row -- ends too.
        let save = app.buttons["inline-rename-save"]
        let controls = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier CONTAINS %@ AND identifier != %@",
            "test-setlist", "row-test-setlist")).allElementsBoundByIndex
        let rightmost = controls.map(\.frame.maxX).max() ?? 0
        print("INLINE row controls: \(controls.map { "\($0.identifier) ends \($0.frame.maxX)" })")
        XCTAssertEqual(save.frame.maxX, rightmost, accuracy: 1,
                       "the row's last control ends at \(rightmost), Save at \(save.frame.maxX)")
        XCTAssertFalse(save.isEnabled, "Save should be disabled while the name is empty")
        field.typeText("Sunday")
        XCTAssertTrue(save.isEnabled, "Save should enable once there is a name")
        app.buttons["inline-rename-cancel"].tap()
        XCTAssertFalse(field.waitForExistence(timeout: 2), "Cancel should take the row away")

        // Pieces: the same component, the same edge.
        let pieceField = openCreateRow(in: "pieces")
        let piece = element("row-sous-le-ciel-de-paris")
        XCTAssertEqual(pieceField.frame.minX, piece.frame.minX + 20, accuracy: 1,
                       "in Pieces the field's leading edge is not the row title's")
        XCTAssertEqual(pieceField.placeholderValue, "Piece name")
        app.buttons["inline-rename-cancel"].tap()
    }

    // 2. inlineCreateIsOneHeight
    func testTheFieldAndBothButtonsAreOneHeightAtEverySize() {
        for (name, category) in [("Large", "UICTContentSizeCategoryL"),
                                 ("XXXL", "UICTContentSizeCategoryXXXL"),
                                 ("AX3", "UICTContentSizeCategoryAccessibilityL")] {
            launch(size: category)
            let field = openCreateRow(in: "setlists")
            let cancel = app.buttons["inline-rename-cancel"]
            let save = app.buttons["inline-rename-save"]
            let heights = [field.frame.height, cancel.frame.height, save.frame.height]
            print("INLINE [\(name)] heights \(heights)")
            XCTAssertEqual(heights[0], heights[1], accuracy: 1, "[\(name)] field and Cancel differ")
            XCTAssertEqual(heights[1], heights[2], accuracy: 1, "[\(name)] Cancel and Save differ")
            XCTAssertGreaterThanOrEqual(heights[0], 34, "[\(name)] below the control height")
            if name == "AX3" {
                XCTAssertGreaterThan(heights[0], 34, "[\(name)] the height did not scale")
            }
            app.buttons["inline-rename-cancel"].tap()
            app.terminate()
        }
    }

    // 8. theNameIsAProposal (with 5: the #1 arrangement of the checked piece)
    func testASetListFromASelectionArrivesWithItsNameSelected() {
        launch()
        element("library-edit").tap(); sleep(1)
        element("row-sous-le-ciel-de-paris").tap(); sleep(1)
        let make = app.buttons["bar-new-setlist"]
        XCTAssertTrue(make.waitForExistence(timeout: 10), "the bar does not offer a set list")
        XCTAssertEqual(make.label, "New set list from this piece",
                       "VoiceOver should get the whole sentence")
        make.tap()
        let field = app.textFields["inline-rename-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 30), "no rename row on the new set list")
        XCTAssertTrue(element("segment-setlists").isSelected, "the library should be on Set lists")
        let proposed = field.value as? String ?? ""
        print("INLINE proposed name \"\(proposed)\"")
        XCTAssertFalse(proposed.isEmpty, "the row arrived without a proposed name")
        XCTAssertTrue((field.value(forKey: "hasKeyboardFocus") as? Bool) == true, "the proposed name should be focused")
        // One keystroke replaces it whole.
        field.typeText("Q")
        XCTAssertEqual(field.value as? String, "Q", "the proposal was not selected: typing appended")
        app.buttons["inline-rename-cancel"].tap()
        // And what it holds: one arrangement, #1 of the piece.
        let row = element("row-" + proposedSlug(proposed))
        if row.waitForExistence(timeout: 5) {
            XCTAssertTrue(row.label.contains("1 arrangement"), "the set list should hold #1 only: \(row.label)")
        }
    }

    private func proposedSlug(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}
