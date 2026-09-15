import XCTest

/// Photographs of size, position, move and duplicate on a mark that is not a
/// chord symbol.
///
/// A SWEEP: it takes pictures for a person to look at and asserts nothing
/// about the product. The reason is measured rather than assumed -- a
/// synthetic pinch reached 1.00, 1.37, 1.61, 5.42 and 5.53 on five runs of the
/// same code, so which bars are on screen after it is not the same twice, and
/// an assertion resting on that is the flake that got three earlier attempts
/// at this deleted (BACKLOG.md, "the chip's adjust row has no end-to-end
/// test"). What makes the pictures reliable is the FIXTURE, not the gesture:
/// `-seedMarkChart` leaves one staff with its notes stripped and a dynamic or
/// a text mark under every bar at two and a half times size, so a tap that
/// lands anywhere on that staff lands on one of them.
final class MarkAdjustShot: XCTestCase {

    private var app: XCUIApplication!

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func settle(_ seconds: TimeInterval = 0.6) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func openTheScore() -> Bool {
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 240)
        let row = app.descendants(matching: .any)["row-sous-le-ciel-de-paris"]
        guard row.waitForExistence(timeout: 300) else { return false }
        row.tap()
        let choice = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                  "arrangement-choice-")).firstMatch
        if choice.waitForExistence(timeout: 60) { choice.tap() }
        return app.buttons["score-title"].waitForExistence(timeout: 300)
    }

    /// Zoom past `TapSelection.noteZoom`, or a tap means the BAR -- and a bar
    /// is a mixed selection, which deliberately gets no adjust row.
    @discardableResult
    private func zoomIn() -> Double {
        func read() -> Double {
            Double((app.scrollViews["score-canvas"].value as? String ?? "")
                .replacingOccurrences(of: "zoom ", with: "")) ?? 0
        }
        var zoom = 0.0
        for _ in 1...4 {
            app.scrollViews["score-canvas"].pinch(withScale: 12, velocity: 5)
            settle(1.2)
            zoom = read()
            if zoom >= 2.2 { break }
        }
        // ...and back out, just past the threshold. At 5.5x most of the screen
        // is the white between two systems; just over 2x it is music, which is
        // where the marks are.
        for _ in 1...6 where zoom > 2.9 {
            app.scrollViews["score-canvas"].pinch(withScale: 0.7, velocity: -3)
            settle(1.0)
            let now = read()
            if now < 2.2 { break }
            zoom = now
        }
        return zoom
    }

    private func clearSelection() {
        let clear = app.buttons["Clear selection"].firstMatch
        if clear.exists { clear.tap(); settle(0.3) }
    }

    /// Tap about the page until one tap lands on a single adjustable mark.
    private func selectAMark() -> String? {
        let chip = app.staticTexts["selection-chip"]
        let size = app.descendants(matching: .any)["adjust-size"]
        var log: [String] = []
        for row in stride(from: 0.16, through: 0.88, by: 0.04) {
            for column in stride(from: 0.16, through: 0.92, by: 0.08) {
                app.windows.firstMatch.coordinate(
                    withNormalizedOffset: CGVector(dx: column, dy: row)).tap()
                settle(0.4)
                log.append(String(format: "%.2f,%.2f %@%@", column, row,
                                  chip.exists ? chip.label : "-",
                                  size.exists ? " ADJUSTABLE" : ""))
                if size.exists {
                    print("MARK-SHOT found at \(column),\(row)")
                    print("MARK-SHOT taps\n" + log.joined(separator: "\n"))
                    return log.joined(separator: "\n")
                }
                clearSelection()
            }
        }
        print("MARK-SHOT taps\n" + log.joined(separator: "\n"))
        return nil
    }

    func testPhotographTheAdjustRowAndTheMoveDestination() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary", "-seedMarkChart"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        guard openTheScore() else { return XCTFail("the score never opened") }
        let canvas = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas-"))
            .firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 300), "no engraved canvas")
        settle(3.0)
        snap("00-the-mark-chart")
        print("MARK-SHOT zoom \(zoomIn())")
        // To the top-left of the page: the marks are on the TOP part, and a
        // pinch leaves the viewport wherever the gesture's centre was.
        for _ in 1...4 {
            app.scrollViews["score-canvas"].swipeRight()
            settle(0.4)
        }
        for _ in 1...4 {
            app.scrollViews["score-canvas"].swipeDown()
            settle(0.4)
        }
        settle(1.0)
        snap("01-zoomed")

        guard let log = selectAMark() else {
            snap("02-no-mark-was-caught")
            print("MARK-SHOT nothing adjustable was caught")
            return
        }
        _ = log
        snap("03-adjust-row-on-a-mark")

        // SIZE, relative: the readout is a multiple, and the caption says
        // what it is a multiple of.
        app.descendants(matching: .any)["adjust-bigger"].firstMatch.tap()
        settle(0.6)
        snap("04-size-one-rung-bigger")
        app.descendants(matching: .any)["adjust-up"].firstMatch.tap()
        settle(0.6)
        snap("05-nudged-up-and-resized")
        let revert = app.descendants(matching: .any)["adjust-revert"].firstMatch
        if revert.exists { revert.tap(); settle(0.6) }

        // MOVE: the prompt, then a tapped bar, then the offset stepper.
        let move = app.descendants(matching: .any)["adjust-move"].firstMatch
        guard move.exists else { snap("06-no-place-row"); return }
        move.tap(); settle(0.6)
        snap("06-move-asks-for-a-bar")
        app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        settle(0.8)
        snap("07-a-bar-is-tapped")
        let later = app.descendants(matching: .any)["place-later"].firstMatch
        if later.exists { later.tap(); settle(0.5); later.tap(); settle(0.6) }
        snap("08-the-offset-stepped")
        let confirm = app.descendants(matching: .any)["place-confirm"].firstMatch
        // A move costs a version and a re-engrave; three seconds caught the
        // OLD page and the picture argued the move had not happened.
        if confirm.exists { confirm.tap(); settle(14.0) }
        snap("09-after-the-move")
    }
}
