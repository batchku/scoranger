import XCTest

/// "If I start playback and go back to the set list, the metronome continues;
/// playback continues. It should stop." (Ali, 2026-09-10)
///
/// The transport is gone from the screen once the score closes, so this asks
/// the next best witness: reopen the score, and the play button must read
/// "Play". If closing had left the sequencer running it would read "Stop",
/// which is what it did.
final class ClosingStopsPlayback: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary"]
        app.launch()
    }

    private func openTheScore() -> Bool {
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 240)
        let row = app.descendants(matching: .any)["row-sous-le-ciel-de-paris"]
        guard row.waitForExistence(timeout: 180) else { return false }
        row.tap()
        let choice = app.descendants(matching: .any)[
            "arrangement-choice-under-paris-skies-accordion-solo"]
        if choice.waitForExistence(timeout: 60) { choice.tap() }
        return app.buttons["score-title"].waitForExistence(timeout: 300)
    }

    func testClosingTheScoreStopsTheMusic() throws {
        guard openTheScore() else { return XCTFail("the score never opened") }
        let play = app.buttons["transport-play"]
        guard play.waitForExistence(timeout: 60) else { return XCTFail("no transport") }
        let usable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"), object: play)
        XCTAssertEqual(XCTWaiter().wait(for: [usable], timeout: 120), .completed)
        play.tap()
        let playing = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Stop"), object: play)
        XCTAssertEqual(XCTWaiter().wait(for: [playing], timeout: 20), .completed,
                       "playback did not start")

        // Back to the library, the way a reader does it.
        let close = app.buttons["score-close"]
        guard close.waitForExistence(timeout: 10) else { return XCTFail("no close button") }
        close.tap()
        XCTAssertTrue(app.descendants(matching: .any)["library-search"]
                        .waitForExistence(timeout: 30), "did not return to the library")
        sleep(1)

        // The witness.
        guard openTheScore() else { return XCTFail("the score did not reopen") }
        let again = app.buttons["transport-play"]
        XCTAssertTrue(again.waitForExistence(timeout: 60))
        XCTAssertEqual(again.label, "Play",
                       "the music kept playing behind the library: the button reads \(again.label)")
    }
}
