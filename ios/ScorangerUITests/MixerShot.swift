import XCTest

/// A photograph of the mixer, for a person to look at. Two things Ali asked
/// about on 2026-09-10 can only be judged by eye: whether ALL ON / ALL OFF
/// are centred in their boxes, and what the knob looks like with its LED in
/// the middle and no numeral. No assertions beyond "it opened".
///
/// Written to `SCORANGER_SHOT_DIR` when set, like the other shots. Not in the
/// gate: photographs cannot fail a build.
final class MixerShot: XCTestCase {
    var app: XCUIApplication!

    private func snap(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["SCORANGER_SHOT_DIR"],
           let png = screenshot.pngRepresentation as NSData? {
            png.write(toFile: directory + "/\(name).png", atomically: true)
        }
    }

    func testPhotographTheMixer() throws {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-resetViewPreferences", "-seedTestLibrary"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 240)
        let row = app.descendants(matching: .any)["row-sous-le-ciel-de-paris"]
        guard row.waitForExistence(timeout: 180) else { return XCTFail("no piece") }
        row.tap()
        let choice = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@ AND NOT identifier CONTAINS %@",
            "arrangement-choice-", "quartet", "gheorghe")).firstMatch
        if choice.waitForExistence(timeout: 60) { choice.tap() }
        guard app.buttons["score-title"].waitForExistence(timeout: 300) else {
            return XCTFail("the score never opened")
        }
        let mixer = app.buttons["transport-mixer"].firstMatch
        guard mixer.waitForExistence(timeout: 60) else { return XCTFail("no mixer button") }
        let usable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"), object: mixer)
        _ = XCTWaiter().wait(for: [usable], timeout: 120)
        mixer.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mixer-header"]
                        .waitForExistence(timeout: 20), "the mixer did not open")
        sleep(2)
        snap("mixer")
    }
}
