import XCTest

/// Filing an arrangement into a set list without leaving the score.
///
/// Ali: he can only add a piece to a set list from the library, not while
/// looking at the music. The checklist itself has existed since 0.6.11, opened
/// by a "+" on the score bar — but the "+" is the FIRST control the bar gives
/// up as it narrows, so on a phone it is never there at all. The reasoning at
/// the time was that "the library's set list picker still offers the same
/// operation, so this costs a shortcut rather than a feature". A reader
/// deciding what goes in a set is looking at the music while they decide, so
/// it cost more than that.
///
/// This runs on a phone deliberately: it is the width where the bar has
/// nothing, so the ⋯ route is the only one there is.
final class SetlistFromTheScore: XCTestCase {

    func testTheScoreCanFileItselfIntoASetList() {
        let app = XCUIApplication()
        app.launchArguments += ["-ScorangerUITest", "1"]
        app.launch()

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 120), "no library row to open")
        row.tap()
        if app.buttons["score-title"].waitForExistence(timeout: 5) == false {
            let choice = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                      "arrangement-choice-")).firstMatch
            if choice.waitForExistence(timeout: 60) { choice.tap() }
        }
        XCTAssertTrue(app.buttons["score-title"].waitForExistence(timeout: 240),
                      "score never opened")

        // the bar has no "+" at this width -- that is the premise
        XCTAssertFalse(app.buttons["score-add-setlist"].exists,
                       "this test is pointless if the bar already offers it here")

        app.buttons["score-more"].tap()
        let setlists = app.descendants(matching: .any)["more-setlists"]
        XCTAssertTrue(setlists.waitForExistence(timeout: 20),
                      "the ⋯ menu offers no way into the set lists")
        setlists.tap()

        // and it lands on the same checklist the "+" opens -- asserted on a
        // CHECKBOX, which is the thing that makes it that checklist. The band's
        // header is drawn uppercased, so matching its title would be matching
        // the styling.
        let box = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                  "setlist-check-")).firstMatch
        let emptyNote = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "No set lists yet")).firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 20)
                        || emptyNote.waitForExistence(timeout: 5),
                      "the set list checklist never opened")

        // a set list to file it into, so the row does what it is for
        if box.exists {
            box.tap()
            XCTAssertTrue(box.waitForExistence(timeout: 10),
                          "the checklist should stay open for a second tick")
        }
    }
}
