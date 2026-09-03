import XCTest

/// Untracked QA scaffolding for the 0.6.3 reorganisation: photograph the
/// things the owner judges by eye -- the halved mixer with its tempo slider,
/// and the PDF / MusicXML tags in the library and on the score.
final class ReorgShot: XCTestCase {

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// `named` picks a particular row -- the mixer needs an arrangement that can
    /// actually PLAY, and the seeded library's first row is a scan.
    private func openFirstScore(_ app: XCUIApplication, named: String? = nil) -> Bool {
        var row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-")).firstMatch
        if let named {
            let wanted = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
                                      "row-", named)).firstMatch
            if wanted.waitForExistence(timeout: 60) { row = wanted }
        }
        guard row.waitForExistence(timeout: 60) else { return false }
        row.tap()
        if app.buttons["score-title"].waitForExistence(timeout: 5) == false {
            let choice = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                      "arrangement-choice-")).firstMatch
            if choice.waitForExistence(timeout: 30) {
                sleep(1)
                snap("piece-screen-arrangement-tags")
                choice.tap()
            }
        }
        return app.buttons["score-title"].waitForExistence(timeout: 240)
    }

    func testTheLibraryAndTheScoreSayWhatTheyHold() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedTestLibrary"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 90)
        sleep(3)
        snap("library-format-tags-and-build-stamp")
        guard openFirstScore(app) else { return XCTFail("the score never engraved") }
        sleep(4)
        snap("score-artifact-marker")
    }

    func testTheMixerIsHalfHeightAndHasATempoSlider() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedTestLibrary"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 90)
        guard openFirstScore(app, named: "Sous le ciel") else {
            return XCTFail("the score never engraved")
        }
        sleep(4)
        snap("score-top-bar-with-transport-toggle")

        // The transport has to be showing for the mixer button to exist. It
        // defaults on since 0.6.1, but say so rather than assume it.
        if app.otherElements["transport"].exists == false,
           app.buttons["score-transport-toggle"].exists {
            app.buttons["score-transport-toggle"].tap()
            sleep(1)
        }
        guard app.buttons["transport-mixer"].waitForExistence(timeout: 120) else {
            snap("no-mixer-button")
            return XCTFail("no mixer button: playback is unavailable for this score")
        }
        app.buttons["transport-mixer"].tap()
        sleep(2)
        snap("mixer-half-height-with-tempo")
        let mixer = app.otherElements["mixer"].firstMatch
        if mixer.exists { print("MIXER frame: \(mixer.frame)") }
        let tempo = app.descendants(matching: .any)["mixer-tempo"].firstMatch
        if tempo.exists {
            print("TEMPO frame: \(tempo.frame), value: \(tempo.value ?? "-")")
            // Drag it well to the left and photograph the transport agreeing.
            tempo.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
            sleep(1)
            snap("mixer-tempo-moved")
            print("TRANSPORT tempo now: "
                  + "\(app.descendants(matching: .any)["transport-tempo"].firstMatch.label)")
        } else {
            XCTFail("the tempo slider is not on the panel")
        }
    }

    /// The Options screen, flattened: no "Score display", no "Versions",
    /// chord symbols one level up.
    func testTheOptionsScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedTestLibrary"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 90)
        guard openFirstScore(app) else { return XCTFail("the score never engraved") }
        sleep(3)
        app.buttons["score-more"].tap()
        sleep(1)
        snap("options-root")
        if app.descendants(matching: .any)["more-chords"].firstMatch.exists {
            app.descendants(matching: .any)["more-chords"].firstMatch.tap()
            sleep(1)
            snap("options-chord-symbols")
        }
    }

    /// The versions dropdown shows versions and nothing else.
    func testTheVersionsDropdown() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedTestLibrary"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 90)
        guard openFirstScore(app) else { return XCTFail("the score never engraved") }
        sleep(3)
        if app.buttons["score-versions"].exists {
            app.buttons["score-versions"].tap(); sleep(1); snap("dropdown-versions-only")
            app.buttons["score-versions"].tap()
        }
        app.buttons["score-title"].tap(); sleep(1); snap("dropdown-arrangements")
    }
}
