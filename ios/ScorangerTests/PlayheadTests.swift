import AVFoundation
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

    // MARK: - A size on screen, at any zoom (0.6.6: thinner, still view-space)

    /// The line was thinned from 2pt to 1pt because the owner marked it
    /// "thin". The number is asserted here rather than only looked at, so
    /// thinning it never quietly becomes thickening it back.
    func testTheLineIsAHairline() {
        XCTAssertEqual(Playhead.weight, 1, accuracy: 0.0001,
                       "the cursor is the app's hairline weight")
    }

    /// And thinning it did NOT make it a size in page coordinates. This is the
    /// rule the two screenshots at 1x and 3x photograph: what is written
    /// `weight / zoom` inside the transform lands `weight` wide on screen,
    /// whatever the transform is.
    func testTheLineKeepsItsWeightAtEveryZoom() {
        for zoom in [1, 1.5, 2, 3, 6, 12] as [CGFloat] {
            let drawn = Playhead.onScreen(Playhead.weight, zoom: zoom)
            XCTAssertEqual(drawn * zoom, Playhead.weight, accuracy: 0.0001,
                           "at \(zoom)x the line lands \(drawn * zoom)pt wide "
                           + "on screen instead of \(Playhead.weight)")
        }
    }

    /// The handle did not thin with the line: it is a touch target now.
    func testTheHandleIsBiggerThanTheLineAndSoIsItsTarget() {
        XCTAssertGreaterThan(Playhead.handle, Playhead.weight)
        XCTAssertGreaterThan(Playhead.handleTouchTarget, Playhead.handle,
                             "a 10pt square is not something a finger can hit")
    }

    /// A zoom that is not a number yet draws at full size rather than as a
    /// slab -- the same guard the selection ink carries, and the same one,
    /// because this delegates to it.
    func testAnUnreportedZoomDrawsTheLineAtFullSize() {
        for nonsense in [0, -3, CGFloat.nan, CGFloat.infinity] as [CGFloat] {
            XCTAssertEqual(Playhead.onScreen(Playhead.weight, zoom: nonsense),
                           Playhead.weight, accuracy: 0.0001,
                           "zoom \(nonsense) drew a slab")
        }
    }

    // MARK: - Grabbing the handle

    /// The target is a square around the handle's centre, in whatever space
    /// the caller is working in.
    func testTheHandleIsGrabbedInsideItsTargetAndNotOutside() {
        let handle = CGPoint(x: 200, y: 50)
        let target = Playhead.handleTouchTarget      // 32 -> 16 either side
        XCTAssertTrue(Playhead.handleGrabbed(touch: handle, handle: handle,
                                             target: target))
        XCTAssertTrue(Playhead.handleGrabbed(touch: CGPoint(x: 215, y: 61),
                                             handle: handle, target: target),
                      "a corner of the target is still the handle")
        XCTAssertFalse(Playhead.handleGrabbed(touch: CGPoint(x: 200, y: 90),
                                              handle: handle, target: target),
                       "a touch on the LINE below the handle is not a grab: "
                       + "that is where the lasso works")
        XCTAssertFalse(Playhead.handleGrabbed(touch: CGPoint(x: 240, y: 50),
                                              handle: handle, target: target))
    }

    /// A target of nothing catches nothing. The layer passes the target
    /// divided by the zoom, and a zoom that has gone wrong must not turn the
    /// whole page into a scrub handle.
    func testNoTargetGrabsNothing() {
        XCTAssertFalse(Playhead.handleGrabbed(touch: .zero, handle: .zero, target: 0))
        XCTAssertFalse(Playhead.handleGrabbed(touch: .zero, handle: .zero, target: -5))
    }

    // MARK: - What a drag lands on

    /// A page of two systems, four bars each, laid out the way an engraving
    /// is: bars 1-4 across the top, 5-8 across the bottom, at the SAME x
    /// positions.
    private let twoSystems: [BarPosition.Bar] = {
        var bars: [BarPosition.Bar] = []
        for (offset, number) in [1, 2, 3, 4].enumerated() {
            bars.append(.init(number: number,
                              frame: CGRect(x: CGFloat(offset) * 100, y: 0,
                                            width: 100, height: 60)))
        }
        for (offset, number) in [5, 6, 7, 8].enumerated() {
            bars.append(.init(number: number,
                              frame: CGRect(x: CGFloat(offset) * 100, y: 200,
                                            width: 100, height: 60)))
        }
        return bars
    }()

    func testADragLandsOnTheBarUnderIt() {
        XCTAssertEqual(Playhead.bar(at: CGPoint(x: 250, y: 30), bars: twoSystems), 3)
        XCTAssertEqual(Playhead.bar(at: CGPoint(x: 50, y: 30), bars: twoSystems), 1)
    }

    /// The failure this rule exists to prevent: two systems share every x, so
    /// x alone cannot say which bar is meant. The same x on the lower system
    /// is a bar four later.
    func testTheSystemIsChosenByYBeforeTheBarIsChosenByX() {
        XCTAssertEqual(Playhead.bar(at: CGPoint(x: 250, y: 30), bars: twoSystems), 3)
        XCTAssertEqual(Playhead.bar(at: CGPoint(x: 250, y: 230), bars: twoSystems), 7,
                       "the same x on the lower system is a different bar")
    }

    /// Dragged into the gap between two systems, or off the end of a line: the
    /// nearest bar, never nothing. A scrub that stops answering at the edge of
    /// the music reads as a gesture that has broken.
    func testADragOffTheMusicTakesTheNearestBar() {
        XCTAssertEqual(Playhead.bar(at: CGPoint(x: 250, y: 70), bars: twoSystems), 3,
                       "just below the top system is still the top system")
        XCTAssertEqual(Playhead.bar(at: CGPoint(x: 250, y: 190), bars: twoSystems), 7,
                       "just above the lower system is the lower system")
        XCTAssertEqual(Playhead.bar(at: CGPoint(x: 900, y: 30), bars: twoSystems), 4,
                       "dragged past the end of the line: the last bar of it")
        XCTAssertEqual(Playhead.bar(at: CGPoint(x: -200, y: 230), bars: twoSystems), 5)
    }

    /// A quartet gives four frames for one bar, and the drag reads their
    /// union: a finger over the cello staff must select the bar, not fail to
    /// find it because it was looking at the violin's frame.
    func testAQuartetsFourStavesAreOneBarToADrag() {
        XCTAssertEqual(Playhead.bar(at: CGPoint(x: 140, y: 200), bars: quartetBar2), 2,
                       "the lowest staff of bar 2 is still bar 2")
        XCTAssertEqual(Playhead.bar(at: CGPoint(x: 140, y: 10), bars: quartetBar2), 2)
    }

    func testADragOverNoGeometryLandsNowhere() {
        XCTAssertNil(Playhead.bar(at: CGPoint(x: 10, y: 10), bars: []))
    }

    /// The claim the whole silent-playback rule rests on: **the CURSOR moves
    /// when nothing can be heard.**
    ///
    /// `PlaybackAudioTests.testAMutedChannelDoesNotStopTheClock` proves the
    /// SEQUENCER advances through silence. That is a different claim: a
    /// sequencer can run while the thing the reader is actually looking at
    /// stands still. This drives the real graph, in true silence, and asks
    /// where the cursor would be drawn at two different moments.
    ///
    /// "All voices off and the metronome off gives you silence, and that is
    /// allowed" is only allowed because of this.
    func testTheCursorMovesThroughTotalSilence() throws {
        guard let midi = Bundle(for: Self.self).url(forResource: "quartet-playback",
                                                    withExtension: "mid",
                                                    subdirectory: "Fixtures") else {
            throw XCTSkip("the quartet fixture is not in the test bundle")
        }
        let parts = (0..<4).map {
            PlaybackTimeline.Part(index: $0, name: "Voice", instrument: nil, program: nil)
        }
        let timeline = PlaybackTimeline(
            parts: parts,
            bars: (0..<4).map { .init(measure: $0 + 1, start: Double($0) * 4,
                                      end: Double($0) * 4 + 4) },
            clicks: [], tempos: [.init(beat: 0, bpm: 120)])
        // The page the cursor is drawn on: four bars laid side by side.
        let engraved = (0..<4).map {
            BarPosition.Bar(number: $0 + 1,
                            frame: CGRect(x: CGFloat($0) * 100, y: 0,
                                          width: 100, height: 200))
        }

        let graph = PlaybackGraph()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        try graph.engine.enableManualRenderingMode(.offline, format: format,
                                                   maximumFrameCount: 4096)
        try graph.load(midi: midi, timeline: timeline)
        var silenced = PlaybackVoices()
        silenced.setAll(on: false, parts: parts)
        graph.apply(silenced, parts: parts, metronome: false)   // nothing sounds

        try graph.engine.start()
        graph.sequencer?.prepareToPlay()
        try graph.sequencer?.start()

        func cursorNow() throws -> Playhead.Position? {
            let beat = graph.sequencer?.currentPositionInBeats ?? 0
            guard let progress = timeline.progress(atBeat: beat) else { return nil }
            return Playhead.position(measure: progress.measure,
                                     fraction: CGFloat(progress.fraction),
                                     bars: engraved)
        }

        let buffer = AVAudioPCMBuffer(pcmFormat: graph.engine.manualRenderingFormat,
                                      frameCapacity: 4096)!
        func renderASecond() throws -> Double {
            let target = graph.engine.manualRenderingSampleTime + 44100
            var peak = 0.0
            while graph.engine.manualRenderingSampleTime < target {
                let remaining = target - graph.engine.manualRenderingSampleTime
                let frames = AVAudioFrameCount(min(AVAudioFramePosition(4096), remaining))
                guard try graph.engine.renderOffline(frames, to: buffer) == .success,
                      let channels = buffer.floatChannelData else { break }
                for channel in 0..<Int(buffer.format.channelCount) {
                    for frame in 0..<Int(buffer.frameLength) {
                        peak = max(peak, abs(Double(channels[channel][frame])))
                    }
                }
            }
            return peak
        }

        let firstPeak = try renderASecond()
        let first = try cursorNow()
        let secondPeak = try renderASecond()
        let second = try cursorNow()

        XCTAssertLessThan(max(firstPeak, secondPeak), 1e-5,
                          "this test is worthless unless it is really silent")
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertGreaterThan(second!.x, first!.x,
                             "the cursor stood still while the music played on")
    }
}

