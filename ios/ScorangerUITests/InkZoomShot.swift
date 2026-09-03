import XCTest

/// The selection ink, photographed at two zooms, so its weight can be MEASURED
/// rather than judged.
///
/// Ali reported bug 8 by eye -- "the lines are way too thick, we've lost our
/// elegant thin line" -- and will judge the fix the same way, so the evidence
/// has to be a picture. But a picture of one zoom proves nothing: the whole
/// fault is that the mark is drawn inside the zoom transform, so it looks
/// correct at 1x however wrong the code is. Two zooms, and the orange border of
/// a selection box counted in pixels at each, is the same proof the playhead's
/// 2pt weight was given (design/screenshots/playhead-zoom-1x.png and -3x.png).
///
/// Carries no assertion about the width, because a screenshot cannot say what
/// the number should have been -- `SelectionInkTests` does that. It asserts
/// only that it photographed what it claims to have photographed: a real
/// selection, at two different zooms.
///
/// Run it on its own, and keep the pictures:
///   xcodebuild test -project Scoranger.xcodeproj -scheme Scoranger \
///     -destination "platform=iOS Simulator,id=<udid>" \
///     -only-testing:ScorangerUITests/InkZoomShot -resultBundlePath out.xcresult
final class InkZoomShot: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// Where the PNGs are written, so they can be measured after the run. The
    /// attachment in the result bundle is the same picture; this is the copy a
    /// person looks at.
    private var shotDirectory: String? {
        ProcessInfo.processInfo.environment["SCORANGER_SHOT_DIR"]
    }

    private func snap(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = shotDirectory,
           let png = screenshot.pngRepresentation as NSData? {
            png.write(toFile: directory + "/\(name).png", atomically: true)
        }
    }

    /// The live zoom, which the scroll view publishes as its accessibility
    /// value for exactly this.
    private func zoom(of canvas: XCUIElement) -> CGFloat {
        CGFloat(Double((canvas.value as? String)?
            .replacingOccurrences(of: "zoom ", with: "") ?? "0") ?? 0)
    }

    private func openFirstScore() {
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "row-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 240),
                      "the seeded library never appeared")
        row.tap()
        if !app.buttons["score-title"].waitForExistence(timeout: 6) {
            let choice = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@",
                            "arrangement-choice-")).firstMatch
            if choice.waitForExistence(timeout: 20) { choice.tap() }
        }
        XCTAssertTrue(app.buttons["score-title"].waitForExistence(timeout: 180),
                      "the score never engraved")
    }

    func testTheSelectionInkKeepsItsWeightAtAnyZoom() {
        app = XCUIApplication()
        // the Pencil stand-in: no simulator can produce Pencil input, so a
        // finger drives the selection pipeline (see LassoGestureRecognizer)
        app.launchArguments = ["-seedTestLibrary", "-uiTestPencil"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        openFirstScore()

        let canvas = app.scrollViews["score-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 180))
        sleep(12)

        // A band across the MIDDLE of the canvas. The pinch below zooms about
        // the element's centre, so a selection caught anywhere else would leave
        // the frame before it could be photographed at 3x.
        let chip = app.staticTexts["selection-chip"]
        var caught = false
        for dy in [0.50, 0.44, 0.56, 0.38] where !caught {
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.38, dy: dy))
                .press(forDuration: 0.6,
                       thenDragTo: canvas.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.62, dy: dy)))
            caught = chip.waitForExistence(timeout: 8)
        }
        XCTAssertTrue(caught, "nothing was selected, so there is no ink to measure")
        sleep(1)
        print("INKZOOM: 1x zoom=\(zoom(of: canvas)) chip=\(chip.label)")
        snap("ink-selection-zoom-1x")

        // Up to about 3x. The layer divides by the SETTLED zoom, so the shot
        // waits for the raster to land -- a picture taken mid-gesture is of a
        // weight that is neither value.
        for _ in 0..<8 where zoom(of: canvas) < 3 {
            canvas.pinch(withScale: 3.0, velocity: 2.0)
            print("INKZOOM: pinch -> \(zoom(of: canvas))")
        }
        sleep(5)
        let zoomed = zoom(of: canvas)
        print("INKZOOM: zoomed to \(zoomed)")
        snap("ink-selection-zoom-\(String(format: "%.1f", zoomed))x")
        // and under a fixed name too, so the pair can be compared without
        // knowing what the pinch settled on
        snap("ink-selection-zoom-deep")

        XCTAssertGreaterThan(zoomed, 1.8,
                             "the pinch did not zoom, so the pair of pictures is "
                             + "of the same magnification and proves nothing")
        XCTAssertTrue(chip.exists,
                      "the selection went away before the second picture")
    }
}
