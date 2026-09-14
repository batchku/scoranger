import XCTest

/// "When I open the mixer transport, playback stops." (Ali, 2026-09-10)
///
/// 0.8: there is no mixer to open -- the tray carries the knobs -- but the
/// things a reader does on it while the music runs are the same: mute a
/// part, open the sound picker. This asserts the music survives them: the
/// play button, whose label is "Stop" while the transport runs, still says
/// "Stop" after a mute and a couple of seconds with the picker open. If either
/// stops the sequencer, the label flips back to "Play" and this says which.
final class MixerKeepsPlaying: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary"]
        app.launch()
    }

    func testWorkingTheTrayDoesNotStopPlayback() throws {
        var step = ""
        guard openTray(app, arrangement: "under-paris-skies-accordion-solo",
                       step: &step) != nil else { return XCTFail(step) }

        let play = app.buttons["transport-play"]
        let usable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"), object: play)
        XCTAssertEqual(XCTWaiter().wait(for: [usable], timeout: 120), .completed,
                       "the play button never became enabled")
        play.tap()
        let playing = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Stop"), object: play)
        XCTAssertEqual(XCTWaiter().wait(for: [playing], timeout: 20), .completed,
                       "playback did not start: the button still reads \(play.label)")

        // A mute, and back.
        let mute = app.descendants(matching: .any)["strip-mute-0"].firstMatch
        mute.tap()
        sleep(1)
        XCTAssertEqual(play.label, "Stop", "muting a part stopped playback")
        mute.tap()

        // The sound picker, open for a couple of seconds, then closed.
        app.descendants(matching: .any)["strip-sound-0"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mixer-picker"]
                        .waitForExistence(timeout: 20), "the sound picker did not open")
        sleep(2)
        XCTAssertEqual(play.label, "Stop",
                       "opening the sound picker stopped playback: the button reads \(play.label)")
        app.descendants(matching: .any)["mixer-picker-close"].firstMatch.tap()
        sleep(1)
        XCTAssertEqual(play.label, "Stop", "closing the sound picker stopped playback")
    }
}
