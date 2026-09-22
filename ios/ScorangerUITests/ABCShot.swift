import XCTest

/// A tune from thesession.org, imported and ENGRAVED, photographed.
///
/// A tune that imports and engraves as nonsense is worse than a refusal: the
/// library says it worked and the page says otherwise, and only a person
/// looking at the page can tell. So this drops a real `.abc` file into the
/// inbox with `-seedInboxABC` -- the same folder a download or an AirDrop
/// lands in -- and lets the app's own scanner pick it up. Nothing is placed
/// in the library behind the import's back.
///
/// The tune is eight bars in E dorian with a repeat and first and second
/// endings, so the photograph shows the things most likely to be silently
/// lost: the two sharps, the `|:` and `:|`, and the two endings over the
/// bars they belong to.
///
/// It asserts nothing about the product and is skipped by the gate. The
/// pictures come out of the result bundle, not SCORANGER_SHOT_DIR
/// (REDESIGN_BRIEF_0.8 §2.4).
final class ABCShot: XCTestCase {
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

    func testPhotographATuneImportedFromABC() throws {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-resetViewPreferences",
                               "-seedInboxABC"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 240)

        // THE PAGE, and it comes first because the app OPENS what it just
        // imported -- the library is behind the score, which is why looking
        // for a library row here finds one that is never hittable.
        //
        // This is the picture to look at: two sharps for E dorian, the
        // opening repeat, and the first and second endings over the bars they
        // belong to. A tune that engraves as nonsense is worse than a refusal,
        // and only eyes can tell.
        guard app.buttons["score-title"].waitForExistence(timeout: 240) else {
            snap("abc-nothing-opened")
            return print("SHOT: the seeded tune never opened")
        }
        pause(4)
        snap("abc-the-engraved-tune")

        if app.buttons["score-more"].exists {
            app.buttons["score-more"].tap(); pause(1)
            snap("abc-the-arrangement-screen")
            if app.buttons["panel-done"].firstMatch.exists {
                app.buttons["panel-done"].firstMatch.tap(); pause(1)
            }
        }

        // And the library behind it: the piece the filing rule made, named
        // after the tune, with the arrangement filed under it.
        if app.buttons["score-close"].exists {
            app.buttons["score-close"].tap()
            waitForTheLibraryToSettle(app)
            pause(2)
            snap("abc-the-library-after-importing-a-tune")
        }
    }
}
