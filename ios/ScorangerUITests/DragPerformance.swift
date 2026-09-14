import XCTest

/// The performance loop's instrument, on a device (0.8.0 build 195).
///
/// Goal, stated: dragging the score holds the display's maximum refresh rate
/// -- `UIScreen.maximumFramesPerSecond`, 120 on ProMotion -- with no
/// degradation over time. This drags the score for a while in each layout
/// and reads `FrameProbe`'s summary: frames, dropped frames, the worst
/// interval, the average rate and the rate of each of the last seconds.
/// Run it on a real device; a simulator's frame timing says nothing about
/// an iPad.
final class DragPerformance: XCTestCase {

    private var app: XCUIApplication!

    private func launch() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary", "-frameProbe"]
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func openTheScore() {
        _ = element("library-search").waitForExistence(timeout: 300)
        let row = element("row-sous-le-ciel-de-paris")
        XCTAssertTrue(row.waitForExistence(timeout: 300), "the seeded piece never appeared")
        row.tap()
        let choice = element("arrangement-choice-sous-le-ciel-quartet")
        if choice.waitForExistence(timeout: 60) { choice.tap() }
        XCTAssertTrue(app.buttons["score-title"].waitForExistence(timeout: 300), "the score did not open")
        XCTAssertTrue(app.scrollViews["score-canvas"].waitForExistence(timeout: 300), "no canvas")
        sleep(3)
    }

    private struct Summary: Decodable {
        var maxFPS: Int; var frames: Int; var dropped: Int; var fps: Double
        var worstMs: Double; var activeSeconds: Double; var tailFPS: [Int]
    }

    private func summary() -> Summary? {
        let probe = element("frame-probe")
        guard probe.exists, let data = probe.label.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Summary.self, from: data)
    }

    /// `count` drags across the canvas, alternating direction, fast.
    private func drag(_ count: Int, horizontal: Bool) {
        let canvas = app.scrollViews["score-canvas"]
        for i in 0..<count {
            let forward = i % 2 == 0
            let a = canvas.coordinate(withNormalizedOffset: horizontal
                                      ? CGVector(dx: forward ? 0.85 : 0.15, dy: 0.5)
                                      : CGVector(dx: 0.5, dy: forward ? 0.85 : 0.15))
            let b = canvas.coordinate(withNormalizedOffset: horizontal
                                      ? CGVector(dx: forward ? 0.15 : 0.85, dy: 0.5)
                                      : CGVector(dx: 0.5, dy: forward ? 0.15 : 0.85))
            a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .default, thenHoldForDuration: 0.05)
        }
    }

    private func report(_ phase: String) -> Summary? {
        sleep(1)
        guard let s = summary() else { print("FPS [\(phase)] no probe summary"); return nil }
        print("FPS [\(phase)] max=\(s.maxFPS) fps=\(s.fps) frames=\(s.frames) dropped=\(s.dropped) worstMs=\(s.worstMs) active=\(s.activeSeconds)s tail=\(s.tailFPS)")
        return s
    }

    func testDraggingHoldsTheDisplaysRefreshRate() {
        launch()
        openTheScore()
        let canvas = app.scrollViews["score-canvas"]

        // Paged, zoomed in by a double tap so a drag pans instead of turning.
        canvas.doubleTap(); sleep(2)
        drag(24, horizontal: false)
        drag(24, horizontal: true)
        let paged = report("paged zoomed")

        // Continuous: the strip scrolls sideways.
        app.buttons["layout-continuous"].tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 240))
        sleep(4)
        drag(40, horizontal: true)
        let continuous = report("continuous")

        // The goal. Averaged over the whole drag, within 5% of the display's
        // best, fewer than 2% of frames dropped, and the last seconds no
        // slower than the whole -- that last one is "no degradation".
        for (name, s) in [("paged zoomed", paged), ("continuous", continuous)] {
            guard let s else { return XCTFail("[\(name)] the probe gave no summary") }
            let goal = Double(s.maxFPS) * 0.95
            XCTAssertGreaterThanOrEqual(s.fps, goal, "[\(name)] \(s.fps) fps against a display that can do \(s.maxFPS)")
            XCTAssertLessThan(Double(s.dropped), Double(s.frames) * 0.02, "[\(name)] dropped \(s.dropped) of \(s.frames)")
            if let last = s.tailFPS.suffix(3).min() {
                XCTAssertGreaterThanOrEqual(Double(last), goal, "[\(name)] the last seconds ran at \(s.tailFPS)")
            }
        }
    }
}
