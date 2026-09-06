import CoreGraphics
import XCTest

/// How far OUT the scroll view may be zoomed.
///
/// Ali: in the scroll view he cannot zoom out far enough, and it "snaps back
/// when I zoom past a certain limit". Both are the same cause -- the canvas
/// took its floor from the paged layout, where 1.0 means "the page fits" and
/// below it there is only ground. In continuous the strip is fitted to HEIGHT
/// and runs off the screen sideways, so below 1 there is more MUSIC, and the
/// floor was stopping the reader at one system filling the canvas. What he
/// felt as a snap is UIScrollView rubber-banding back to `minimumZoomScale`.
final class ContinuousZoomOutTests: XCTestCase {

    /// The strip heights these numbers are about: a four-staff system fitted
    /// to a portrait iPad, and a single voice.
    private let fourStaves: CGFloat = 540
    private let singleVoice: CGFloat = 300

    /// MUCH further out than today, which was 1.0 -- one system filling the
    /// canvas and nothing beyond it.
    func testTheFloorIsFarBelowWhatItWas() {
        let now = ContinuousTiles.minimumZoom(fittedStripHeight: fourStaves)
        XCTAssertLessThan(now, PagedCanvas.minimumZoom,
                          "the scroll view still cannot zoom out past the "
                          + "paged floor")
        XCTAssertLessThan(now, 0.2,
                          "a four-staff strip only reaches \(now)x, which is "
                          + "not the \"much further out\" this is for")
        // Five times more music across the screen, at least.
        XCTAssertGreaterThanOrEqual(1 / now, 5,
                                    "\(1 / now)x more music is not much more")
    }

    /// It is derived from the strip, not fixed: a tall score has further to go
    /// before its systems stop being readable, so it goes further.
    func testATallerStripZoomsOutFurther() {
        let tall = ContinuousTiles.minimumZoom(fittedStripHeight: fourStaves)
        let short = ContinuousTiles.minimumZoom(fittedStripHeight: singleVoice)
        XCTAssertLessThan(tall, short,
                          "a four-staff system should zoom out further than a "
                          + "single voice, having further to go")
    }

    /// And it never goes uselessly tiny: whatever the strip, what is left on
    /// screen is at least `minimumStripHeight`.
    func testItNeverGoesUselesslyTiny() {
        for height in [120.0, 300.0, 540.0, 900.0] {
            let floor = ContinuousTiles.minimumZoom(fittedStripHeight: height)
            let drawn = height * floor
            XCTAssertGreaterThanOrEqual(
                drawn, ContinuousTiles.minimumStripHeight - 0.01,
                "a \(height)pt strip at its floor is \(drawn)pt tall")
            XCTAssertGreaterThanOrEqual(floor, ContinuousTiles.absoluteZoomFloor)
        }
    }

    /// A strip already shorter than the minimum keeps its own fit rather than
    /// being given a floor ABOVE it -- which would be a canvas that cannot
    /// show its own music at rest.
    func testAShortStripIsNotGivenAFloorAboveItsFit() {
        XCTAssertEqual(ContinuousTiles.minimumZoom(fittedStripHeight: 40), 1)
        XCTAssertEqual(ContinuousTiles.minimumZoom(fittedStripHeight: 60), 1)
    }

    /// Nothing to divide by answers 1 rather than crashing or returning zero,
    /// which would be a scroll view that cannot zoom at all.
    func testAnUnmeasuredStripAnswersOne() {
        XCTAssertEqual(ContinuousTiles.minimumZoom(fittedStripHeight: 0), 1)
        XCTAssertEqual(ContinuousTiles.minimumZoom(fittedStripHeight: -10), 1)
    }

    /// THE PAGED FLOOR IS UNTOUCHED. A page IS fitted to the viewport, so
    /// below 1 there really is only ground around it -- the reasoning that was
    /// wrongly applied to the strip is right where it came from.
    func testThePagedFloorIsUnchanged() {
        XCTAssertEqual(PagedCanvas.minimumZoom, 1.0)
        XCTAssertEqual(PagedCanvas.clamp(zoom: 0.4), 1.0,
                       "a paged canvas should still clamp to fit")
    }
}
