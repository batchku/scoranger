import XCTest

/// Turning a page during playback hands control over, and a button hands it
/// back. design/PLAYBACK.md, revised.
final class PageFollowTests: XCTestCase {

    func testFollowingIsOnUntilTheReaderTurnsAPage() {
        var follow = PageFollow()
        XCTAssertTrue(follow.isFollowing)
        follow.readerTurnedPage()
        XCTAssertFalse(follow.isFollowing)
    }

    /// The heart of the revision: it does NOT come back when the music
    /// wanders into view. Only a tap restores it.
    func testFollowingNeverResumesOnItsOwn() {
        var follow = PageFollow()
        follow.readerTurnedPage()
        // the playhead arriving on the visible page changes nothing
        XCTAssertFalse(PageFollow.showsSync(isPlaying: true,
                                            isFollowing: follow.isFollowing,
                                            playheadPage: 2, visiblePages: [2],
                                            isPerformanceMode: false))
        XCTAssertFalse(follow.isFollowing, "it must still be the reader's page")
        follow.syncTapped()
        XCTAssertTrue(follow.isFollowing)
    }

    func testTheChipAppearsOnlyWhenTheReaderHasDriftedAway() {
        XCTAssertTrue(PageFollow.showsSync(isPlaying: true, isFollowing: false,
                                           playheadPage: 5, visiblePages: [2],
                                           isPerformanceMode: false))
        XCTAssertFalse(PageFollow.showsSync(isPlaying: true, isFollowing: false,
                                            playheadPage: 2, visiblePages: [2],
                                            isPerformanceMode: false),
                       "the playhead is on the page they are looking at")
    }

    /// The gate that stops the chip blinking on every automatic page turn.
    /// Auto-follow turns at 85% of the page, BEFORE the playhead leaves, so
    /// for a moment the next page is showing and the playhead is behind it.
    func testItDoesNotBlinkDuringAnAutomaticPageTurn() {
        XCTAssertFalse(PageFollow.showsSync(isPlaying: true, isFollowing: true,
                                            playheadPage: 1, visiblePages: [2],
                                            isPerformanceMode: false),
                       "the app is doing the paging; there is nothing to sync")
    }

    /// It belongs to playback. Stopping while paged away must not leave it
    /// stranded on screen.
    func testItIsGoneWhenNothingIsPlaying() {
        XCTAssertFalse(PageFollow.showsSync(isPlaying: false, isFollowing: false,
                                            playheadPage: 5, visiblePages: [2],
                                            isPerformanceMode: false))
    }

    /// On a spread, EITHER leaf counts as visible.
    func testEitherPageOfASpreadCounts() {
        XCTAssertFalse(PageFollow.showsSync(isPlaying: true, isFollowing: false,
                                            playheadPage: 4, visiblePages: [4, 5],
                                            isPerformanceMode: false))
        XCTAssertFalse(PageFollow.showsSync(isPlaying: true, isFollowing: false,
                                            playheadPage: 5, visiblePages: [4, 5],
                                            isPerformanceMode: false))
        XCTAssertTrue(PageFollow.showsSync(isPlaying: true, isFollowing: false,
                                           playheadPage: 6, visiblePages: [4, 5],
                                           isPerformanceMode: false))
    }

    /// Performance mode hides chrome, and this is chrome.
    func testPerformanceModeHasNoChip() {
        XCTAssertFalse(PageFollow.showsSync(isPlaying: true, isFollowing: false,
                                            playheadPage: 5, visiblePages: [2],
                                            isPerformanceMode: true))
    }

    /// No geometry, no chip: the remote-engine path builds none, and a jump to
    /// a guessed page is worse than no button.
    func testNoGeometryOffersNothing() {
        XCTAssertFalse(PageFollow.showsSync(isPlaying: true, isFollowing: false,
                                            playheadPage: nil, visiblePages: [2],
                                            isPerformanceMode: false))
    }

    /// A different score is not a resumption -- there is no page the reader
    /// chose any more.
    func testAnotherScoreStartsFollowingAgain() {
        var follow = PageFollow()
        follow.readerTurnedPage()
        follow.loadedSomethingElse()
        XCTAssertTrue(follow.isFollowing)
    }

    /// Musicians navigate by bar.
    func testTheChipNamesTheBarItWillTakeYouTo() {
        XCTAssertEqual(PageFollow.syncLabel(bar: 34), "Back to bar 34")
        XCTAssertEqual(PageFollow.syncLabel(bar: nil), "Back to playback")
    }
}
