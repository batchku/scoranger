import XCTest

/// Where the transport is, and that it is there at all.
///
/// 0.6 shipped playback behind `showTransport`, defaulting to false in a
/// submenu, and the reader who asked for the feature could not find it on a
/// score with real notation. The default is true now and the transport reveals
/// itself on the first playable arrangement — this proves both, and proves it
/// in CONTINUOUS layout too, which is the view that reader was actually in.
final class TransportVisibility: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-seedTestLibrary", "-resetViewPreferences"]
        app.launch()
    }

    private func keep(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// The whole point: open an arrangement that CAN play, and the transport is
    /// on screen without anyone visiting a menu.
    func testTheTransportIsThereWithoutBeingTurnedOn() {
        let row = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "row-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 180),
                      "the seeded library never arrived")
        row.tap()
        let choice = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "arrangement-choice-")).firstMatch
        if choice.waitForExistence(timeout: 20) { choice.tap() }

        let canvas = app.scrollViews["score-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 180),
                      "the score never finished engraving")

        // PAGED
        let play = app.buttons["transport-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 30),
                      "no play button in paged layout — the transport is hidden again")
        XCTAssertTrue(app.buttons["transport-mixer"].exists,
                      "no fader button, so the mixer is unreachable")
        keep("transport-paged")

        // CONTINUOUS — the layout the reader was stuck in
        let continuous = app.buttons["layout-continuous"]
        if continuous.waitForExistence(timeout: 20) {
            continuous.tap()
            XCTAssertTrue(canvas.waitForExistence(timeout: 180),
                          "the continuous engraving never arrived")
            XCTAssertTrue(app.buttons["transport-play"].waitForExistence(timeout: 30),
                          "the transport vanishes in continuous layout")
            keep("transport-continuous")
        }
    }
}
