import XCTest

/// "When I open the mixer transport, playback stops." (Ali, 2026-09-10)
///
/// PlaybackCrash already opens the mixer while a score plays and asserts the
/// app SURVIVES it. This asserts the music does: the play button, whose label
/// is "Stop" while the transport runs, still says "Stop" after the mixer has
/// been open for a couple of seconds. If opening the mixer stops the
/// sequencer, the label flips back to "Play" and this says so, naming the step.
final class MixerKeepsPlaying: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary"]
        app.launch()
    }

    func testOpeningTheMixerDoesNotStopPlayback() throws {
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 240)
        let row = app.descendants(matching: .any)["row-sous-le-ciel-de-paris"]
        guard row.waitForExistence(timeout: 180) else { return XCTFail("no piece") }
        row.tap()
        let choice = app.descendants(matching: .any)[
            "arrangement-choice-under-paris-skies-accordion-solo"]
        if choice.waitForExistence(timeout: 60) { choice.tap() }
        guard app.buttons["score-title"].waitForExistence(timeout: 300) else {
            return XCTFail("the score never opened")
        }

        let play = app.buttons["transport-play"]
        guard play.waitForExistence(timeout: 60) else {
            return XCTFail("no play button: the transport never appeared")
        }
        // The transport may still be preparing; wait for it to be usable.
        let usable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"), object: play)
        XCTAssertEqual(XCTWaiter().wait(for: [usable], timeout: 120), .completed,
                       "the play button never became enabled")
        play.tap()
        let playing = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Stop"), object: play)
        XCTAssertEqual(XCTWaiter().wait(for: [playing], timeout: 20), .completed,
                       "playback did not start: the button still reads \(play.label)")

        let mixer = app.buttons["transport-mixer"].firstMatch
        guard mixer.waitForExistence(timeout: 20) else { return XCTFail("no mixer button") }
        mixer.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mixer-header"]
                        .waitForExistence(timeout: 20), "the mixer did not open")
        sleep(2)
        XCTAssertEqual(play.label, "Stop",
                       "opening the mixer stopped playback: the button reads \(play.label)")
    }
}
