import XCTest

/// The render overhaul's evidence, and its regression.
///
/// The fault it exists to hold shut: Verovio's `setOptions` MERGES, so an
/// option one layout's set names and the other's omits is not a default -- it
/// is a value the first layout leaves on the shared toolkit for the second to
/// find. The paged set did not name `breaks`. One visit to continuous mode set
/// it to "none", and every paged engrave for the rest of the session laid the
/// whole score out as ONE system on one enormous page: no pagination, a counter
/// reading "p. 1 / 1", a blurred raster (the strip is 17000pt wide and the
/// paged canvas caps a page at 5200px) and thumbnails of the whole score
/// squeezed into a page-shaped box.
///
/// So the assertion is the round trip, not the first render: page, then
/// continuous, then page again, and the score must still have its pages.
///
/// Run it on its own, screenshots and all:
///   xcodebuild test -project Scoranger.xcodeproj -scheme Scoranger \
///     -destination "platform=iOS Simulator,id=<udid>" \
///     -only-testing:ScorangerUITests/RenderShot -resultBundlePath out.xcresult
///   xcrun xcresulttool export attachments --path out.xcresult --output-path shots
final class RenderShot: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        // every step photographs something; one missing control must not cost
        // the rest of the evidence
        continueAfterFailure = true
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func settle(_ seconds: TimeInterval = 1.2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @discardableResult
    private func tap(_ id: String, wait: TimeInterval = 6) -> Bool {
        for element in [app.buttons[id], app.otherElements[id], app.staticTexts[id]]
        where element.exists && element.isHittable {
            element.tap()
            return true
        }
        if app.buttons[id].waitForExistence(timeout: wait), app.buttons[id].isHittable {
            app.buttons[id].tap()
            return true
        }
        print("RENDERSHOT: no element \(id)")
        return false
    }

    /// What the page counter says right now, or "" when there is none.
    private var counter: String {
        let chip = app.staticTexts["counter-pages"]
        return chip.exists ? chip.label : ""
    }

    /// The total in "p. 3 / 9", or 0 when the counter is absent.
    private func pages(in label: String) -> Int {
        guard let slash = label.lastIndex(of: "/") else { return 0 }
        return Int(label[label.index(after: slash)...]
            .trimmingCharacters(in: .whitespaces)) ?? 0
    }

    /// Wait for a re-engrave to land. Switching layout re-engraves the whole
    /// score, and the PREVIOUS pages deliberately stay up until the new ones
    /// arrive (#44) -- so a screenshot taken too early is a photograph of the
    /// last layout, whatever the fix did.
    @discardableResult
    private func waitForPages(_ want: (Int) -> Bool,
                              timeout: TimeInterval = 90) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let now = counter
            if want(pages(in: now)) { settle(0.8); return counter }
            settle(0.5)
        }
        return counter
    }

    private func openFirstScore() {
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "row-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 240), "the seeded library never appeared")
        row.tap()
        settle()
        if !app.buttons["score-title"].waitForExistence(timeout: 5) {
            let open = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "arrangement-")).firstMatch
            if open.waitForExistence(timeout: 8) { open.tap() }
        }
        _ = app.buttons["score-title"].waitForExistence(timeout: 120)
        settle(2.5)
    }

    /// Page -> continuous -> page, photographed at every step.
    func testPaginationSurvivesAVisitToContinuous() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        settle(1.5)
        openFirstScore()

        tap("layout-page")
        settle(2.5)
        let first = waitForPages { $0 > 0 }
        snap("01-paged-first-open")
        print("RENDERSHOT: paged on open = \"\(first)\"")

        tap("layout-continuous")
        // the counter goes as soon as the layout does; the STRIP takes as long
        // as an engrave, and the paged canvas stays up until it lands
        waitForPages { $0 == 0 }
        settle(12)
        snap("02-continuous")
        print("RENDERSHOT: continuous counter = \"\(counter)\" (there should be none)")

        tap("layout-page")
        settle(2.0)
        let after = waitForPages { $0 > 1 }
        snap("03-paged-after-continuous")
        print("RENDERSHOT: paged after continuous = \"\(after)\"")

        // The whole bug, in one line.
        XCTAssertGreaterThan(pages(in: after), 1,
                             "a notation score lost its pages on the way back from "
                             + "continuous mode: the counter reads \"\(after)\"")
        XCTAssertEqual(pages(in: after), pages(in: first),
                       "the same music engraved to a different number of pages "
                       + "before (\(first)) and after (\(after)) a visit to continuous")

        // and the strip, which is where the thumbnails come from
        if app.otherElements["thumbnail-strip"].exists {
            snap("04-thumbnail-strip")
        }
    }
}
