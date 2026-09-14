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
        sleep(3)

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

        // THE WITNESS IS THE LINE. If the score streams past it, the handle
        // stands near the park point -- a quarter of the glass in -- and stays
        // there between two readings. If the score does NOT scroll, the line
        // travels across the glass and the two readings differ by whole bars.
        let handle = app.descendants(matching: .any)["playhead-handle"]
        guard handle.waitForExistence(timeout: 20) else { return XCTFail("no play head handle") }
        let window = app.windows.firstMatch.frame
        // Long enough at 120 bpm for the line to reach the park point.
        sleep(14)
        let first = (handle.frame.midX - window.minX) / window.width
        sleep(5)
        let second = (handle.frame.midX - window.minX) / window.width
        print("DIAG handle at \(first) then \(second) of the window width")
        XCTAssertEqual(first, 0.25, accuracy: 0.12,
                       "the line is not parked near a quarter in: \(first)")
        XCTAssertEqual(second, first, accuracy: 0.06,
                       "the line moved across the glass (\(first) -> \(second)): the score is not scrolling")
    }
}
