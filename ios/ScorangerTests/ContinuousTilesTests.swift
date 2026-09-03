import CoreGraphics
import XCTest

/// The continuous strip's geometry.
final class ContinuousTilesTests: XCTestCase {
    /// The real shape: an eleven-page quartet engraved with breaks:none comes
    /// back about 21114 x 538 points.
    private let strip = CGSize(width: 21114, height: 538)

    // MARK: - Fitting

    /// A single-voice tune: `breaks: none` plus `adjustPageHeight` trims the
    /// strip to its one staff, and one staff is SHORT.
    private let oneStaff = CGSize(width: 9400, height: 150)

    /// A tall iPad in portrait, with the transport's reserve.
    private let portrait = CGSize(width: 1032, height: 1250)

    /// A system tall enough that fitting its height is the binding constraint
    /// -- more staves than half a page holds.
    private let bigSystem = CGSize(width: 30000, height: 900)

    /// Continuous is bound by HEIGHT. Fitting its width would scale a 21000pt
    /// strip into 1200pt of glass, which is not notation any more.
    func testTheStripIsFittedByHeightWhileThatFitsUnderTheCeiling() {
        let scale = ContinuousTiles.fittedScale(pageSize: bigSystem, viewport: portrait)
        XCTAssertEqual(bigSystem.height * scale, portrait.height - 24, accuracy: 0.5,
                       "the strip should fill the height, less its margins")
        XCTAssertGreaterThan(bigSystem.width * scale, portrait.width,
                             "and be far wider than the viewport, which is the point")
    }

    /// The pill's reserve is honoured here too, or the strip sits under it --
    /// the same defect as L21, one layout over.
    func testTheChromeIsKeptClear() {
        let scale = ContinuousTiles.fittedScale(pageSize: bigSystem, viewport: portrait,
                                                bottomChrome: 84)
        XCTAssertEqual(bigSystem.height * scale, portrait.height - 24 - 84, accuracy: 0.5)
    }

    // MARK: - The ceiling (#9)

    /// #9: a single-voice tune was stuck at giant notes with nothing below to
    /// zoom out to, because the zoom floor IS this fit and this fit had no
    /// upper bound. Fitting 150pt of staff into a portrait iPad is 8x.
    func testASingleStaffIsNotBlownUpToFillTheHeight() {
        let unbounded = (portrait.height - 24) / oneStaff.height
        XCTAssertGreaterThan(unbounded, 8, "the fixture should be the pathological case")
        let scale = ContinuousTiles.fittedScale(pageSize: oneStaff, viewport: portrait)
        XCTAssertLessThan(scale, 2, "one staff must not be magnified eight times")
        XCTAssertEqual(scale,
                       ContinuousTiles.maximumMagnification
                           * ContinuousTiles.pageScale(viewport: portrait),
                       accuracy: 0.001, "it lands on the ceiling, not on fit-height")
    }

    /// The rule, stated: the strip is never drawn more than twice the size the
    /// same music is on a page fitted to the same viewport.
    func testTheStripIsNeverMoreThanTwiceTheSizeItIsOnAFittedPage() {
        for viewport in [portrait,
                         CGSize(width: 1210, height: 634),
                         CGSize(width: 834, height: 1112),
                         CGSize(width: 390, height: 844)] {
            let ceiling = ContinuousTiles.maximumMagnification
                * ContinuousTiles.pageScale(viewport: viewport, bottomChrome: 84)
            for size in [strip, oneStaff, CGSize(width: 5000, height: 1100)] {
                let scale = ContinuousTiles.fittedScale(pageSize: size, viewport: viewport,
                                                        bottomChrome: 84)
                XCTAssertLessThanOrEqual(scale, ceiling + 0.001,
                                         "\(size) in \(viewport) is drawn larger than a page")
            }
        }
    }

    /// A tall strip -- many staves -- is still fitted, so it cannot overflow.
    func testATallStripIsStillFittedToTheHeight() {
        let tall = CGSize(width: 30000, height: 2400)
        let scale = ContinuousTiles.fittedScale(pageSize: tall, viewport: portrait,
                                                bottomChrome: 84)
        XCTAssertLessThanOrEqual(tall.height * scale, portrait.height - 24 - 84 + 0.5)
    }

    func testAnEmptyViewportDoesNotDivideByZero() {
        XCTAssertEqual(ContinuousTiles.fittedScale(pageSize: .zero, viewport: .zero), 1)
    }

    // MARK: - What is on screen, in the engraving's own coordinates

    /// The badge read "bar 68" on a score just opened, because the paged
    /// canvas's page-frame arithmetic was being run over a page that does not
    /// exist in continuous mode. The strip is ONE engraving; the slice is the
    /// viewport divided by the scale.
    func testTheVisibleSliceIsTheViewportInEngravedCoordinates() {
        let scale: CGFloat = 0.5
        let viewport = CGRect(x: 1000, y: ContinuousTiles.margin, width: 1000, height: 269)
        let slice = ContinuousTiles.visibleSlice(contentRect: viewport, scale: scale,
                                                 pageSize: strip)
        XCTAssertEqual(slice?.minX, 2000)
        XCTAssertEqual(slice?.minY, 0)
        XCTAssertEqual(slice?.width, 2000)
    }

