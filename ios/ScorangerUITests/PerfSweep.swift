import XCTest

/// The measurement run, against the real app.
///
/// Not a gate. It asserts almost nothing, because there is no agreed budget
/// yet -- the point is to produce NUMBERS for a report that has so far been
/// "the app is starting to feel slow". Once a budget is agreed the assertions
/// belong here; guessing one now would be inventing a requirement.
///
/// It is skipped in `scripts/gate.sh` for the same reason the screenshot
/// sweeps are: it costs minutes and cannot fail a build.
///
/// Run it on its own:
///   xcodebuild test -project Scoranger.xcodeproj -scheme Scoranger \
///     -destination "platform=iOS Simulator,id=..." \
///     -only-testing:ScorangerUITests/PerfSweep
final class PerfSweep: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws { continueAfterFailure = true }

    private func settle(_ s: TimeInterval = 0.6) { Thread.sleep(forTimeInterval: s) }

    /// `-perfMetrics YES` sets the user default of that name for the launched
    /// process, which is what `PerfMetrics` reads at init. No build flag, no
    /// tapping through Settings before the thing being measured.
    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-seedTestLibrary", "-perfMetrics", "YES",
                               "-perfDump"] + extra
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        settle(1.5)
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
        _ = app.buttons["score-title"].waitForExistence(timeout: 180)
        settle(3.0)   // let the first engrave finish, so it is not charged to a tap
    }

    /// The readings come back in the LOG, not off the screen: `-perfDump`
    /// prints the table every three seconds, so the numbers survive whatever
    /// the panel happens to be scrolled to. Grep the run for SCORANGER-PERF.
    private func readReadings(_ label: String) {
        settle(4.0)   // one dump interval, so the last taps are in the table
        let note = XCTAttachment(string: "readings for \(label) are in the run "
                                 + "log under SCORANGER-PERF")
        note.name = label
        note.lifetime = .keepAlways
        add(note)
    }

    /// The owner's named example: "clicking on the drop-down for versions and a
    /// score can take a second". Ten opens, so the reading is a distribution
    /// and not one anecdote.
    func testVersionDropdownLatency() {
        launch()
        openFirstScore()

        for i in 0..<10 {
            let trigger = app.buttons["score-versions"].firstMatch
            guard trigger.waitForExistence(timeout: 10) else {
                XCTFail("no versions control on the bar at open \(i)")
                return
            }
            trigger.tap()
            settle(1.2)          // long enough for the frame to land and be timed
            trigger.tap()        // shut it again, so the next open is an open
            settle(0.8)
        }
        readReadings("version-dropdown")
    }

    /// The same control on the title side, and a version SWITCH -- which is the
    /// one that re-engraves, so the two costs can be told apart.
    func testSwitchingVersionCostsARender() {
        launch()
        openFirstScore()

        let trigger = app.buttons["score-versions"].firstMatch
        guard trigger.waitForExistence(timeout: 10) else {
            XCTFail("no versions control on the bar")
            return
        }
        for _ in 0..<3 {
            trigger.tap()
            settle(1.0)
            let row = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "menu-version-")).firstMatch
            if row.waitForExistence(timeout: 5) {
                row.tap()
                settle(3.0)   // the re-engrave
            } else {
                trigger.tap()
                settle(0.6)
            }
        }
        readReadings("version-switch")
    }
}
