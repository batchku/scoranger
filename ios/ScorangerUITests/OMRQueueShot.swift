import XCTest

/// The transcription queue, and the contradiction it was built to close.
///
/// Ali, 2026-09-14: "if I go to a different arrangement that is PDF only and
/// see that progress bar, then it doesn't make sense that 'Make Editable' is
/// not on." So the pictures are of a library with three transcriptions in
/// flight, and then of two different arrangements: the one being transcribed
/// and one that is not.
///
/// `-seedOMRQueue` puts the rows in with no network: three jobs against real
/// arrangements, one running with a bar and two waiting. Nothing is uploaded
/// and nothing finishes, which is what makes the picture repeatable.
///
/// It asserts nothing about the product and is skipped by the gate.
final class OMRQueueShot: XCTestCase {
    private var app: XCUIApplication!

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func pause(_ seconds: TimeInterval) {
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "pause")],
                             timeout: seconds)
    }

    func testPhotographTheQueueAndTheScoresItBelongsTo() throws {
        app = XCUIApplication()
        // -resetLibrary, because the scan seed skips itself when a scanned
        // score is already there and this shot wants two of them.
        app.launchArguments = ["-resetLibrary", "-resetViewPreferences",
                               "-seedTestLibrary",
                               "-seedScanArrangement", "-seedSecondScan",
                               "-seedOMRQueue"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 240)
        waitForTheLibraryToSettle(app)
        let queued = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "importing-")).firstMatch
        guard queued.waitForExistence(timeout: 60) else {
            return XCTFail("the seeded queue never appeared in the library")
        }
        pause(1)
        snap("omr-queue-in-the-library")

        // The arrangement being transcribed: its chip reads its own progress.
        openScore(named: "Another scan")
        pause(2)
        snap("omr-the-score-being-transcribed")
        if app.buttons["score-more"].exists {
            app.buttons["score-more"].tap(); pause(1)
            snap("omr-more-screen-of-the-score-being-transcribed")
            app.buttons["panel-done"].firstMatch.tap(); pause(1)
        }
        if app.buttons["score-close"].exists { app.buttons["score-close"].tap() }

        // A DIFFERENT arrangement, a scan, with no transcription of its own:
        // no chip, and Make editable on offer. The pair Ali named.
        pause(1)
        openScore(named: "Scanned score")
        pause(2)
        snap("omr-a-different-scan-no-chip")
        if app.buttons["score-more"].exists {
            app.buttons["score-more"].tap(); pause(1)
            snap("omr-more-screen-of-a-score-not-in-the-queue")
        }
    }

    /// Open an arrangement by the name of the piece that holds it.
    private func openScore(named piece: String) {
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                  "row-\(piece.lowercased().replacingOccurrences(of: " ", with: "-"))"))
            .firstMatch
        guard row.waitForExistence(timeout: 120) else {
            return print("SHOT: no library row for \(piece)")
        }
        row.tap()
        let choice = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                  "arrangement-choice-")).firstMatch
        if choice.waitForExistence(timeout: 60) { choice.tap() }
        _ = app.buttons["score-title"].waitForExistence(timeout: 240)
    }
}
