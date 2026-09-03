import CoreGraphics
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

/// The same handover on the continuous strip, where "off screen" is horizontal
/// and there are no pages at all (bug 6c).
final class ContinuousFollowTests: XCTestCase {
    private let visible = CGRect(x: 1000, y: 0, width: 800, height: 400)

    private func shows(playing: Bool = true, following: Bool = false,
                       x: CGFloat? = 5000, performance: Bool = false) -> Bool {
        PageFollow.showsSync(isPlaying: playing, isFollowing: following,
                             playheadX: x, visible: visible,
                             isPerformanceMode: performance)
    }

    /// The reader scrolled away and the music played on past the edge.
    func testTheChipAppearsWhenTheLineHasRunOffTheScreen() {
        XCTAssertTrue(shows(x: 5000), "the line is far to the right of the viewport")
        XCTAssertTrue(shows(x: 10), "and to the left of it, if they scrolled forward")
    }

    /// While the line is still in view there is nothing to go back to.
    func testNoChipWhileTheLineIsStillOnScreen() {
        XCTAssertFalse(shows(x: 1400))
        XCTAssertFalse(shows(x: visible.minX))
        XCTAssertFalse(shows(x: visible.maxX))
    }

    /// While the app is doing the scrolling there is nothing to sync -- the
    /// same inversion the paged rule exists to avoid.
    func testNoChipWhileTheAppIsStillFollowing() {
        XCTAssertFalse(shows(following: true))
    }

    func testNoChipWhenNothingIsPlaying() {
        XCTAssertFalse(shows(playing: false))
    }

    /// Performance mode exists to remove exactly this.
    func testNoChipInPerformanceMode() {
        XCTAssertFalse(shows(performance: true))
    }

    /// No geometry, no position: every remote-engine render. Nothing is offered
    /// rather than a jump to a guess.
    func testNoChipWithoutAPositionToGoBackTo() {
        XCTAssertFalse(shows(x: nil))
    }
}
