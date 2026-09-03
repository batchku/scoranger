import CoreGraphics
import XCTest

/// Which viewport the continuous strip is fitted to.
///
/// The strip is fitted by HEIGHT, so every panel that opens over the canvas --
/// the version band, the ink bar, the transport, the mixer -- takes height and
/// would otherwise re-scale the whole score. A re-scaled strip is a fresh
/// raster for every one of its twenty-odd tiles, which is where the version
/// dropdown's 575 ms went with the raster cache already in place: the cache
/// missed on every tile because every tile's scale had changed.
final class StripFitLatchTests: XCTestCase {

    private let canvas = CGSize(width: 1000, height: 900)

    func testTheFirstViewportIsTheOneFittedTo() {
        XCTAssertEqual(
            ContinuousTiles.fittingViewport(now: canvas, latched: .zero,
                                            sameDocument: true),
            canvas)
    }

    /// The band opening. The music keeps its size and the shorter canvas shows
    /// less of it.
    func testAShorterViewportDoesNotRefit() {
        let withBand = CGSize(width: 1000, height: 700)
        XCTAssertEqual(
            ContinuousTiles.fittingViewport(now: withBand, latched: canvas,
                                            sameDocument: true),
            canvas)
    }

    /// The band closing. Back to the full fit -- and to a scale the cache is
    /// still holding every tile for, so the close costs nothing either.
    func testATallerViewportRefits() {
        let tall = CGSize(width: 1000, height: 950)
        XCTAssertEqual(
            ContinuousTiles.fittingViewport(now: tall, latched: canvas,
                                            sameDocument: true),
            tall)
    }

    /// A rotation or a window resize. There is no sense in which the old fit
    /// still applies, so it is dropped even though the new viewport is shorter.
    func testAChangeOfWidthAlwaysRefits() {
        let rotated = CGSize(width: 1400, height: 700)
        XCTAssertEqual(
            ContinuousTiles.fittingViewport(now: rotated, latched: canvas,
                                            sameDocument: true),
            rotated)
    }

    func testADifferentEngravingDropsTheLatch() {
        let shorter = CGSize(width: 1000, height: 700)
        XCTAssertEqual(
            ContinuousTiles.fittingViewport(now: shorter, latched: canvas,
                                            sameDocument: false),
            shorter)
    }

    /// Sub-point wobble in the width -- SwiftUI reports fractional sizes -- is
    /// not a rotation, and must not throw the fit away.
    func testAFractionOfAPointIsNotARotation() {
        let wobbled = CGSize(width: 1000.2, height: 700)
        XCTAssertEqual(
            ContinuousTiles.fittingViewport(now: wobbled, latched: canvas,
                                            sameDocument: true),
            canvas)
    }

    /// What the latch is FOR, stated as the scale the reader sees: opening a
    /// panel leaves the music exactly the size it was.
    func testTheStripKeepsItsScaleWhenAPanelOpens() {
        let strip = CGSize(width: 17267, height: 541)
        let open = CGSize(width: 1000, height: 700)
        let before = ContinuousTiles.fittedScale(pageSize: strip, viewport: canvas,
                                                 bottomChrome: 82)
        let naive = ContinuousTiles.fittedScale(pageSize: strip, viewport: open,
                                                bottomChrome: 82)
        let latched = ContinuousTiles.fittedScale(
            pageSize: strip,
            viewport: ContinuousTiles.fittingViewport(now: open, latched: canvas,
                                                      sameDocument: true),
            bottomChrome: 82)
        XCTAssertNotEqual(naive, before, accuracy: 0.0001,
                          "the fixture has to actually move, or this proves nothing")
        XCTAssertEqual(latched, before, accuracy: 0.0001)
    }
}