// MARK: - The continuous strip (bug 6)

/// The DAW rule: the line stands still and the score scrolls past it.
final class ContinuousPlayheadTests: XCTestCase {
    private let surface: CGFloat = 20000
    private let viewport: CGFloat = 1000

    /// In the body of the piece the offset tracks the line exactly, so the line
    /// does not move on screen at all: that is the whole feature.
    func testTheLineStandsStillWhileTheScoreScrolls() {
        var onScreen: [CGFloat] = []
        for x in stride(from: CGFloat(2000), through: 8000, by: 250) {
            let offset = Playhead.stripOffset(playheadX: x, viewportWidth: viewport,
                                              surfaceWidth: surface)
            onScreen.append(x - offset)
        }
        for position in onScreen {
            XCTAssertEqual(position, viewport * Playhead.parkFraction, accuracy: 0.001,
                           "the line moved on screen instead of the score moving")
        }
    }

    /// Before the park point there is nothing to scroll to, so the score holds
    /// still and the line travels in from the first bar.
    func testAtTheStartTheScoreHoldsStillAndTheLineTravels() {
        // The park point is a quarter of the viewport in: 250 of 1000.
        for x in [CGFloat(0), 100, 200, 249] {
            XCTAssertEqual(Playhead.stripOffset(playheadX: x, viewportWidth: viewport,
                                                surfaceWidth: surface), 0,
                           "the score should not move before the line reaches the park point")
        }
        XCTAssertEqual(viewport * Playhead.parkFraction, 250, "the park point is a quarter in")
        XCTAssertGreaterThan(
            Playhead.stripOffset(playheadX: 500, viewportWidth: viewport,
                                 surfaceWidth: surface), 0)
    }

