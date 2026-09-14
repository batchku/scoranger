import XCTest

/// What arrives, opens. And a photograph arrives whole.
///
/// Ali on build 193: "Import should OPEN the imported score" -- both the
/// in-app path and the share-extension/inbox path. Both end in
/// `AppState.receiveFile`, which is what the inbox seed drives here without a
/// share sheet or a Files picker in the way; after it, `openAfterImport`
/// carries the new slug to the root, which opens it.
///
/// The second test brings in a real .jpeg. In 193 an imported picture opened,
/// but its More panel had no Make editable (the gate asked for `.scan`, which
/// a picture is not) and saving its Details failed with a music21
/// ConverterFileException, because the engine parsed the latest artifact --
/// a JPEG -- to write the title into it. Both are asserted the way a reader
/// meets them: from the panel.
final class ArrivalsOpen: XCTestCase {

    private var app: XCUIApplication!

    private func launch(_ arguments: [String]) {
        app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Nothing is tapped. The score arrives in the inbox and the next thing
    /// on screen is the score itself.
    func testAScoreThatArrivesOpensItself() {
        launch(["-resetLibrary", "-seedTestLibrary", "-seedInboxFixture"])
        let title = element("score-title")
        XCTAssertTrue(title.waitForExistence(timeout: 240),
                      "the score that arrived in the inbox did not open on its own")
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 180),
                      "it opened but never drew")
        snap("arrived-score-open")
        // It is the arrival, not whatever the library had selected.
        XCTAssertTrue(element("score-close").exists)
    }

    /// A photograph of a page: opens on arrival, keeps its details, and can be
    /// read into notation.
    func testAPhotographArrivesOpensAndCanBeReadIntoNotation() {
        launch(["-resetLibrary", "-seedTestLibrary", "-seedInboxImage"])
        let title = element("score-title")
        XCTAssertTrue(title.waitForExistence(timeout: 240),
                      "the photograph that arrived in the inbox did not open on its own")
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 120),
                      "the photograph opened but never drew")
        // A picture is not engraved, so continuous is off: the proof this is
        // the image artifact and not something already transcribed.
        XCTAssertTrue(app.buttons["layout-continuous"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["layout-continuous"].isEnabled,
                       "continuous is for notation; this should still be the picture")
        snap("arrived-photo-open")

        // Details save on the picture -- the ConverterFileException of 193.
        app.buttons["score-more"].tap()
        XCTAssertTrue(element("more-details").waitForExistence(timeout: 20), "no Details in More")
        element("more-details").tap()
        let composer = app.textFields["arrangement-composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 20), "no composer field on Details")
        composer.tap()
        composer.typeText("Hubert Giraud")
        let save = app.buttons["save-metadata"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "typing a composer should offer Save")
        save.tap()
        // Save goes away when there is nothing left to save; the failure of
        // 193 surfaces as a notice bar beginning "Couldn't save".
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 90), .completed,
                       "the details save never completed")
        let failure = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Couldn't save")).firstMatch
        XCTAssertFalse(failure.exists, "saving the picture's details failed: \(failure.exists ? failure.label : "")")
        XCTAssertEqual(composer.value as? String, "Hubert Giraud",
                       "the composer did not survive the save")
        snap("photo-details-saved")

        // And the way out of being a picture is offered, and works.
        //
        // 0.8.2 (SC13): the offer is a PANEL STATE. More keeps a row that
        // opens it -- which is what this asserts, because that row going is
        // what would take the whole route away from a picture.
        element("panel-back").tap()
        let convertRow = element("more-make-editable")
        XCTAssertTrue(convertRow.waitForExistence(timeout: 20),
                      "a picture should offer Convert, as a PDF does")
        snap("photo-more-convert-row")
        convertRow.tap()
        let convert = element("convert-run")
        XCTAssertTrue(convert.waitForExistence(timeout: 20),
                      "the Convert row opened no offer")
        snap("photo-convert-offer")
        convert.tap()
        // The transcription goes to the OMR service and comes back as a
        // notation version; continuous layout coming alive is the arrival.
        let notation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"),
            object: app.buttons["layout-continuous"])
        let outcome = XCTWaiter.wait(for: [notation], timeout: 420)
        snap("photo-after-make-editable")
        XCTAssertEqual(outcome, .completed,
                       "Make editable never produced notation from the photograph "
                       + "(needs the OMR service reachable from this machine)")
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "ConverterFileException")).firstMatch.exists,
                       "the engine still parsed the JPEG as notation")
    }
}
