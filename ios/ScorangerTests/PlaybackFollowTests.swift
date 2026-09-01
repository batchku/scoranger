import CoreGraphics
import XCTest

/// Keeping the sounding bar on screen without taking the score away from the
/// reader. Pure geometry over the strip's surface, so no scroll view, no score
/// and no sound are involved.
final class PlaybackFollowTests: XCTestCase {

    /// A viewport a third of the way into a strip, the shape the continuous
    /// view actually produces: about 21000pt of music across 1200pt of glass.
    private let visible = CGRect(x: 6000, y: 0, width: 1200, height: 540)
    private let surface: CGFloat = 21114

    private func bar(at x: CGFloat, width: CGFloat = 180) -> CGRect {
        CGRect(x: x, y: 0, width: width, height: 540)
    }

    // MARK: - Reluctance

    /// The whole point of the guard band. A view that recentres on every bar
    /// takes the page away from a reader who has just panned to look at it.
    func testABarComfortablyOnScreenDoesNotScrollAtAll() {
        XCTAssertNil(PlaybackFollow.target(bar: bar(at: 6500), visible: visible,
                                           surfaceWidth: surface))
        XCTAssertNil(PlaybackFollow.target(bar: bar(at: 6200), visible: visible,
                                           surfaceWidth: surface))
    }

    /// A bar half off the right edge is exactly when it is hardest to read, so
    /// that is what the guard band catches -- not the moment it has already
    /// gone.
    func testABarAgainstTheTrailingEdgeMovesBeforeItLeaves() {
        let edge = bar(at: visible.maxX - 100)
        let target = PlaybackFollow.target(bar: edge, visible: visible,
                                           surfaceWidth: surface)
        XCTAssertNotNil(target)
        // placed a third in, so two thirds of the viewport is music not yet
        // reached: reading ahead is the point of a scrolling part
        XCTAssertEqual(target!, edge.minX - visible.width / 3, accuracy: 0.5)
    }

    /// A repeat sends the play head BACKWARDS. The band is symmetric so the
    /// strip follows it back rather than sitting on music that has finished.
    func testARepeatScrollsBackwards() {
        let earlier = bar(at: 1000)
        let target = PlaybackFollow.target(bar: earlier, visible: visible,
                                           surfaceWidth: surface)
        XCTAssertNotNil(target)
        XCTAssertLessThan(target!, visible.minX, "the strip must come back for a repeat")
        XCTAssertEqual(target!, 1000 - 400, accuracy: 0.5)
    }

    // MARK: - Ends of the score

    func testTheHeadOfTheScoreIsNotScrolledPastBackwards() {
        let first = bar(at: 0)
        let atHead = CGRect(x: 0, y: 0, width: 1200, height: 540)
        // Bar 1 sits against the left edge, inside the guard band, so it moves
        // -- and the move must not produce a negative offset.
        let target = PlaybackFollow.target(bar: first, visible: atHead,
                                           surfaceWidth: surface)
        XCTAssertEqual(target, 0)
    }

    func testTheEndOfTheScoreCannotBeScrolledPast() {
        let last = bar(at: surface - 120)
        let nearEnd = CGRect(x: surface - 1200, y: 0, width: 1200, height: 540)
        let target = PlaybackFollow.target(bar: last, visible: nearEnd,
                                           surfaceWidth: surface)
        if let target {
            XCTAssertLessThanOrEqual(target, surface - 1200,
                                     "white space past the last bar is not a place to be")
        }
    }

    /// A strip shorter than the viewport -- a two-bar sketch -- has nowhere to
    /// scroll, and must not be asked to.
    func testAStripShorterThanTheViewportStaysAtZero() {
        let short: CGFloat = 400
        XCTAssertEqual(PlaybackFollow.seek(bar: bar(at: 300), viewportWidth: 1200,
                                           surfaceWidth: short), 0)
    }

    func testAnUnmeasuredViewportAsksForNothing() {
        XCTAssertNil(PlaybackFollow.target(bar: bar(at: 100),
                                           visible: CGRect(x: 0, y: 0, width: 0, height: 0),
                                           surfaceWidth: surface))
    }

    // MARK: - Seeking

    /// A seek is the reader asking to be taken somewhere, so unlike following
    /// it always answers.
    func testASeekAlwaysMoves() {
        let comfortable = bar(at: 6500)
        XCTAssertNil(PlaybackFollow.target(bar: comfortable, visible: visible,
                                           surfaceWidth: surface))
        XCTAssertEqual(PlaybackFollow.seek(bar: comfortable, viewportWidth: 1200,
                                           surfaceWidth: surface),
                       6500 - 400, accuracy: 0.5)
    }

    // MARK: - Page coordinates to surface coordinates

    func testABarsFrameScalesWithTheStrip() {
        let page = CGRect(x: 1000, y: 20, width: 200, height: 500)
        let framed = PlaybackFollow.surfaceFrame(pageFrame: page, scale: 0.5)
        XCTAssertEqual(framed, CGRect(x: 500, y: 10, width: 100, height: 250))
    }

    // MARK: - Paged mode

    /// Following in paged mode is a turn, and only when the bar is elsewhere:
    /// a player reading a page is not interrupted by a turn they did not need.
    func testAPageAlreadyOnScreenIsNotTurnedTo() {
        XCTAssertNil(PlaybackFollow.turn(toPage: 2, showing: [2], spread: false))
        XCTAssertNil(PlaybackFollow.turn(toPage: 3, showing: [2, 3], spread: true))
    }

    func testAPageElsewhereTurnsToItsUnit() {
        XCTAssertEqual(PlaybackFollow.turn(toPage: 5, showing: [2], spread: false), 5)
        // a spread's unit is the even page it opens on
        XCTAssertEqual(PlaybackFollow.turn(toPage: 5, showing: [2, 3], spread: true), 4)
    }
}
