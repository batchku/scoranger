import XCTest

/// The mixer at the text size the reader actually uses.
///
/// Ali, on his iPad: the mixer is "NOT draggable at all, and its text/UI is
/// cut off". Both were invisible to every test in this suite, and this is the
/// half that explains the cut-off half.
///
/// `MixerLayout` computes the panel's size from hard-coded points -- a 64pt
/// strip, a 16pt label row, a 22pt picker row -- and `MixerLayout.origin`
/// positions it on the assumption that arithmetic is what SwiftUI will draw.
/// Every type role in this app scales with Dynamic Type
/// (`Theme.Role.font` -> `UIFontMetrics.scaledFont`), so at any content size
/// above the default the panel's CONTENT outgrows those frames: the panel
/// renders wider than the number it was placed by, and the difference hangs
/// off the screen edge.
///
/// Measured on iPad Pro 13-inch (M5), iOS 26.5, 1032x1376pt:
///
///     content size                 panel drawn      right edge
///     large (the default)          268.0 x 173.0    inside
///     accessibility-extra-large    320.5 x 182.0    23pt off screen
///
/// and at that size the ✕ close button, the "all voices" caption, the tempo
/// value and both transport readouts are off the panel or truncated to an
/// ellipsis.
///
/// The size is set with `-UIPreferredContentSizeCategoryName` on the launch
/// rather than `simctl ui content_size`, so it belongs to the test rather
/// than to the machine and the gate carries it.
final class MixerFitsAnyTextSize: XCTestCase {

    /// The sizes asserted. Not every category -- these are the default, one
    /// step up (which many readers set and no test had ever run), and the
    /// accessibility size that made the failure obvious.
    private static let sizes = [
        ("large", "UICTContentSizeCategoryL"),
        ("extra-extra-large", "UICTContentSizeCategoryXXL"),
        ("accessibility-extra-large", "UICTContentSizeCategoryAccessibilityXL"),
    ]

    private func snap(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func openMixer(_ app: XCUIApplication) -> XCUIElement? {
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 90)
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
                                  "row-", "Sous le ciel")).firstMatch
        guard row.waitForExistence(timeout: 120) else { return nil }
        row.tap()
        if app.buttons["score-title"].waitForExistence(timeout: 5) == false {
            let choice = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                      "arrangement-choice-")).firstMatch
            if choice.waitForExistence(timeout: 30) { settle(choice); choice.tap() }
        }
        guard app.buttons["score-title"].waitForExistence(timeout: 240) else { return nil }
        let page = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas-")).firstMatch
        _ = page.waitForExistence(timeout: 180)
        settle(page, still: 0.6)
        if app.otherElements["transport"].exists == false,
           app.buttons["score-transport-toggle"].exists {
            app.buttons["score-transport-toggle"].tap()
            _ = app.otherElements["transport"].waitForExistence(timeout: 20)
        }
        guard app.buttons["transport-mixer"].waitForExistence(timeout: 120) else { return nil }
        app.buttons["transport-mixer"].tap()
        let panel = app.otherElements["mixer"].firstMatch
        guard panel.waitForExistence(timeout: 30) else { return nil }
        settle(panel)
        return panel
    }

    /// At every text size: the panel is wholly on screen, and the controls a
    /// reader needs are still ON it and hittable.
    ///
    /// Hittability rather than pixels, because that is the failure: the ✕ was
    /// not small at accessibility size, it was off the panel entirely. An
    /// element XCTest cannot hit is one a finger cannot reach.
    func testTheMixerFitsAndKeepsItsControlsAtEveryTextSize() {
        for (label, category) in Self.sizes {
            let app = XCUIApplication()
            app.launchArguments = ["-seedTestLibrary",
                                   "-UIPreferredContentSizeCategoryName", category]
            app.launch()
            defer { app.terminate() }

            guard let panel = openMixer(app) else {
                snap("no-mixer-at-\(label)", app)
                XCTFail("[\(label)] no mixer opened")
                continue
            }
            snap("mixer-at-\(label)", app)

            let screen = app.windows.firstMatch.frame
            let box = panel.frame
            print("[\(label)] panel \(box) in screen \(screen)")

            XCTAssertLessThanOrEqual(box.maxX - screen.maxX, 0.5,
                                     "[\(label)] \(box.maxX - screen.maxX)pt off the right")
            XCTAssertLessThanOrEqual(box.maxY - screen.maxY, 0.5,
                                     "[\(label)] \(box.maxY - screen.maxY)pt off the bottom")
            XCTAssertGreaterThanOrEqual(box.minX, -0.5, "[\(label)] off the left")
            XCTAssertGreaterThanOrEqual(box.minY, -0.5, "[\(label)] off the top")

            // The way out of the panel, which is the one that actually went
            // missing. A panel with no reachable close is the mixer trapping
            // the reader, which is #60's lesson on a different control.
            let close = app.buttons["mixer-close"]
            XCTAssertTrue(close.exists && close.isHittable,
                          "[\(label)] the mixer's ✕ is not reachable")

            // One strip's controls, so the panel is usable and not merely
            // present: the mute, the fader and the sound chip of channel 0.
            for id in ["strip-mute-0", "strip-fader-0", "strip-sound-0"] {
                let control = app.descendants(matching: .any)[id]
                XCTAssertTrue(control.exists && control.isHittable,
                              "[\(label)] \(id) is not reachable")
            }

            // And the transport's own two readouts, which collapsed to "0…"
            // and "3…" -- a clock that says nothing is not a clock.
            for id in ["mixer-elapsed", "mixer-total"] {
                let readout = app.descendants(matching: .any)[id]
                XCTAssertTrue(readout.exists, "[\(label)] \(id) is gone")
                XCTAssertFalse((readout.label).contains("…"),
                               "[\(label)] \(id) is truncated: \(readout.label)")
            }
        }
    }
}
