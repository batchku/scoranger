import XCTest

/// Ali, on 0.6.14 build 173: "App crashes in playback of Sous le ciel de
/// Paris."
///
/// A reproduction first, and deliberately a crude one: open the arrangement,
/// press play, and let it play. Nothing is asserted about the sound -- the
/// only claim is that the app is still running afterwards, which is the whole
/// of the report.
///
/// It plays for SECONDS rather than pressing play and looking immediately. A
/// crash in playback can be at the start (the graph being built, a part with
/// no notes, a program that will not load) or later (the play head reaching a
/// bar the map does not describe, a repeat being played out), and a test that
/// only checks the first frame after the tap would miss the second kind
/// entirely.
final class PlaybackCrash: XCTestCase {

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testPlayingSousLeCielDoesNotCrash() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 240)
        let row = app.descendants(matching: .any)["row-sous-le-ciel-de-paris"]
        guard row.waitForExistence(timeout: 180) else { return XCTFail("no piece") }
        row.tap()
        let choice = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                  "arrangement-choice-")).firstMatch
        if choice.waitForExistence(timeout: 60) { settle(choice); choice.tap() }
        guard app.buttons["score-title"].waitForExistence(timeout: 300) else {
            return XCTFail("the score never opened")
        }
        settle(app.buttons["score-title"], still: 0.8)

        // The transport reveals itself on the first playable arrangement, so
        // it may need a moment -- and if it never appears, that is a different
        // bug and this test should say so rather than time out silently.
        let play = app.buttons["transport-play"]
        if !play.waitForExistence(timeout: 60) {
            snap(app, "no-transport")
            return XCTFail("no play button: the transport never appeared")
        }
        snap(app, "before-play")
        play.tap()

        // Let it actually play. `expectation` rather than a bare wait so the
        // failure reads as "the app went away" instead of a mysterious query
        // timeout further down.
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: play)
        let result = XCTWaiter().wait(for: [gone], timeout: 25)
        snap(app, "after-playing")

        XCTAssertEqual(app.state, .runningForeground,
                       "the app is no longer in the foreground: state "
                       + "\(app.state.rawValue) -- it crashed during playback")
        XCTAssertNotEqual(result, .completed,
                          "the transport disappeared while playing, which is "
                          + "what a crash looks like from out here")

        // STAGE 2: TOUCH THE MUSIC WHILE IT PLAYS.
        //
        // This is new in 0.6.14 and it is the interaction most likely to be
        // what Ali hit. Before this release a finger tap on the canvas did
        // nothing AT ALL -- the recogniser failed itself at the end of every
        // touch -- so selecting while the music played was not possible with a
        // finger on any device. It is now, and following a performance by
        // tapping the note you are listening to is about the first thing
        // anyone would try.
        let canvas = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas-"))
            .firstMatch
        guard canvas.waitForExistence(timeout: 60) else {
            return XCTFail("no canvas to tap")
        }
        for dy in [0.3, 0.45, 0.6, 0.75] {
            guard app.state == .runningForeground else {
                snap(app, "crashed-tapping-while-playing")
                return XCTFail("the app died on a tap at dy=\(dy) while playing")
            }
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy)).tap()
        }
        snap(app, "tapped-while-playing")
        XCTAssertEqual(app.state, .runningForeground,
                       "the app crashed while the score was tapped during "
                       + "playback -- the interaction 0.6.14 made possible")

        // STAGE 3: and a PRESS while it plays, which raises the loupe over a
        // canvas that is being redrawn under it by the play head.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 2.0)
        snap(app, "pressed-while-playing")
        XCTAssertEqual(app.state, .runningForeground,
                       "the app crashed while a press held the loupe open "
                       + "during playback")
    }
}
