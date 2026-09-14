import XCTest

/// A drag that REACHES the edge of a zoomed page does not turn it.
///
/// Ali's build-with answer, and the rule `PagedCanvas.swipeMayTurn` states:
/// stop at the edge; the turn is a second, deliberate gesture. The code read
/// the limit at the END of the drag instead of the start, so every long pan
/// across a zoomed page ended against the limit and turned -- and nobody saw
/// it, because the recogniser that reports a swipe never fired at all until
/// 0.6.14. The first thing that happened when it was repaired was a zoomed
/// page panning itself seven pages forward.
final class SwipeAtTheEdge: XCTestCase {

    private var app: XCUIApplication!

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testAPanThatReachesTheEdgeDoesNotTurnThePage() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 240)
        let row = app.descendants(matching: .any)["row-sous-le-ciel-de-paris"]
        guard row.waitForExistence(timeout: 180) else { return XCTFail("no arrangement") }
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

        // Zoom in, or there is no slack and a drag is FREE to mean a turn --
        // which is the other half of the same rule and must keep working.
        // 1.8x deliberately and not more: the drag below has to be able to
        // cross the whole remaining slack in ONE gesture, and slack grows with
        // the zoom. At 1.8x on an 11-inch iPad that is about 667pt against a
        // drag of about 800.
        func scale() -> CGFloat {
            CGFloat(Double((canvas.value as? String)?
                .replacingOccurrences(of: "zoom ", with: "") ?? "0") ?? 0)
        }
        // The same walk the zoom test uses, and the same factor: one pinch
        // multiplies the scale by about 1.15 however large the number asked
        // for, so it is climbed rather than jumped.
        for _ in 0..<30 where scale() < 1.8 {
            canvas.pinch(withScale: 3.0, velocity: 2.0)
        }
        XCTAssertGreaterThanOrEqual(scale(), 1.5, "could not zoom in: \(scale())x")
        settle(canvas, still: 0.6)

        let page = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier ENDSWITH %@", "/p0"))
            .firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 30), "no first page")

        func drag() {
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5))
                .press(forDuration: 0.05,
                       thenDragTo: canvas.coordinate(
                           withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)))
        }

        let before = app.staticTexts["counter-pages"].label

        // ONE long drag, from the far side of the page to past the near edge.
        // It STARTS with slack and ENDS hard against the limit -- the gesture
        // that rolled into a turn the moment the recogniser was repaired.
        drag()
        settle(canvas, still: 0.8)
        snap("pan-reached-the-edge")

        // THE PRECONDITION, stated rather than assumed. Without it this
        // assertion passes on a drag that never got near the edge -- which is
        // how the first version of this test passed while proving nothing.
        XCTAssertEqual(page.frame.maxX, canvas.frame.maxX, accuracy: 40,
                       "the drag did not reach the edge, so the assertion "
                       + "below says nothing: page ends at \(page.frame.maxX), "
                       + "canvas at \(canvas.frame.maxX)")
        XCTAssertEqual(app.staticTexts["counter-pages"].label, before,
                       "a pan that reached the edge turned the page: "
                       + "\(before) -> \(app.staticTexts["counter-pages"].label)")

        // AND A SECOND DRAG, FROM THE EDGE, TURNS -- and the readout follows.
        //
        // The other half of the same rule. The first drag began with slack, so
        // it was a pan, however hard it ended against the edge; this one begins
        // AT the edge, so it is a swipe, and a swipe turns the page (0.8.0
        // build 196, Ali's item D, in performance mode: "I can't swipe to the
        // next page"). Until then this asserted the opposite, because
        // swipe-to-turn was left unwired in 0.6.14 as half-finished; what it
        // lacked -- the edge read at the START of the gesture, the readout
        // following the index -- is what makes both halves hold now.
        drag()
        settle(canvas, still: 0.8)
        snap("second-drag-from-the-edge")
        let turned = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", before),
            object: app.staticTexts["counter-pages"])
        XCTAssertEqual(XCTWaiter().wait(for: [turned], timeout: 10), .completed,
                       "a swipe that began at the edge did not turn the page: "
                       + "still \(app.staticTexts["counter-pages"].label)")
        XCTAssertTrue(app.staticTexts["counter-pages"].label.hasPrefix("p. 2 "),
                      "the readout did not follow the swipe-turn: "
                      + "\(app.staticTexts["counter-pages"].label)")
    }
}
