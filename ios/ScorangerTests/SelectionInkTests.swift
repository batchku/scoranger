import CoreGraphics
import XCTest

/// The rule that makes the selection ink a size on SCREEN.
///
/// Stated as arithmetic here and photographed at two zooms by
/// `InkZoomShot.testTheSelectionInkKeepsItsWeightAtAnyZoom`, the way the
/// playhead's weight was proved. Neither is enough on its own: the arithmetic
/// cannot see whether the view divides by the right thing, and a screenshot
/// cannot say what the number should have been.
final class SelectionInkTests: XCTestCase {

    /// The whole of bug 8, in one assertion: what is drawn 0.75pt wide inside
    /// the zoom must be written smaller as the zoom grows.
    func testAViewPointStaysAViewPointAtEveryZoom() {
        for zoom in [1, 1.5, 2, 3, 6, 12] as [CGFloat] {
            let drawn = SelectionInk.onScreen(SelectionInk.lassoWeight, zoom: zoom)
            XCTAssertEqual(drawn * zoom, SelectionInk.lassoWeight, accuracy: 0.0001,
                           "at \(zoom)x the outline lands \(drawn * zoom)pt wide "
                           + "on screen instead of \(SelectionInk.lassoWeight)")
        }
    }

    /// The regression the render overhaul introduced, named by its numbers: the
    /// ceiling went from 3 to 12, so the undivided outline went from bad to
    /// unusable.
    func testTheTwelveTimesCeilingIsWhatMadeItUnusable() {
        let undivided = SelectionInk.highlightWeight
        XCTAssertEqual(undivided * PagedCanvas.maximumZoom, 12, accuracy: 0.0001,
                       "the highlight outline would be this many points on screen "
                       + "without the divide")
        XCTAssertEqual(SelectionInk.onScreen(undivided, zoom: PagedCanvas.maximumZoom)
                        * PagedCanvas.maximumZoom,
                       undivided, accuracy: 0.0001)
    }

    /// Zooming OUT must not thicken the ink either. The floor is fit, so this
    /// is defensive -- but the arithmetic is a division and a small zoom is a
    /// large answer.
    func testZoomingOutDoesNotThickenTheInk() {
        XCTAssertEqual(SelectionInk.onScreen(1, zoom: 0.5) * 0.5, 1, accuracy: 0.0001)
    }

    /// A zoom that is not a number yet is 1, not a divide by nearly nothing.
    ///
    /// A `max(zoom, 0.01)` floor would draw a 75pt slab for the frame before
    /// the scroll view reports anything.
    func testAnUnreportedZoomDrawsAtFullSize() {
        for nonsense in [0, -3, CGFloat.nan, CGFloat.infinity] as [CGFloat] {
            XCTAssertEqual(SelectionInk.onScreen(0.75, zoom: nonsense), 0.75,
                           accuracy: 0.0001, "zoom \(nonsense) drew a slab")
        }
    }

    /// The dash keeps its rhythm: at 12x an undivided 2.5pt dash is a 30pt
    /// stripe, which reads as a chain of orange bars rather than a dotted line.
    func testTheDashKeepsItsRhythm() {
        let dashes = SelectionInk.lassoDashes(zoom: 4)
        XCTAssertEqual(dashes.count, 2)
        XCTAssertEqual(dashes[0] * 4, SelectionInk.lassoDash, accuracy: 0.0001)
        XCTAssertEqual(dashes[0], dashes[1])
    }

    // MARK: - The highlight box: two spaces in one frame

    /// The part that must scale (the element's own size) and the parts that
    /// must not (the padding, the floor) are separated correctly.
    func testTheBoxTracksTheNoteheadWhileItsPaddingStaysOnScreen() {
        // a notehead 10 page-units wide, drawn at 2 content points per unit
        let atOne = SelectionInk.highlightExtent(engraved: 10, scale: 2, zoom: 1)
        XCTAssertEqual(atOne, 20 + SelectionInk.highlightPadding, accuracy: 0.0001)

        // Zoomed 4x, the layout scale grows with the zoom (the page is drawn
        // four times larger), so the notehead's own 20 becomes 80 -- and the
        // padding must still be 3 points ON SCREEN, which is 0.75 here.
        let atFour = SelectionInk.highlightExtent(engraved: 10, scale: 8, zoom: 4)
        XCTAssertEqual(atFour, 80 + SelectionInk.highlightPadding / 4, accuracy: 0.0001)

        // The invariant, stated on screen: however far in the reader zooms,
        // the box overhangs the notehead by the SAME few points. Undivided it
        // overhangs by 3 at 1x and by 36 at 12x, which is the bloom that turned
        // a selected chord into one orange blob.
        XCTAssertEqual((atOne - 20) * 1, SelectionInk.highlightPadding, accuracy: 0.0001)
        XCTAssertEqual((atFour - 80) * 4, SelectionInk.highlightPadding, accuracy: 0.0001)
    }

    /// The floor is a size on screen too: a stem three page-units wide must be
    /// given a visible box at 1x and must not be given a 72pt one at 12x.
    func testTheMinimumBoxIsASizeOnScreen() {
        let tiny = SelectionInk.highlightExtent(engraved: 0.1, scale: 1, zoom: 12)
        XCTAssertEqual(tiny * 12,
                       SelectionInk.highlightMinimum + SelectionInk.highlightPadding,
                       accuracy: 0.0001)
    }

    // MARK: - Where a lasso landed

    /// Unit points know nothing about units, which is exactly why one
    /// conversion serves the page and the strip.
    func testUnitPointsConvertByThePagesOwnSize() {
        // the strip: 383690 SVG units wide, 5400 tall
        let strip = CGSize(width: 383690, height: 5400)
        let middle = LassoPath.onPage(unit: [CGPoint(x: 0.5, y: 0.5)], pageSize: strip)
        XCTAssertEqual(middle[0].x, 191845, accuracy: 0.5)
        XCTAssertEqual(middle[0].y, 2700, accuracy: 0.5)

        // the same unit point on a PAGE lands in the middle of the page. If the
        // strip's PDF width (16970 points) had leaked into either side of this,
        // one of the two would be twenty-two times wrong.
        let page = CGSize(width: 2100, height: 2970)
        let onPage = LassoPath.onPage(unit: [CGPoint(x: 0.5, y: 0.5)], pageSize: page)
        XCTAssertEqual(onPage[0].x, 1050, accuracy: 0.5)
        XCTAssertEqual(onPage[0].y, 1485, accuracy: 0.5)
    }

    /// A lasso drawn near the right-hand end of the strip resolves near the end
    /// of the ENGRAVING, not off it. The 22x error looked exactly like this:
    /// a stroke a fifth of the way in resolved past the last bar.
    func testAStrokeNearTheEndOfTheStripStaysOnIt() {
        let strip = CGSize(width: 383690, height: 5400)
        let path = LassoPath.onPage(
            unit: [CGPoint(x: 0.90, y: 0.2), CGPoint(x: 0.95, y: 0.8)],
            pageSize: strip)
        for point in path {
            XCTAssertLessThanOrEqual(point.x, strip.width)
            XCTAssertLessThanOrEqual(point.y, strip.height)
        }
        XCTAssertEqual(path[0].x / strip.width, 0.90, accuracy: 0.001)
    }

    func testAPageWithNoSizeCatchesNothing() {
        XCTAssertTrue(LassoPath.onPage(unit: [CGPoint(x: 0.5, y: 0.5)],
                                       pageSize: .zero).isEmpty)
    }
}
