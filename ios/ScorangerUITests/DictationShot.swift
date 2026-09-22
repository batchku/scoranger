import XCTest

/// A photograph of what the chat field says when dictation cannot run
/// on-device, for a person to read.
///
/// 0.12.0 made dictation on-device only: `requiresOnDeviceRecognition = true`,
/// and where `supportsOnDeviceRecognition` is false the app refuses rather
/// than falling back to Apple's servers. The refusal is not an alert — it is
/// the chat field's PLACEHOLDER (`ChatView.swift`, `dictation.errorText`), so
/// the only way to know it reads as a sentence and not as a truncated string
/// in a field the size of a stamp is to look at it.
///
/// A simulator is the honest place to take this picture: it has no on-device
/// speech model, which is the case being photographed.
///
/// NOT IN THE GATE, and not an assertion. Which of the three messages appears
/// depends on what the host's Speech stack answers -- permission, availability
/// or on-device support -- and a build must not fail because a simulator
/// declined a microphone. The photograph is the point; the behaviour is held
/// by `engine/scripts/check_dictation.py`, which reads the source.
final class DictationShot: XCTestCase {
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

    func testPhotographTheDictationRefusal() throws {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-resetViewPreferences", "-seedTestLibrary"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 240)
        let row = app.descendants(matching: .any)["row-sous-le-ciel-de-paris"]
        guard row.waitForExistence(timeout: 180) else { return XCTFail("no piece") }
        row.tap()
        let choice = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "arrangement-choice-")).firstMatch
        if choice.waitForExistence(timeout: 60) { choice.tap() }
        guard app.buttons["score-ask"].waitForExistence(timeout: 300) else {
            return XCTFail("the score never opened")
        }
        app.buttons["score-ask"].tap()
        guard app.buttons["Close chat"].waitForExistence(timeout: 30) else {
            return XCTFail("the chat never opened")
        }
        snap("chat-before-dictation")

        // The permission alerts are the system's, not the app's. Dismiss
        // whichever appears so the run reaches the refusal rather than
        // stopping at a dialog.
        addUIInterruptionMonitor(withDescription: "speech and microphone") { alert in
            for label in ["OK", "Allow", "Yes"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.buttons["Start dictation"].tap()
        app.tap()                      // fires the interruption monitor
        sleep(4)
        snap("chat-after-tapping-the-mic")

        // Whatever happened, say what the field now reads, and whether the
        // app thinks it is recording -- the picture alone cannot distinguish
        // "refused" from "listening", and those are opposite outcomes.
        let field = app.descendants(matching: .any)["chat-input"]
        let placeholder = field.exists
            ? (field.placeholderValue ?? field.label) : "(no chat-input)"
        let recording = app.buttons["Stop dictation"].exists
        print("DICTATION PLACEHOLDER: \(placeholder)")
        print("DICTATION RECORDING: \(recording)")
        if recording {
            // On-device recognition IS available here; photograph the live
            // state instead, and leave the field as it was found.
            app.buttons["Stop dictation"].tap()
            sleep(2)
            snap("chat-after-stopping")
        }
    }
}
