import XCTest

/// The frame between pressing a layout cell and the new pages arriving
/// (Ali, 2026-09-14 #2: "switching the score canvas between one page, two
/// pages and scroll shows the WRONG view for a moment").
///
/// A one-frame fault cannot be asserted from XCUITest -- there is no way to
/// sample the frame buffer on a schedule -- so this photographs it instead.
/// After each press it takes SEVERAL screenshots back to back with nothing
/// waited on between them, which lands inside the engrave window (continuous
/// is a different Verovio document and takes seconds), and then one more once
/// the canvas has settled.
///
/// Read the pictures in pairs. Before the fix, the shots taken during the
/// switch show the pages the canvas is still holding drawn under the NEW
/// layout's rules -- a paged document stretched as a strip, a strip squeezed
/// into a page frame. After it, every shot during the switch is the OLD
/// layout, coherent, until the settled shot shows the new one.
///
/// It carries no assertions and cannot fail a build; it is evidence, and
/// evidence is looked at.
final class LayoutSwitchShot: XCTestCase {
    private var app: XCUIApplication!

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Press a layout cell and photograph the moment after, several times,
    /// with nothing waited on: these are the frames the flash lives in.
    private func press(_ cell: String, named: String, bursts: Int = 5) {
        let button = app.buttons["layout-\(cell)"]
        guard button.waitForExistence(timeout: 30) else {
            return XCTFail("no layout cell \(cell)")
        }
        button.tap()
        for shot in 1...bursts { snap("\(named)-during-\(shot)") }
        // Long enough for the engrave: the render is the largest cost in the
        // app and continuous re-engraves the whole score.
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "settle")], timeout: 12)
        snap("\(named)-settled")
    }

    func testPhotographTheSwitchBetweenLayouts() throws {
        app = XCUIApplication()
        app.launchArguments = ["-resetViewPreferences", "-seedTestLibrary"]
        app.launch()
        var step = ""
        guard openTray(app, step: &step) != nil else { return XCTFail(step) }
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "settle")], timeout: 3)
        snap("one-page-at-rest")

        press("spread", named: "to-two-pages")
        press("continuous", named: "to-scroll")
        press("page", named: "back-to-one-page")
    }
}