    /// At the head of the strip the reader is at the head of the MUSIC: bar 1,
    /// the clef, and the left margin before it.
    func testTheHeadOfTheStripIsTheHeadOfTheScore() {
        let slice = ContinuousTiles.visibleSlice(
            contentRect: CGRect(x: 0, y: 0, width: 1000, height: 300),
            scale: 0.5, pageSize: strip)
        XCTAssertEqual(slice?.minX, 0, "the first thing on screen is the first bar")
    }

    func testTheSliceCannotRunPastTheEndOfTheMusic() {
        let slice = ContinuousTiles.visibleSlice(
            contentRect: CGRect(x: strip.width * 0.5 - 100, y: 0, width: 4000, height: 300),
            scale: 0.5, pageSize: strip)
        XCTAssertEqual(slice?.maxX ?? 0, strip.width, accuracy: 0.5)
    }

    func testNoSliceBeforeTheScrollViewHasReported() {
        XCTAssertNil(ContinuousTiles.visibleSlice(contentRect: .zero, scale: 0.5,
                                                  pageSize: strip))
    }

    // MARK: - Tiling

    func testTheTilesCoverTheStripExactlyOnce() {
        let tiles = ContinuousTiles.tiles(surface: strip)
        XCTAssertEqual(tiles.first?.minX, 0)
        XCTAssertEqual(tiles.last!.maxX, strip.width, accuracy: 0.001,
                       "the tiles must reach the end of the score and no further")
        for (a, b) in zip(tiles, tiles.dropFirst()) {
            XCTAssertEqual(a.maxX, b.minX, accuracy: 0.001, "a gap between tiles")
        }
        XCTAssertTrue(tiles.allSatisfy { $0.height == strip.height })
    }

    /// A tile hanging past the end is white space the reader can scroll into.
    func testTheLastTileIsShortRatherThanOverhanging() {
        let tiles = ContinuousTiles.tiles(surface: CGSize(width: 1000, height: 100),
                                          tileWidth: 400)
        XCTAssertEqual(tiles.count, 3)
        XCTAssertEqual(tiles.last?.width, 200)
    }

    func testAnEmptyStripHasNoTiles() {
        XCTAssertTrue(ContinuousTiles.tiles(surface: .zero).isEmpty)
    }

    // MARK: - What is drawn at depth

    /// The whole point: 24 tiles exist, a handful are drawn sharply.
    func testOnlyTheTilesNearTheViewportAreDrawnAtDepth() {
        let tiles = ContinuousTiles.tiles(surface: strip)
        XCTAssertGreaterThan(tiles.count, 20, "the fixture should be a long strip")
        let visible = CGRect(x: 5000, y: 0, width: 1200, height: strip.height)
        let deep = ContinuousTiles.atDepth(tiles: tiles, visible: visible)
        XCTAssertLessThan(deep.count, 8,
                          "drawing them all at depth is what kills the app")
        for index in deep {
            XCTAssertTrue(tiles[index].maxX > 3000 && tiles[index].minX < 8500,
                          "tile \(index) is nowhere near the viewport")
        }
    }

    func testTheTilesEitherSideAreDrawnSoAScrollFindsThemReady() {
        let tiles = ContinuousTiles.tiles(surface: CGSize(width: 4000, height: 100),
                                          tileWidth: 1000)
        let deep = ContinuousTiles.atDepth(
            tiles: tiles, visible: CGRect(x: 1100, y: 0, width: 500, height: 100))
        XCTAssertEqual(deep, [0, 1, 2], "the touched tile and one either side")
    }

    /// Before the scroll view has reported anything.
    func testWithNothingVisibleTheHeadOfTheStripIsDrawn() {
        let tiles = ContinuousTiles.tiles(surface: strip)
        XCTAssertTrue(ContinuousTiles.atDepth(tiles: tiles, visible: .zero).contains(0))
    }

    // MARK: - Tap zones

    func testATapAdvancesOneViewportWidth() {
        XCTAssertEqual(ContinuousTiles.advanced(from: 0, by: 1200, direction: 1,
                                                surfaceWidth: 21114), 1200)
        XCTAssertEqual(ContinuousTiles.advanced(from: 1200, by: 1200, direction: -1,
                                                surfaceWidth: 21114), 0)
    }

    func testATapCannotLeaveTheScore() {
        XCTAssertEqual(ContinuousTiles.advanced(from: 0, by: 1200, direction: -1,
                                                surfaceWidth: 21114), 0)
        XCTAssertEqual(ContinuousTiles.advanced(from: 20000, by: 1200, direction: 1,
                                                surfaceWidth: 21114),
                       21114 - 1200, "the far edge is the end of the music")
    }

    /// A score shorter than the viewport cannot scroll at all.
    func testAShortScoreDoesNotScroll() {
        XCTAssertEqual(ContinuousTiles.advanced(from: 0, by: 1200, direction: 1,
                                                surfaceWidth: 800), 0)
    }
}
