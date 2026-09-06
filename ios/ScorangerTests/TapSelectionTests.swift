import CoreGraphics
import XCTest

/// What a tap means, and where the loupe goes.
///
/// IPHONE_0.6.14 §9.1 and §9.2, the two decisions in step 3. Both are pure:
/// the rest of tap selection is wiring a gesture to `selectBar` and
/// `addToSelection`, which already exist.
final class TapSelectionTests: XCTestCase {

    // MARK: - §9.1 granularity follows the zoom

    /// The rule, and it is not arbitrary: it is the granularity that is both
    /// legible and hittable at that scale. At fit a notehead is 3.9pt against
    /// a 25pt fingertip; at 2x it is 7.8pt and a bar is still in view.
    func testBelowTwoATapMeansABar() {
        for zoom in [1.0, 1.4, 1.99] {
            XCTAssertEqual(TapSelection.granularity(atZoom: zoom), .measure,
                           "at \(zoom)x")
        }
    }

    func testAtTwoAndAboveATapMeansANote() {
        for zoom in [2.0, 4.0, 6.0, 12.0] {
            XCTAssertEqual(TapSelection.granularity(atZoom: zoom), .note,
                           "at \(zoom)x")
        }
    }

    /// The boundary is 2.0 itself, and it belongs to `note`. A reader who has
    /// zoomed to exactly 2x has asked for the finer one.
    func testTheBoundaryBelongsToTheFinerGranularity() {
        XCTAssertEqual(TapSelection.granularity(atZoom: 2.0), .note)
        XCTAssertEqual(TapSelection.granularity(atZoom: 1.9999), .measure)
    }

    /// Tapping an ALREADY-SELECTED bar drills in, at any zoom -- the way to a
    /// note without zooming (§9.1's first override).
    func testTappingASelectedBarDrillsIn() {
        XCTAssertEqual(TapSelection.granularity(atZoom: 1.0, onSelected: true),
                       .note)
        XCTAssertEqual(TapSelection.granularity(atZoom: 1.0, onSelected: false),
                       .measure)
        // and at note zoom it stays a note either way
        XCTAssertEqual(TapSelection.granularity(atZoom: 4.0, onSelected: true),
                       .note)
    }

    // MARK: - §9.2 the loupe

    private let loupe = TapSelection.loupeSize          // 96
    private let offset = TapSelection.loupeOffset       // 88

    /// Above the touch by default, which is where a finger is not.
    func testTheLoupeSitsAboveTheTouch() {
        let placed = TapSelection.loupe(at: CGPoint(x: 200, y: 500),
                                        in: CGSize(width: 393, height: 759),
                                        safeAreaTop: 59)
        XCTAssertEqual(placed.centre.y, 500 - offset, accuracy: 0.5)
        XCTAssertFalse(placed.flipped)
    }

    /// It flips BELOW within 100pt of the top safe area, or it would be drawn
    /// under the status bar and the top bar.
    func testTheLoupeFlipsBelowNearTheTop() {
        let placed = TapSelection.loupe(at: CGPoint(x: 200, y: 120),
                                        in: CGSize(width: 393, height: 759),
                                        safeAreaTop: 59)
        XCTAssertTrue(placed.flipped, "it should have flipped below the touch")
        XCTAssertEqual(placed.centre.y, 120 + offset, accuracy: 0.5)
    }

    /// And it stays on screen horizontally: at the edges it slides rather than
    /// hanging off, because half a loupe shows half the answer.
    func testTheLoupeStaysOnScreenSideways() {
        let width: CGFloat = 393
        for x in [0.0, 4.0, 200.0, 389.0, 393.0] {
            let placed = TapSelection.loupe(at: CGPoint(x: x, y: 500),
                                            in: CGSize(width: width, height: 759),
                                            safeAreaTop: 59)
            XCTAssertGreaterThanOrEqual(placed.centre.x - loupe / 2, -0.5,
                                        "off the left at x=\(x)")
            XCTAssertLessThanOrEqual(placed.centre.x + loupe / 2, width + 0.5,
                                     "off the right at x=\(x)")
        }
    }

    /// The crosshair marks the TOUCH, not the loupe's centre. Release commits
    /// what the crosshair is on, so the two must not be confused.
    func testTheCrosshairMarksTheTouchPoint() {
        let touch = CGPoint(x: 200, y: 500)
        let placed = TapSelection.loupe(at: touch,
                                        in: CGSize(width: 393, height: 759),
                                        safeAreaTop: 59)
        XCTAssertEqual(placed.hit, touch)
    }

    /// Suppressed where it would be wrong rather than merely unhelpful:
    /// VoiceOver selects by element and not by point, and two fingers down is
    /// a pinch, which is not a selection (§10.3).
    func testTheLoupeIsSuppressedWhereItWouldBeWrong() {
        XCTAssertFalse(TapSelection.showsLoupe(voiceOver: true, fingers: 1,
                                               pinching: false))
        XCTAssertFalse(TapSelection.showsLoupe(voiceOver: false, fingers: 2,
                                               pinching: false))
        XCTAssertTrue(TapSelection.showsLoupe(voiceOver: false, fingers: 1,
                                              pinching: false))
    }

    /// During a pinch it FREEZES rather than vanishing: it holds its last
    /// sample and dims. Stale music at a changing scale is worse than a
    /// visible pause, and it re-samples when the scale settles.
    func testTheLoupeFreezesDuringAPinchRatherThanDisappearing() {
        XCTAssertTrue(TapSelection.showsLoupe(voiceOver: false, fingers: 1,
                                              pinching: true))
        XCTAssertEqual(TapSelection.loupeOpacity(pinching: true), 0.7,
                       accuracy: 0.001)
        XCTAssertEqual(TapSelection.loupeOpacity(pinching: false), 1.0,
                       accuracy: 0.001)
    }

    /// It magnifies 2x the CURRENT scale, so it is always twice what the
    /// reader can already see rather than a fixed power.
    func testTheLoupeMagnifiesTwiceWhateverTheZoomIs() {
        XCTAssertEqual(TapSelection.loupeScale(zoom: 1), 2, accuracy: 0.001)
        XCTAssertEqual(TapSelection.loupeScale(zoom: 4), 8, accuracy: 0.001)
        XCTAssertEqual(TapSelection.loupeScale(zoom: 12), 24, accuracy: 0.001)
    }
}
