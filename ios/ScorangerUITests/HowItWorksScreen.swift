import XCTest

/// Settings -> "How Scoranger works": that it is reachable, that the diagram
/// and the credits are actually on it, and that none of it runs off the side
/// of the screen at a large text size.
///
/// It photographs as it goes, but it is NOT a sweep and is not skipped by the
/// gate: every one of the assertions below can fail. The section is a wall of
/// prose and a column of boxes, which is precisely the shape that survives at
/// Large and breaks at an accessibility size -- §6.3's lesson from the mixer,
/// where a panel drew 23pt off the screen and no test in the suite noticed.
///
/// HORIZONTAL fit only, and deliberately: the section is a ScrollView whose
/// content is several screens tall, so every box below the fold is legitimately
/// outside the window's bottom. `assertFitsOnScreen` asks about all four edges,
/// which is the right question for a bar and the wrong one for a scrolling
/// page. Running off the SIDE is the failure this screen can have.
final class HowItWorksScreen: XCTestCase {

    /// The default, and the size that makes a long line break.
    private static let sizes = [
        ("large", "UICTContentSizeCategoryL"),
        ("accessibility-large", "UICTContentSizeCategoryAccessibilityL"),
    ]

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

    /// Every named element that is on screen sits inside the window
    /// left-to-right. Missing ones are skipped, like `assertFitsOnScreen`:
    /// what is not drawn is a different assertion.
    private func assertNothingRunsOffTheSide(_ identifiers: [String],
                                             in app: XCUIApplication,
                                             context: String) {
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, 0, "no window to measure against [\(context)]")
        for identifier in identifiers {
            let element = app.descendants(matching: .any)[identifier].firstMatch
            guard element.exists, element.frame.width > 0 else { continue }
            let box = element.frame
            XCTAssertLessThanOrEqual(window.minX - box.minX, 0.5,
                                     "\(identifier) is \(window.minX - box.minX)pt off the "
                                     + "LEFT edge [\(context)]: \(box) in \(window)")
            XCTAssertLessThanOrEqual(box.maxX - window.maxX, 0.5,
                                     "\(identifier) is \(box.maxX - window.maxX)pt off the "
                                     + "RIGHT edge [\(context)]: \(box) in \(window)")
        }
    }

    /// The library is not seeded: this screen is static and reads nothing out
    /// of it, and seeding is minutes of engine work per launch.
    private func openTheSection(_ category: String, size: String) -> XCUIApplication? {
        let app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-resetViewPreferences",
                               "-UIPreferredContentSizeCategoryName", category]
        app.launch()
        guard app.descendants(matching: .any)["library-search"]
            .waitForExistence(timeout: 240) else {
            XCTFail("[\(size)] the library never appeared")
            return nil
        }
        app.buttons["library-settings"].tap()
        let index = app.descendants(matching: .any)["settings-split"]
        guard index.waitForExistence(timeout: 20) else {
            XCTFail("[\(size)] Settings never opened")
            return nil
        }
        let item = app.buttons["settings-how-it-works"]
        guard item.waitForExistence(timeout: 10) else {
            XCTFail("[\(size)] there is no How Scoranger works in the index")
            return nil
        }
        item.tap()
        guard app.descendants(matching: .any)["how-it-works"]
            .waitForExistence(timeout: 20) else {
            XCTFail("[\(size)] the section did not open")
            return nil
        }
        return app
    }

    func testTheSectionIsReachableAndReadableAtEveryTextSize() {
        for (size, category) in Self.sizes {
            guard let app = openTheSection(category, size: size) else { continue }
            Thread.sleep(forTimeInterval: 0.8)
            snap("how-it-works-\(size)-1-diagram")

            // The diagram is the part that could be drawn as an image and is
            // not, so it is the part worth asserting exists as views.
            let diagram = app.descendants(matching: .any)["pipeline-diagram"]
            XCTAssertTrue(diagram.exists, "[\(size)] no diagram")
            let boxes = ["pipeline-sources", "pipeline-omr", "pipeline-agent",
                         "pipeline-engine", "pipeline-versions", "pipeline-page"]
            for box in boxes {
                XCTAssertTrue(app.descendants(matching: .any)[box].firstMatch.exists,
                              "[\(size)] the diagram is missing \(box)")
            }
            assertNothingRunsOffTheSide(boxes + ["how-it-works", "pipeline-diagram"],
                                        in: app, context: "diagram/\(size)")

            // Down the section: the prose, then the credits. The scroll is
            // what puts the lower blocks on screen to be measured at all.
            for step in 2...6 {
                app.swipeUp()
                Thread.sleep(forTimeInterval: 0.5)
                snap("how-it-works-\(size)-\(step)")
                assertNothingRunsOffTheSide(
                    ["credits", "credits-omr", "credits-engine", "credits-page",
                     "credits-sound", "credits-type", "credits-account", "credits-chat",
                     "how-passage-in", "how-passage-ops", "how-passage-versions",
                     "how-passage-chat", "how-passage-offline"],
                    in: app, context: "scrolled-\(step)/\(size)")
            }

            // The obligation half: the licences have to be ON the screen, not
            // merely in the data. Verified by reading them back out of the
            // hierarchy at the accessibility size too, where a clipped or
            // dropped block would be easiest to lose.
            let credits = app.descendants(matching: .any)["credits"]
            XCTAssertTrue(credits.exists, "[\(size)] nothing credits anybody")
            app.terminate()
        }
    }

    /// A licence text the screen offers is IN the bundle and reads back on
    /// screen (0.15.0). The unit tests hold the paths to the data and
    /// deploy_testflight.sh holds them to the archive; this is the one check
    /// that the sheet actually finds a folder at runtime, for one credit from
    /// each source: vendor_engine.sh's Python texts, the tracked Licences/
    /// tree, and a single file at the bundle root.
    func testALicenceTextOpensFromTheCreditsAndReads() {
        guard let app = openTheSection("UICTContentSizeCategoryL", size: "large") else { return }
        let cases = [("music21", "Redistribution and use"),
                     ("Verovio", "GNU GENERAL PUBLIC LICENSE"),
                     ("Inter", "SIL OPEN FONT LICENSE")]
        for (name, phrase) in cases {
            let open = app.buttons["licence-\(name)"]
            var swipes = 0
            while !(open.exists && open.isHittable) && swipes < 20 {
                app.swipeUp()
                swipes += 1
            }
            XCTAssertTrue(open.isHittable, "no Read the licence for \(name)")
            open.tap()
            let sheet = app.descendants(matching: .any)["licence-sheet"]
            XCTAssertTrue(sheet.waitForExistence(timeout: 10), "\(name)'s licence did not open")
            let text = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", phrase))
            XCTAssertTrue(text.firstMatch.waitForExistence(timeout: 10),
                          "\(name)'s sheet does not show its licence")
            XCTAssertFalse(app.staticTexts.containing(
                NSPredicate(format: "label BEGINSWITH %@", "This build is missing")).firstMatch.exists,
                           "\(name)'s licence text is missing from the bundle")
            snap("licence-\(name)")
            app.buttons["Done"].tap()
            XCTAssertTrue(sheet.waitForNonExistence(timeout: 10))
        }
        app.terminate()
    }
}
