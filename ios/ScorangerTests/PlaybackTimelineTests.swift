import XCTest

/// The map from a play head to the page.
///
/// Every fixture here is shaped like something the engine really emits, and the
/// numbers come from `engine/scripts/check_playback.py` rather than from
/// invention -- the two files describe the same map from either side of the
/// boundary.
final class PlaybackTimelineTests: XCTestCase {

    /// Four bars of 4/4 whose first two repeat, which is what the engine
    /// returns for that score: six spans, bar 1 twice.
    private var repeated: PlaybackTimeline {
        PlaybackTimeline(
            parts: [.init(index: 0, name: "Violin I", instrument: "Violin", program: 40),
                    .init(index: 1, name: "Viola", instrument: "Viola", program: 41)],
            bars: [.init(measure: 1, start: 0, end: 4),
                   .init(measure: 2, start: 4, end: 8),
                   .init(measure: 1, start: 8, end: 12),
                   .init(measure: 2, start: 12, end: 16),
                   .init(measure: 3, start: 16, end: 20),
                   .init(measure: 4, start: 20, end: 24)],
            clicks: [], tempos: [.init(beat: 0, bpm: 120)], beats: 24)
    }

    // MARK: - Where the play head is

    func testTheBarUnderThePlayHead() {
        XCTAssertEqual(repeated.bar(atBeat: 0), 1)
        XCTAssertEqual(repeated.bar(atBeat: 2.5), 1)
        XCTAssertEqual(repeated.bar(atBeat: 5), 2)
        XCTAssertEqual(repeated.bar(atBeat: 23.9), 4)
    }

    /// A repeat is the reason this is a list of spans. Beat 9 is bar 1 for the
    /// second time -- a map from bar to beat could not say so.
    func testARepeatedBarIsFoundOnBothPassesThroughIt() {
        XCTAssertEqual(repeated.bar(atBeat: 1), 1)
        XCTAssertEqual(repeated.bar(atBeat: 9), 1, "bar 1 sounds again after the repeat")
        XCTAssertEqual(repeated.span(atBeat: 1), 0)
        XCTAssertEqual(repeated.span(atBeat: 9), 2,
                       "the same bar, but a different stretch of the performance")
    }

    /// The rule BarPosition already follows for a viewport resting on a
    /// barline: the line belongs to the bar it opens.
    func testABeatExactlyOnABarlineBelongsToTheBarItOpens() {
        XCTAssertEqual(repeated.bar(atBeat: 4), 2)
        XCTAssertEqual(repeated.span(atBeat: 8), 2)
    }

    func testOutsideThePerformanceThereIsNoBar() {
        XCTAssertNil(repeated.bar(atBeat: -1))
        XCTAssertNil(repeated.bar(atBeat: 24), "the end is past the last bar")
        XCTAssertNil(repeated.bar(atBeat: 99))
        XCTAssertNil(PlaybackTimeline.empty.bar(atBeat: 0))
    }

    /// Tapping bar 2 means "start there", so it seeks to the first time bar 2
    /// is played. Landing inside the repeat would skip the music before it.
    func testSeekingToABarFindsTheFirstTimeItIsPlayed() {
        XCTAssertEqual(repeated.firstBeat(ofBar: 1), 0)
        XCTAssertEqual(repeated.firstBeat(ofBar: 2), 4)
        XCTAssertEqual(repeated.firstBeat(ofBar: 3), 16)
        XCTAssertNil(repeated.firstBeat(ofBar: 99))
    }

    // MARK: - Clicks

    func testTheClickWindowIsHalfOpen() {
        let timeline = PlaybackTimeline(
            parts: [], bars: [.init(measure: 1, start: 0, end: 4)],
            clicks: [.init(beat: 0, down: true), .init(beat: 1, down: false),
                     .init(beat: 2, down: false), .init(beat: 3, down: false),
                     .init(beat: 4, down: true)],
            tempos: [], beats: 8)
        // Half-open, so scheduling window after window cannot sound one twice.
        XCTAssertEqual(timeline.clicks(from: 0, to: 4).map(\.beat), [0, 1, 2, 3])
        XCTAssertEqual(timeline.clicks(from: 4, to: 8).map(\.beat), [4])
    }

    // MARK: - What the transport reads off it

    func testATempoNobodyChoseIsMarkedAsSuch() {
        let defaulted = PlaybackTimeline(parts: [], bars: [], clicks: [],
                                         tempos: [.init(beat: 0, bpm: 120)],
                                         tempoFromScore: false)
        XCTAssertEqual(defaulted.openingTempo, 120)
        XCTAssertFalse(defaulted.tempoFromScore,
                       "120 the writer chose is not 120 the arranger chose")
    }

    func testAnEmptyTimelineStillAnswersATempo() {
        XCTAssertEqual(PlaybackTimeline.empty.openingTempo, 120)
        XCTAssertTrue(PlaybackTimeline.empty.isEmpty)
    }

    // MARK: - Decoding what the engine sends

    /// The engine speaks snake_case; the app decodes with
    /// `convertFromSnakeCase`, exactly as `LocalEngine` already does.
    func testItDecodesTheEnginesOwnShape() throws {
        let json = """
        {"parts": [{"index": 0, "name": "Clarinet in Bb",
                    "instrument": "Clarinet", "program": 71},
                   {"index": 1, "name": "Voice", "instrument": null, "program": null}],
         "bars": [{"measure": 0, "start": 0.0, "end": 1.0, "meter": "4/4", "pickup": true},
                  {"measure": 1, "start": 1.0, "end": 5.0, "meter": "4/4", "pickup": false}],
         "clicks": [{"beat": 0.0, "down": false}, {"beat": 1.0, "down": true}],
         "tempos": [{"beat": 0.0, "bpm": 72.0}],
         "tempo_from_score": true, "beats": 5.0,
         "repeats_expanded": true, "sounding_pitch": true,
         "written_bars": 2, "performed_bars": 2}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let timeline = try decoder.decode(PlaybackTimeline.self,
                                          from: Data(json.utf8))
        XCTAssertEqual(timeline.parts.count, 2)
        XCTAssertEqual(timeline.parts[0].program, 71)
        XCTAssertNil(timeline.parts[1].program,
                     "a part with no instrument keeps its null rather than a guess")
        XCTAssertTrue(timeline.bars[0].pickup)
        XCTAssertTrue(timeline.tempoFromScore)
        XCTAssertTrue(timeline.soundingPitch)
        XCTAssertEqual(timeline.beats, 5)
        // A pickup's click is not a downbeat, or the player's foot lands in
        // the wrong place for the whole first phrase.
        XCTAssertFalse(timeline.clicks[0].down)
        XCTAssertTrue(timeline.clicks[1].down)
        // and the bar map still works over a pickup, where bar 1 does not
        // start at beat 0
        XCTAssertEqual(timeline.bar(atBeat: 0.5), 0)
        XCTAssertEqual(timeline.bar(atBeat: 1.0), 1)
    }
}
