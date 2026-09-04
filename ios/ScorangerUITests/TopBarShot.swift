import XCTest

/// Photographs of the score's top bar, for a human to look at (0.6.8).
///
/// It carries no assertions about the product and cannot fail a build, which is
/// why it sits with the other sweeps rather than in the suite: what it produces
/// is evidence, and evidence is read, not asserted.
///
/// It runs against the build BEFORE the change and the build after, and takes
/// the same three pictures either way -- the reading bar, the Options screen,
/// and a transcription in flight -- so the pair can be put side by side. It
/// therefore reaches for both routes to everything and asserts neither.
///
/// The transcription shot needs an OMR service it can actually reach. Pass
/// `-omrURL http://127.0.0.1:8099` and run `omr-service/server.py` beside it;
/// without one the app falls back to saving into intake and the shot is simply
/// of a score with no chip on it, which is what this class then prints.
final class TopBarShot: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func launch(_ arguments: [String]) {
        app = XCUIApplication()
        app.launchArguments = arguments
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 90)
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func settle(_ seconds: TimeInterval = 1.0) {
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "settle")],
                             timeout: seconds)
    }

    /// What the transcription chip says, or that there is none.
    private func reportChip() {
        let chip = app.descendants(matching: .any)["score-omr-progress"].firstMatch
        guard chip.exists else { return print("SHOT: no transcription chip on screen") }
        print("SHOT: transcription chip reads \(chip.label)")
    }

    /// Open whatever the seed put in the library, by the route a person takes.
    private func openFirstScore() {
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "row-")).firstMatch
        guard row.waitForExistence(timeout: 180) else {
            return print("SHOT: the library never filled")
        }
        row.tap()
        let choice = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "arrangement-choice-")).firstMatch
        if choice.waitForExistence(timeout: 5) { choice.tap() }
        _ = app.buttons["score-close"].waitForExistence(timeout: 180)
        settle(3.0)
    }

    private func back() {
        let byId = app.buttons["screen-back"].firstMatch
        if byId.exists && byId.isHittable { return byId.tap() }
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Back to")).firstMatch.tap()
    }

    /// The reading bar, and the Options screen behind its `…`.
    func testShootTheTopBarAndOptions() {
        launch(["-resetLibrary", "-seedTestLibrary"])
        openFirstScore()
        print("SHOT: score-performance on the bar = "
              + "\(app.buttons["score-performance"].exists)")
        print("SHOT: score-transport-toggle on the bar = "
              + "\(app.buttons["score-transport-toggle"].exists)")
        snap("top-bar")

        app.buttons["score-more"].tap()
        settle(1.5)
        print("SHOT: more-performance in Options = "
              + "\(app.descendants(matching: .any)["more-performance"].exists)")
        print("SHOT: more-transport in Options = "
              + "\(app.descendants(matching: .any)["more-transport"].exists)")
        snap("options")
        back()
    }

    /// A scan, with a transcription running on it.
    ///
    /// The switch is pressed and the screen LEFT, which is the whole point: the
    /// question is what the score view says about work that is still going on
    /// somewhere else.
    func testShootATranscriptionInFlight() {
        // The OMR endpoint, pointed at a service running beside this on the
        // host. A launch argument of this shape lands in NSArgumentDomain,
        // which is what @AppStorage("omrURL") reads first.
        launch(["-resetLibrary", "-seedTestLibrary", "-seedScanArrangement",
                "-omrURL", "http://127.0.0.1:8099"])
        let scan = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                        "row-", "Scanned")).firstMatch
        guard scan.waitForExistence(timeout: 180) else {
            return print("SHOT: no scan in the library, so nothing to transcribe")
        }
        scan.tap()
        let choice = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "arrangement-choice-")).firstMatch
        if choice.waitForExistence(timeout: 5) { choice.tap() }
        guard app.buttons["score-close"].waitForExistence(timeout: 180) else {
            return print("SHOT: the scan never opened")
        }
        settle(3.0)
        snap("scan-before-omr")

        app.buttons["score-more"].tap()
        let makeEditable = app.switches["Make editable"]
        guard makeEditable.waitForExistence(timeout: 20) else {
            return print("SHOT: no Make editable switch: this is not a scan")
        }
        makeEditable.tap()
        settle(2.0)
        snap("make-editable-running")
        back()

        // Back on the music, which is where a reader goes. Photograph it as the
        // transcription runs -- twice, so the pictures show whether the readout
        // MOVES or sits still.
        settle(12.0)
        // Reading `.label` off something that is not there THROWS, and on the
        // build this is the "before" of, it is not there -- which is the whole
        // point of taking the picture. So it is asked whether it exists first,
        // every time.
        reportChip()
        snap("score-during-omr-early")
        settle(30.0)
        reportChip()
        snap("score-during-omr-later")

        // And what the switch itself says, which is the readout that stuck.
        app.buttons["score-more"].tap()
        settle(1.5)
        snap("make-editable-progress")
        back()
    }
}
