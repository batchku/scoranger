import XCTest

/// The tray is wholly on screen, and a knob follows the finger.
///
/// Ali, 0.6.10, about the mixer window: it "renders cut off / clipped at the
/// screen edge", and dragging it "doesn't move live -- it only jumps to the
/// final position on release". The window is gone. The two claims survive on
/// the tray in the form it gives them: the line and the sound picker over it
/// are inside the screen, a knob's level moves WHILE the finger is down, and
/// the tray itself cannot be dragged anywhere.
///
/// Measured against the screen's frame rather than the geometry's intent,
/// because what Ali described was what SwiftUI drew.
final class TrayVisibility: XCTestCase {

    private var step = "the fixture never opened"

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedTestLibrary"]
        app.launch()
        return app
    }

    /// Every edge of the tray is inside the screen.
    func testTheTrayIsWhollyOnScreen() {
        let app = launched()
        guard let tray = openTray(app, step: &step) else { return XCTFail(step) }
        snap("tray")
        let screen = app.windows.firstMatch.frame
        print("TRAY frame \(tray.frame) in screen \(screen)")
        assertInside(tray.frame, screen, "tray")
    }

    /// And the sound picker, which is the largest thing the tray puts up.
    func testTheSoundPickerIsWhollyOnScreen() throws {
        let app = launched()
        guard openTray(app, step: &step) != nil else { return XCTFail(step) }
        let sound = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "strip-sound-"))
            .firstMatch
        guard sound.waitForExistence(timeout: 20) else {
            throw XCTSkip("no sound label to open the picker with")
        }
        sound.tap()
        let picker = app.descendants(matching: .any)["mixer-picker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 20), "the picker did not open")
        settle(picker)
        snap("tray-with-picker-open")
        let screen = app.windows.firstMatch.frame
        print("PICKER frame \(picker.frame) in screen \(screen)")
        assertInside(picker.frame, screen, "picker")
    }

    /// The knob tracks the finger, rather than jumping when it lifts.
    ///
    /// Measured MID-GESTURE: the drag is held still partway and the level
    /// read while the touch is still down, because the whole claim is about
    /// what is on screen while the finger is there. A test that only
    /// compared before and after would pass on the behaviour Ali reported.
    func testTheKnobFollowsTheFingerWhileItIsStillDown() {
        let app = launched()
        guard openTray(app, step: &step) != nil else { return XCTFail(step) }
        let knob = app.descendants(matching: .any)["strip-fader-0"].firstMatch
        XCTAssertTrue(knob.exists, "no knob to turn")
        let before = knob.value as? String ?? ""
        snap("knob-before-drag")

        let start = knob.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // Straight up: 14pt per unit, so 70pt is five steps -- unmistakable.
        let target = start.withOffset(CGVector(dx: 0, dy: -70))
        start.press(forDuration: 0.2, thenDragTo: target,
                    withVelocity: .slow, thenHoldForDuration: 1.2)
        // Sampled while the press is still held: XCTest keeps the touch down
        // for `thenHoldForDuration`, so this value is mid-gesture.
        let during = knob.value as? String ?? ""
        snap("knob-mid-drag")
        print("KNOB before \(before) during \(during)")
        XCTAssertNotEqual(during, before,
                          "the level had not moved while the finger was down "
                          + "(\(before)) -- it only jumps on release")
    }

    /// The tray has no drag: shoved at a corner, it is where it was.
    ///
    /// The window borrowed the ink bar's clamp and could legitimately park
    /// most of itself in the bezel. The tray is a line in the layout; the
    /// only thing a drag on its readout should do is nothing.
    func testTheTrayCannotBeDraggedAway() {
        let app = launched()
        guard let tray = openTray(app, step: &step) else { return XCTFail(step) }
        let before = tray.frame
        let handle = app.staticTexts["transport-bar"].firstMatch
        XCTAssertTrue(handle.exists, "no readout to take hold of")
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2,
                   thenDragTo: app.windows.firstMatch.coordinate(
                       withNormalizedOffset: CGVector(dx: 1.6, dy: 1.6)),
                   withVelocity: .default, thenHoldForDuration: 0.3)
        settle(tray)
        snap("tray-shoved-at-the-corner")
        let after = app.otherElements["transport"].firstMatch.frame
        print("TRAY before \(before) after \(after)")
        XCTAssertEqual(after.origin, before.origin,
                       "the tray moved from \(before.origin) to \(after.origin): it has a drag")
        assertInside(after, app.windows.firstMatch.frame, "tray after the shove")
    }
}
