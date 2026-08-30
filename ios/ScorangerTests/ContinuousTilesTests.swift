import CoreGraphics
import XCTest

/// The continuous strip's geometry.
final class ContinuousTilesTests: XCTestCase {
    /// The real shape: an eleven-page quartet engraved with breaks:none comes
    /// back about 21114 x 538 points.
    private let strip = CGSize(width: 21114, height: 538)

    // MARK: - Fitting

    /// Continuous is bound by HEIGHT. Fitting its width would scale a 21000pt
    /// strip into 1200pt of glass, which is not notation any more.
    func testTheStripIsFittedByHeight() {
        let viewport = CGSize(width: 1210, height: 634)
        let scale = ContinuousTiles.fittedScale(pageSize: strip, viewport: viewport)
        XCTAssertEqual(strip.height * scale, 634 - 24, accuracy: 0.5,
                       "the strip should fill the height, less its margins")
        XCTAssertGreaterThan(strip.width * scale, viewport.width,
                             "and be far wider than the viewport, which is the point")
    }

    /// The pill's reserve is honoured here too, or the strip sits under it --
    /// the same defect as L21, one layout over.
    func testTheChromeIsKeptClear() {
        let viewport = CGSize(width: 1210, height: 634)
        let scale = ContinuousTiles.fittedScale(pageSize: strip, viewport: viewport,
                                                bottomChrome: 84)
        XCTAssertEqual(strip.height * scale, 634 - 24 - 84, accuracy: 0.5)
    }

    func testAnEmptyViewportDoesNotDivideByZero() {
        XCTAssertEqual(ContinuousTiles.fittedScale(pageSize: .zero, viewport: .zero), 1)
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
