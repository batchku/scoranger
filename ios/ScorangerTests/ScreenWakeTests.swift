import XCTest

/// The screen stays lit for the reader, and for nobody else.
///
/// Ali's iPad dims and locks while he plays, because someone reading a score
/// touches the glass once a page and the system counts that as idle.
///
/// The reason this is a rule and not a line of code is the other half of it.
/// `isIdleTimerDisabled` belongs to the APPLICATION, so setting it in the score
/// view without clearing it anywhere holds the screen awake over the library,
/// over Settings, and until the app is killed — a battery bug shipped as a
/// feature. Every case below that expects `false` is that bug.
final class ScreenWakeTests: XCTestCase {

    private func lit(reading: Bool, playing: Bool = false, active: Bool = true) -> Bool {
        ScreenWake.shouldStayLit(readingScore: reading, playing: playing, appActive: active)
    }

    func testAScoreLeftUntouchedStaysLit() {
        XCTAssertTrue(lit(reading: true))
    }

    func testTheLibraryKeepsTheSystemsOwnTimer() {
        XCTAssertFalse(lit(reading: false),
                       "holding the screen awake over a list is a battery bug")
    }

    func testPlaybackIsReasonEnoughOnItsOwn() {
        // sound coming out of the device is not idleness, whatever is on screen
        XCTAssertTrue(lit(reading: false, playing: true))
        XCTAssertTrue(lit(reading: true, playing: true))
    }

    func testTheClaimIsDroppedWhenTheAppGoesAway() {
        // the idle timer means nothing in the background; what matters is that
        // the flag is not left set for whatever the reader does next
        XCTAssertFalse(lit(reading: true, active: false))
        XCTAssertFalse(lit(reading: true, playing: true, active: false))
        XCTAssertFalse(lit(reading: false, active: false))
    }

    func testItIsTakenAgainOnTheWayBack() {
        // the sequence Ali will actually perform: reading, home button, back
        var conditions = ScreenWake.Conditions(readingScore: true, playing: false,
                                               appActive: true)
        XCTAssertTrue(ScreenWake.shouldStayLit(conditions))
        conditions.appActive = false
        XCTAssertFalse(ScreenWake.shouldStayLit(conditions))
        conditions.appActive = true
        XCTAssertTrue(ScreenWake.shouldStayLit(conditions),
                      "returning to a score that is still open should light it again")
    }

    func testLeavingTheScoreGivesTheScreenBack() {
        var conditions = ScreenWake.Conditions(readingScore: true, playing: false,
                                               appActive: true)
        XCTAssertTrue(ScreenWake.shouldStayLit(conditions))
        conditions.readingScore = false          // X back to the library
        XCTAssertFalse(ScreenWake.shouldStayLit(conditions))
    }

    func testNothingOpenAndNothingPlayingIsNotAReason() {
        XCTAssertFalse(lit(reading: false, playing: false))
    }
}
