import XCTest

/// Nothing is cut off, on any screen, at any text size a reader might set.
///
/// §6.3: every type role in this app is `UIFontMetrics.scaledFont` and caption1
/// runs 12pt at Large to 36pt at AX5 -- a 3x range -- while every fixed row
/// height in the app is a 1.0x number. The mixer proved what that costs: at
/// accessibility-extra-large its panel drew 320.5pt wide where the arithmetic
/// had placed a 268pt one, hung 23pt off the screen, and truncated the close
/// button, the caption, the tempo and both transport readouts.
///
/// That bug was invisible to every test in the suite, and it is the one check
/// that would have caught it: launch at two sizes above the default and ask
/// the WINDOW whether each screen's labelled controls are inside it. It uses
/// the same `assertFitsOnScreen` the selection chip does, so there is one
/// spelling of "is it cut off" rather than two that could drift.
///
/// `-UIPreferredContentSizeCategoryName` sets the size on the launch rather
/// than `simctl ui content_size`, so it belongs to the test and the gate
/// carries it.
final class DynamicTypeFits: XCTestCase {

    /// The default, one big step, and the accessibility size that made the
    /// mixer's failure obvious.
    private static let sizes = [
        ("XXXL", "UICTContentSizeCategoryXXXL"),
        ("accessibility-large", "UICTContentSizeCategoryAccessibilityL"),
    ]

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func launch(_ size: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary",
                               "-UIPreferredContentSizeCategoryName", size]
        app.launch()
        return app
    }

    /// ONE launch per size, walking the screens in the order a reader meets
    /// them. Seeding the library is minutes of engine work and every screen
    /// below is reached from the same seeded state.
    func testEveryScreenFitsAtLargeTextSizes() {
        for (name, category) in Self.sizes {
            let app = launch(category)
            XCUIDevice.shared.orientation = .portrait

            // 1. THE LIBRARY, which is the first thing anyone sees.
            let search = app.descendants(matching: .any)["library-search"]
            XCTAssertTrue(search.waitForExistence(timeout: 240),
                          "[\(name)] the library never appeared")
            settle(search, still: 0.6)
            // The action row too, at these sizes. It is the row Ali found
            // clipped at both edges on 0.6.14, and `LibraryBarLayout` is
            // supposed to yield labels until it fits AT THE TEXT SIZE IN
            // FORCE -- so the sizes above Large are the ones that check the
            // measurement rather than the arithmetic.
            assertFitsOnScreen(["library-search", "library-import",
                                "library-new", "library-sort",
                                "library-filter", "library-edit"],
                               in: app, context: "library/\(name)")
            snap("library-\(name)")

            // 2. THE SCORE VIEW, where the whole of 0.6.14 lives. Its top bar
            // is fitted by arithmetic over 1.0x widths (`ScoreBarLayout`), so
            // it is exactly the surface §6.3 rule 3 warns will seat controls
            // it cannot draw.
            let row = app.descendants(matching: .any)["row-sous-le-ciel-de-paris"]
            guard row.waitForExistence(timeout: 180) else {
                XCTFail("[\(name)] no arrangement to open")
                continue
            }
            row.tap()
            let choice = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                      "arrangement-choice-")).firstMatch
            if choice.waitForExistence(timeout: 60) { settle(choice); choice.tap() }
            guard app.buttons["score-title"].waitForExistence(timeout: 300) else {
                XCTFail("[\(name)] the score never opened")
                continue
            }
            settle(app.buttons["score-title"], still: 0.8)
            let bar = ["score-close", "score-title", "score-select",
                       "score-ask", "score-more", "counter-pages",
                       "scrubber-page", "page-scrubber"]
            assertFitsOnScreen(bar, in: app, context: "score bar/\(name)")
            assertNotTruncated(["score-select", "score-ask", "score-more"],
                               in: app, context: "score bar/\(name)")
            snap("score-\(name)")

            // 3. THE OPTIONS SCREEN, which carries every control the bar
            // yielded -- so at a large text size it is carrying MORE, not
            // less, and is the screen most likely to overflow.
            app.descendants(matching: .any)["score-more"].firstMatch.tap()
            let annotations = app.descendants(matching: .any)["more-annotations"]
            if annotations.waitForExistence(timeout: 30) {
                settle(annotations, still: 0.5)
                assertFitsOnScreen(["more-annotations", "more-chords",
                                    "more-performance"],
                                   in: app, context: "options/\(name)")
                snap("options-\(name)")
            } else {
                XCTFail("[\(name)] the options screen never appeared")
            }
            app.terminate()
        }
    }
}
