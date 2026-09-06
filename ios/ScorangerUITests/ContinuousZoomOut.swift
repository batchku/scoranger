import XCTest

/// The scroll view zooms out far, and STAYS there.
///
/// Ali: in the scroll view he cannot zoom out far enough, and it "snaps back
/// when I zoom past a certain limit". Both are one cause -- the canvas took
/// its zoom floor from the paged layout, where 1.0 means "the page fits", and
/// UIScrollView rubber-banded anything past that floor straight back.
///
/// `ContinuousZoomOutTests` holds the arithmetic. This is the half the
/// arithmetic cannot answer: whether a real pinch on a real canvas reaches the
/// new floor and is still there a second later.
final class ContinuousZoomOut: XCTestCase {

    private var app: XCUIApplication!

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The canvas publishes its settled zoom as its accessibility value, which
    /// is the only way in from out here.
    private func scale(_ canvas: XCUIElement) -> CGFloat {
        CGFloat(Double((canvas.value as? String)?
            .replacingOccurrences(of: "zoom ", with: "") ?? "0") ?? 0)
    }

    func testTheScrollViewZoomsOutFarAndStaysThere() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 240)
        let row = app.descendants(matching: .any)["row-sous-le-ciel-de-paris"]
        guard row.waitForExistence(timeout: 180) else { return XCTFail("no piece") }
        row.tap()
        let choice = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                  "arrangement-choice-")).firstMatch
        if choice.waitForExistence(timeout: 60) { settle(choice); choice.tap() }
        guard app.buttons["score-title"].waitForExistence(timeout: 300) else {
            return XCTFail("the score never opened")
        }
        let canvas = app.scrollViews["score-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 240), "no canvas")
        settle(canvas, still: 0.8)

        // Into the SCROLL view. This test is about the strip; the paged floor
        // is deliberately unchanged and `ContinuousZoomOutTests` says so.
        let continuous = app.descendants(matching: .any)["layout-continuous"].firstMatch
        guard continuous.waitForExistence(timeout: 30) else {
            return XCTFail("no continuous layout control")
        }
        continuous.tap()
        settle(canvas, still: 1.0)
        snap("continuous-at-fit")
        let atFit = scale(canvas)
        XCTAssertGreaterThan(atFit, 0, "the canvas reports no zoom at all")

        // Pinch out, repeatedly. One pinch only divides the scale by about
        // 1.15 however small the factor asked for, so it is walked down.
        for _ in 0..<20 where scale(canvas) > 0.3 {
            canvas.pinch(withScale: 0.4, velocity: -3.0)
        }
        settle(canvas, still: 1.0)
        let out = scale(canvas)
        snap("continuous-zoomed-out")

        // 1. IT GOES FAR OUT. The old floor was 1.0 -- one system filling the
        // canvas -- and there was nothing below it.
        XCTAssertLessThan(out, 0.9,
                          "the strip only reached \(out)x: it is still held at "
                          + "the paged floor of 1.0")
        XCTAssertLessThan(out, atFit,
                          "zooming out did not make the music smaller")

        // 2. AND IT STAYS. This is the snap: UIScrollView bounced a pinch past
        // the floor back to it, so the reader saw the score spring in again.
        // Read after it has settled, then again, so a bounce in flight cannot
        // be mistaken for a resting scale.
        let settled = scale(canvas)
        settle(canvas, still: 1.2)
        let later = scale(canvas)
        XCTAssertEqual(later, settled, accuracy: 0.02,
                       "the zoom snapped back from \(settled)x to \(later)x "
                       + "after the gesture ended")
        XCTAssertLessThan(later, 0.9,
                          "it sprang back past the old floor: \(later)x")
        snap("continuous-stayed-out")
    }
}
