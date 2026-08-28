import CoreGraphics
import XCTest

/// Ali: the notes stay crisp under deep zoom and the ink over them goes soft.
/// The page re-rasters at the settled zoom; the PencilKit canvas was left at
/// the screen's own scale and magnified by the same transform as everything
/// else, so it is literally a stretched picture.
final class InkSharpnessTests: XCTestCase {

    func testInkIsDrawnFinerAsTheScoreIsZoomedIn() {
        let at1 = InkSharpness.contentScale(zoom: 1, base: 2)
        let at3 = InkSharpness.contentScale(zoom: 3, base: 2)
        XCTAssertEqual(at1, 2, accuracy: 0.001, "at rest the ink is screen scale")
        XCTAssertEqual(at3, 6, accuracy: 0.001, "three times in, three times finer")
        XCTAssertGreaterThan(at3, at1)
    }

    /// The screen's own scale differs between devices, and the ink has to
    /// follow it rather than assume 2x.
    func testItFollowsTheScreenScale() {
        XCTAssertEqual(InkSharpness.contentScale(zoom: 2, base: 3), 6, accuracy: 0.001)
        XCTAssertEqual(InkSharpness.contentScale(zoom: 2, base: 2), 4, accuracy: 0.001)
    }

    /// The zoom ceiling is 12. Drawing the ink twelve times finer than a
    /// retina screen is memory spent past what any display can show.
    func testItIsBoundedSoDeepZoomCannotExhaustMemory() {
        let deep = InkSharpness.contentScale(zoom: 12, base: 3)
        XCTAssertEqual(deep, 3 * InkSharpness.maximumFactor, accuracy: 0.001)
        XCTAssertLessThanOrEqual(deep, 3 * InkSharpness.maximumFactor)
    }

    /// Zooming OUT must not make the ink coarser than the screen: the strokes
    /// are still drawn at full size when the gesture ends.
    func testZoomingOutNeverDegradesTheInk() {
        XCTAssertEqual(InkSharpness.contentScale(zoom: 0.5, base: 2), 2, accuracy: 0.001)
        XCTAssertEqual(InkSharpness.contentScale(zoom: 0.01, base: 2), 2, accuracy: 0.001)
    }

    /// Assigning the scale re-renders every stroke, and the zoom settles on
    /// quarter steps, so a canvas already at the right scale is left alone.
    func testAnUnchangedZoomDoesNotRepaintTheCanvas() {
        XCTAssertFalse(InkSharpness.isWorthRedrawing(from: 6, to: 6))
        XCTAssertFalse(InkSharpness.isWorthRedrawing(from: 6, to: 6.005))
        XCTAssertTrue(InkSharpness.isWorthRedrawing(from: 4, to: 4.5))
    }

    func testADegenerateScreenScaleIsNotDividedBy() {
        XCTAssertEqual(InkSharpness.contentScale(zoom: 4, base: 0), 1, accuracy: 0.001)
    }
}