    /// And at the end it stops at the last screenful rather than scrolling the
    /// music off the left edge.
    func testAtTheEndTheScoreStopsAndTheLineTravelsOn() {
        let offset = Playhead.stripOffset(playheadX: surface - 10,
                                          viewportWidth: viewport, surfaceWidth: surface)
        XCTAssertEqual(offset, surface - viewport)
    }

    /// A score shorter than the viewport cannot scroll at all.
    func testAShortScoreNeverScrolls() {
        XCTAssertEqual(Playhead.stripOffset(playheadX: 400, viewportWidth: viewport,
                                            surfaceWidth: 600), 0)
    }

    func testAnEmptyViewportIsNotADivision() {
        XCTAssertEqual(Playhead.stripOffset(playheadX: 400, viewportWidth: 0,
                                            surfaceWidth: 600), 0)
    }

    // MARK: the note under the line

    private func note(_ staff: Int, _ x: CGFloat) -> (staff: Int, frame: CGRect) {
        (staff, CGRect(x: x, y: CGFloat(staff) * 100, width: 10, height: 10))
    }

    /// One note per staff, so a quartet lights four noteheads at once rather
    /// than saying three parts are silent.
    func testEveryStaffSoundingUnderTheLineIsLit() {
        let bar = [note(1, 10), note(1, 60), note(2, 10), note(2, 60),
                   note(3, 10), note(4, 10)]
        let lit = Playhead.sounding(notes: bar, x: 65)
        XCTAssertEqual(lit.count, 4, "one note on each of the four staves")
        XCTAssertEqual(lit.map(\.minX), [60, 60, 10, 10])
    }

    /// A note stays lit until the line reaches the next one, which is what
    /// "for the note's duration" means with no onset map to ask.
    func testANoteStaysLitUntilTheLineReachesTheNext() {
        let bar = [note(1, 10), note(1, 60)]
        for x in stride(from: CGFloat(10), to: 60, by: 5) {
            XCTAssertEqual(Playhead.sounding(notes: bar, x: x).first?.minX, 10)
        }
        XCTAssertEqual(Playhead.sounding(notes: bar, x: 60).first?.minX, 60)
    }

    /// Before the first note of the bar nothing is lit -- better than lighting
    /// a note that has not sounded.
    func testNothingIsLitBeforeTheFirstNote() {
        XCTAssertTrue(Playhead.sounding(notes: [note(1, 40)], x: 10).isEmpty)
    }
}
