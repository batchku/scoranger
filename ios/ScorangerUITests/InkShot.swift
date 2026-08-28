import XCTest

/// Untracked QA scaffolding: draw ink, zoom in, photograph it. The only way to
/// see whether the strokes are re-rendered at the zoom or merely magnified.
final class InkShot: XCTestCase {
    func testInkUnderZoom() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedTestLibrary", "-annotateWithFinger"]
        app.launch()

        _ = app.descendants(matching: .any)["library-search"]
            .waitForExistence(timeout: 60)
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "no library row")
        row.tap()
        if app.buttons["score-title"].waitForExistence(timeout: 5) == false {
            let choice = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                      "arrangement-choice-")).firstMatch
            if choice.waitForExistence(timeout: 20) { choice.tap() }
        }
        XCTAssertTrue(app.buttons["score-title"].waitForExistence(timeout: 180),
                      "the score never engraved")
        let score = app.scrollViews["score-canvas"]
        XCTAssertTrue(score.waitForExistence(timeout: 60))
        sleep(3)

        // ink mode on, then a big finger stroke across the page
        app.buttons["score-edit"].tap()
        sleep(1)
        let a = score.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.30))
        let b = score.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.42))
        a.press(forDuration: 0.1, thenDragTo: b)
        sleep(1)
        let c = score.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.45))
        let d = score.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.32))
        c.press(forDuration: 0.1, thenDragTo: d)
        sleep(1)
        snap("ink-mode-on")
        app.buttons["score-edit"].tap()
        sleep(1)
        snap("ink-at-rest")

        func scale() -> CGFloat {
            CGFloat(Double((score.value as? String)?
                .replacingOccurrences(of: "zoom ", with: "") ?? "0") ?? 0)
        }
        for _ in 0..<24 where scale() < 4 {
            score.pinch(withScale: 3.0, velocity: 2.0)
        }
        sleep(3)
        print("INKSHOT zoom \(scale())")
        snap("ink-zoomed-\(String(format: "%.1f", scale()))")
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
