import XCTest

/// The library's action row, on a phone.
///
/// Ali on 0.6.14 b173: the row is clipped at BOTH edges. The import arrow is
/// half off the left, and "Sort: name", the filter icon and the Edit tick run
/// off the right. It is the same class of failure §6.1 and §6.3 fixed on the
/// score screen -- a row that is told how wide it may be, does not fit, and
/// spills over both edges rather than yielding -- in the one place that work
/// did not touch.
///
/// `LibraryActionRow` has no yield order at all. Its only concession to width
/// is `isCompact`, which turns labels into icons below 700pt; below that there
/// is nothing left to give, and 393pt is far below it.
///
/// Asked with `assertFitsOnScreen`, the same window-relative check the
/// selection chip and the Dynamic Type sweep use.
final class LibraryToolbarFits: XCTestCase {

    /// Every control in the row, in the order it is drawn.
    private static let row = [
        "library-import", "library-import-folder", "library-import-book",
        "library-new", "library-new-setlist",
        "library-sort", "library-filter", "library-edit",
    ]

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTheActionRowFitsThePhone() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        let search = app.descendants(matching: .any)["library-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 240),
                      "the library never appeared")
        settle(search, still: 0.8)
        snap("library-action-row")

        // The measurement, printed whether it passes or fails: a row that is
        // 42pt too wide and a row that is 2pt too wide are the same assertion
        // and very different problems.
        let window = app.windows.firstMatch.frame
        var report = ["window \(Int(window.width))pt"]
        for id in Self.row {
            let element = app.descendants(matching: .any)[id].firstMatch
            guard element.exists else { report.append("\(id) MISSING"); continue }
            let f = element.frame
            report.append(String(format: "%@ x=%.1f…%.1f w=%.1f", id,
                                 f.minX, f.maxX, f.width))
        }
        let text = XCTAttachment(string: report.joined(separator: "\n"))
        text.name = "library-row-frames"
        text.lifetime = .keepAlways
        add(text)
        print("LIBROW\n" + report.joined(separator: "\n") + "\nENDLIBROW")

        assertFitsOnScreen(Self.row, in: app, context: "library action row")

        // And every control is REACHABLE, which is the other half of the bug:
        // a row that fits by hiding two of its buttons has not been fixed. If
        // the row scrolls or an overflow menu carries them, they are reachable
        // in a way this test has to follow rather than assume -- so it asserts
        // hittability, which is true of a control on screen and false of one
        // pushed past the edge.
        for id in Self.row {
            let element = app.descendants(matching: .any)[id].firstMatch
            guard element.exists else { continue }
            XCTAssertTrue(element.isHittable,
                          "\(id) is on screen but cannot be tapped: \(element.frame)")
        }
    }
}
