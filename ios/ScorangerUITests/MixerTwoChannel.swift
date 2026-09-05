import XCTest

/// The panel at its largest, on a TWO-channel score.
///
/// Ali's clipped screenshot (IMG_0192) is a real-device 2-strip panel cut off
/// at the bottom-right, on a stock 13-inch Pro at normal text. Every mixer
/// test before this one used the seeded quartet -- FOUR strips -- and passed.
///
/// The arithmetic says why that matters. `MixerLayout.panelWidth` is
/// `8 + strips * 64 + dividers`, so:
///
///     1 strip   72pt      4 strips  267pt
///     2 strips  137pt     6 strips  397pt
///
/// and the panel is parked at `bounds.width - thatNumber - 4`. But the header
/// it has to draw is the same at every strip count: the ☰ grip, "MIXER",
/// "all voices", "All on", "All off" and the ✕. On the quartet that header
/// fits inside 267pt and the arithmetic is roughly honest. On two strips the
/// header cannot fit in 137pt, so SwiftUI draws the panel as wide as the
/// header needs -- while `origin` has already placed it as if it were 137pt
/// wide. The difference hangs off the right edge.
///
/// Which is the same bug class the Dynamic Type run proved -- a panel
/// positioned by arithmetic that is not what gets drawn -- reached by a
/// trigger that needs no unusual settings at all. Fewer channels, not more.
final class MixerTwoChannel: XCTestCase {

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

    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedTestLibrary",
                               "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryL"]
        app.launch()
        return app
    }

    /// The accordion solo: two staves, both called "Accordion". The same
    /// shape as Ali's Whiskey score (Voice + Acoustic Guitar).
    private func openTwoChannelScore(_ app: XCUIApplication) -> XCUIElement? {
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 90)
        // Both seeded scores are arrangements of ONE piece, so the library
        // shows the piece and the arrangement is chosen behind it. The
        // accordion solo is the two-staff one; the quartet is four.
        let row = app.descendants(matching: .any)["row-sous-le-ciel-de-paris"]
        guard row.waitForExistence(timeout: 120) else { return nil }
        row.tap()
        let choice = app.descendants(matching: .any)[
            "arrangement-choice-under-paris-skies-accordion-solo"]
        guard choice.waitForExistence(timeout: 60) else { return nil }
        settle(choice)
        choice.tap()
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

    private func strips(_ app: XCUIApplication) -> Int {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "strip-mute-")).count
    }

    private func check(_ label: String, _ app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        let box = app.otherElements["mixer"].firstMatch.frame
        print("[\(label)] strips \(strips(app)) panel \(box) window \(window)")
        print("[\(label)] right slack \(window.maxX - box.maxX)pt, "
              + "bottom slack \(window.maxY - box.maxY)pt")
        XCTAssertLessThanOrEqual(box.maxX, window.maxX + 0.5,
                                 "[\(label)] \(box.maxX - window.maxX)pt off the RIGHT")
        XCTAssertLessThanOrEqual(box.maxY, window.maxY + 0.5,
                                 "[\(label)] \(box.maxY - window.maxY)pt off the BOTTOM")
        XCTAssertGreaterThanOrEqual(box.minX, -0.5, "[\(label)] off the left")
        XCTAssertGreaterThanOrEqual(box.minY, -0.5, "[\(label)] off the top")
        // The ✕ is the control that goes first when the header overflows.
        let close = app.buttons["mixer-close"]
        XCTAssertTrue(close.exists && close.isHittable,
                      "[\(label)] the mixer's ✕ is not reachable")
    }

    func testTwoChannelPanelFitsInPortrait() {
        let app = launched()
        guard openTwoChannelScore(app) != nil else { return XCTFail("no mixer") }
        snap("two-channel-portrait")
        check("2ch portrait", app)
    }

    func testTwoChannelPanelFitsInLandscape() {
        let app = launched()
        guard let panel = openTwoChannelScore(app) else { return XCTFail("no mixer") }
        XCUIDevice.shared.orientation = .landscapeLeft
        settle(panel, still: 0.8)
        snap("two-channel-landscape")
        check("2ch landscape", app)
    }

    /// The widest and tallest state: two strips AND the instrument picker
    /// open, which is what Ali's screenshots carry.
    func testTwoChannelPanelFitsWithThePickerOpen() {
        let app = launched()
        guard let panel = openTwoChannelScore(app) else { return XCTFail("no mixer") }
        let sound = app.descendants(matching: .any)["strip-sound-0"]
        guard sound.waitForExistence(timeout: 20) else {
            return XCTFail("no sound chip to open the picker")
        }
        sound.tap()
        _ = app.descendants(matching: .any)["mixer-picker"].waitForExistence(timeout: 20)
        settle(panel, still: 0.5)
        snap("two-channel-picker-portrait")
        check("2ch picker portrait", app)

        XCUIDevice.shared.orientation = .landscapeLeft
        settle(panel, still: 0.8)
        snap("two-channel-picker-landscape")
        check("2ch picker landscape", app)
    }
}
