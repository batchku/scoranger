import CoreGraphics
import XCTest

/// The cursor's geometry: (measure, beat) in, a place on the page out.
final class PlayheadTests: XCTestCase {

    /// A quartet's bar 2: four staves, four frames, one measure.
    private let quartetBar2: [BarPosition.Bar] = [
        .init(number: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 40)),
        .init(number: 2, frame: CGRect(x: 100, y: 0, width: 80, height: 40)),
        .init(number: 2, frame: CGRect(x: 100, y: 60, width: 80, height: 40)),
        .init(number: 2, frame: CGRect(x: 100, y: 120, width: 80, height: 40)),
        .init(number: 2, frame: CGRect(x: 100, y: 180, width: 80, height: 40)),
        .init(number: 3, frame: CGRect(x: 180, y: 0, width: 90, height: 40)),
    ]

    /// The line spans the SYSTEM, not one staff: the union of every frame
    /// carrying that measure number, top of the first staff to bottom of the
    /// last.
    func testTheLineSpansEveryStaffOfTheSystem() {
        let position = Playhead.position(measure: 2, fraction: 0,
                                         bars: quartetBar2)
        XCTAssertEqual(position?.top, 0)
        XCTAssertEqual(position?.bottom, 220)
        XCTAssertEqual(position?.height, 220)
    }

    /// x is interpolated across the bar by how far through it the beat is.
    func testTheBeatPlacesTheLineAcrossTheBar() {
        XCTAssertEqual(Playhead.position(measure: 2, fraction: 0,
                                         bars: quartetBar2)?.x, 100)
        XCTAssertEqual(Playhead.position(measure: 2, fraction: 0.5,
                                         bars: quartetBar2)?.x, 140)
        XCTAssertEqual(Playhead.position(measure: 2, fraction: 1,
                                         bars: quartetBar2)?.x, 180)
    }

    /// A fraction outside the bar is clamped rather than allowed to draw the
    /// cursor into the next system.
    func testAFractionOffTheEndIsClamped() {
        XCTAssertEqual(Playhead.position(measure: 2, fraction: 4,
                                         bars: quartetBar2)?.x, 180)
        XCTAssertEqual(Playhead.position(measure: 2, fraction: -1,
                                         bars: quartetBar2)?.x, 100)
    }

    /// The failure mode is ABSENT, not wrong. A measure that is not engraved on
    /// this page -- or a render that built no geometry at all, which is every
    /// remote-engine page -- gets no cursor, and the reader is not shown a
    /// position the app invented.
    func testAMeasureNotOnThisPageHasNoCursor() {
        XCTAssertNil(Playhead.position(measure: 99, fraction: 0, bars: quartetBar2))
        XCTAssertNil(Playhead.position(measure: 1, fraction: 0, bars: []))
    }

    /// The repeat case, which is the whole reason this is driven by measure and
    /// not by elapsed time. Bar 2 sounds at beat 4 and again at beat 12, and
    /// BOTH resolve to bar 2's frame -- so the cursor jumps back, which is what
    /// a reader watching a repeat expects.
    func testARepeatedBarPutsTheCursorInTheSamePlaceBothTimes() {
        let timeline = PlaybackTimeline(
            parts: [],
            bars: [.init(measure: 1, start: 0, end: 4),
                   .init(measure: 2, start: 4, end: 8),
                   .init(measure: 1, start: 8, end: 12),
                   .init(measure: 2, start: 12, end: 16)],
            clicks: [], tempos: [])

        let firstPass = timeline.progress(atBeat: 6)
        let secondPass = timeline.progress(atBeat: 14)
        XCTAssertEqual(firstPass?.measure, 2)
        XCTAssertEqual(secondPass?.measure, 2)
        XCTAssertEqual(firstPass?.fraction ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(secondPass?.fraction ?? -1, 0.5, accuracy: 1e-9)

        let first = Playhead.position(measure: firstPass!.measure,
                                      fraction: CGFloat(firstPass!.fraction),
                                      bars: quartetBar2)
        let second = Playhead.position(measure: secondPass!.measure,
                                       fraction: CGFloat(secondPass!.fraction),
                                       bars: quartetBar2)
        XCTAssertEqual(first, second, "the same bar is the same place on the page")
    }

    /// Which page holds the music, for page-follow and for the Sync chip.
    func testFindingThePageAMeasureIsEngravedOn() {
        let pages: [(index: Int, bars: [BarPosition.Bar])] = [
            (0, [.init(number: 1, frame: .zero), .init(number: 2, frame: .zero)]),
            (1, [.init(number: 3, frame: .zero), .init(number: 4, frame: .zero)]),
        ]
        XCTAssertEqual(Playhead.page(ofMeasure: 4, pages: pages), 1)
        XCTAssertEqual(Playhead.page(ofMeasure: 1, pages: pages), 0)
        XCTAssertNil(Playhead.page(ofMeasure: 9, pages: pages))
    }

    /// The page turns BEFORE the music arrives, at 85% across.
    func testThePageTurnsAheadOfTheMusic() {
        XCTAssertFalse(Playhead.shouldTurnPage(x: 800, pageWidth: 1000))
        XCTAssertTrue(Playhead.shouldTurnPage(x: 850, pageWidth: 1000))
        XCTAssertTrue(Playhead.shouldTurnPage(x: 999, pageWidth: 1000))
        XCTAssertFalse(Playhead.shouldTurnPage(x: 100, pageWidth: 0),
                       "a page with no width cannot be turned past")
    }
}
