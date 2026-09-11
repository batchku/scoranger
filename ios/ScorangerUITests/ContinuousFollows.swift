import XCTest

/// "When playing back in scroll mode, the score doesn't scroll." (Ali,
/// 2026-09-10.) It should: once the line reaches about a quarter of the way
/// in, the score streams past it and the line stands still.
///
/// Two witnesses, both on screen. The strip's canvas element moves LEFT as the
/// score scrolls, so its frame's minX after some seconds of playback must be
/// well below where it started. And the play head's handle, once the score is
/// moving, stands near the park point -- a quarter of the canvas's visible
/// width from its left edge -- rather than travelling across the glass.
final class ContinuousFollows: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-resetViewPreferences", "-seedTestLibrary"]
        app.launch()
    }

    func testTheScoreStreamsPastTheLineInScrollMode() throws {
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 240)
        let row = app.descendants(matching: .any)["row-sous-le-ciel-de-paris"]
        guard row.waitForExistence(timeout: 180) else { return XCTFail("no piece") }
        row.tap()
        // The QUARTET: 136 bars, so the strip is many screens wide and there is
        // something to scroll. The accordion solo fits in a screen or two.
        // The MUSICXML quartet, not the PDF scan of it: the strip is an
        // engraving, and only notation has one. The seed files the two
        // quartets under the same piece; the scan's slug carries the arranger.
        let choice = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@ AND NOT identifier CONTAINS %@",
            "arrangement-choice-", "quartet", "gheorghe")).firstMatch
        if choice.waitForExistence(timeout: 60) { choice.tap() }
        guard app.buttons["score-title"].waitForExistence(timeout: 300) else {
            return XCTFail("the score never opened")
        }

        let continuous = app.descendants(matching: .any)["layout-continuous"].firstMatch
        guard continuous.waitForExistence(timeout: 30) else { return XCTFail("no continuous layout control") }
        continuous.tap()
        let canvas = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas-")).firstMatch
        guard canvas.waitForExistence(timeout: 60) else { return XCTFail("no strip canvas") }
        sleep(2)
        let before = canvas.frame.minX

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

        // Long enough for the line to reach the park point and the score to
        // start moving behind it, at the default 120 bpm.
        sleep(14)
        let after = canvas.frame.minX
        print("DIAG strip minX before \(before) after \(after)")
        XCTAssertLessThan(after, before - 100,
                          "the strip did not scroll: canvas minX \(before) -> \(after)")

        // And the line is parked: a quarter of the way in, give or take a bar.
        let handle = app.descendants(matching: .any)["playhead-handle"]
        if handle.exists {
            let window = app.windows.firstMatch.frame
            let fraction = (handle.frame.midX - window.minX) / window.width
            print("DIAG handle at \(fraction) of the window width")
            XCTAssertEqual(fraction, 0.25, accuracy: 0.12,
                           "the line is not parked near a quarter in: \(fraction)")
        }
    }
}
