import XCTest

/// The phone gets the same canvas as the iPad.
///
/// design/IPHONE_0.6.14.md §0 and §10.4 step 1. Compact width used a 36-line
/// `ScoreZoomView` -- a bare `PDFView` with `autoScales` -- and everything the
/// score view is made of was absent behind it: no Pencil markup, no lasso, no
/// selection, no playhead, no page counter, no thumbnail rail, and a zoom
/// ceiling of 5 rather than 12.
///
/// Nothing else in 0.6.14 is testable until this lands, which is why it is
/// step one: tap selection, the loupe and the armed lasso are all things that
/// happen ON the canvas, and there was no canvas to put them on.
///
/// Asserted through what the canvas RAISES rather than by naming the type:
/// a test that checked for a class name would pass on a canvas that drew
/// nothing.
final class OneCanvasEverywhere: XCTestCase {

    private var app: XCUIApplication!

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func openAScore() -> Bool {
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 240)
        let row = app.descendants(matching: .any)["row-sous-le-ciel-de-paris"]
        guard row.waitForExistence(timeout: 180) else { return false }
        row.tap()
        let choice = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                  "arrangement-choice-")).firstMatch
        if choice.waitForExistence(timeout: 60) { settle(choice); choice.tap() }
        return app.buttons["score-title"].waitForExistence(timeout: 300)
    }

    /// The engraved page itself. `canvas-<n>` is what `ScorePagesView` puts on
    /// each page and what every iPad test waits for; the phone stub raised
    /// nothing at all.
    private func engravedPage() -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas-"))
            .firstMatch
    }

    /// ONE launch, three claims. Each of these used to reset and re-seed the
    /// library, which is 300s of engine work apiece for assertions that all
    /// look at the same opened score.
    func testThePhoneGetsTheRealCanvas() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        guard openAScore() else { return XCTFail("the score never opened") }

        // 1. THE CANVAS ITSELF. `canvas-N` is what ScorePagesView puts on each
        // page and what every iPad test waits for; the PDFView stub raised
        // nothing at all, so this is the assertion that actually discriminates.
        XCTAssertTrue(engravedPage().waitForExistence(timeout: 240),
                      "the phone is not drawing the engraved canvas: no "
                      + "canvas-N element exists, which is what ScorePagesView "
                      + "raises and the PDFView stub never did")
        settle(engravedPage(), still: 0.8)
        snap("phone-real-canvas")

        // 2. The page counter. Weaker than it looks and kept as a regression
        // guard rather than as proof: it lives in ContentView's overlay, not
        // in the canvas, so it passed against the stub too.
        let counter = app.staticTexts["counter-pages"]
        XCTAssertTrue(counter.waitForExistence(timeout: 60),
                      "no page counter on the phone")
        XCTAssertTrue(counter.label.contains("/"),
                      "the counter says \"\(counter.label)\"")

        // 3. The score view's own controls, which §6.1 says are the same at
        // every size class.
        for id in ["score-close", "score-edit", "score-ask", "score-more"] {
            XCTAssertTrue(app.buttons[id].exists,
                          "\(id) is missing on the phone")
        }
        snap("phone-score-chrome")
    }
}
