import XCTest

/// The activity LED's question: is this staff making a noise right now.
///
/// Asked of every strip, twenty times a second, while the transport runs -- so
/// the answer has to be cheap and it has to be right at a boundary, because a
/// lamp that flickers on every rest edge is worse than no lamp.
final class PlaybackActivityTests: XCTestCase {

    private func part(_ sounding: [[Double]]) -> PlaybackTimeline.Part {
        .init(index: 0, name: "Viola", instrument: "Viola", program: 41,
              sounding: sounding)
    }

    func testAStaffIsSoundingInsideItsInterval() {
        let viola = part([[0, 4], [8, 12]])
        XCTAssertTrue(viola.isSounding(at: 0))
        XCTAssertTrue(viola.isSounding(at: 2))
        XCTAssertTrue(viola.isSounding(at: 8))
        XCTAssertTrue(viola.isSounding(at: 11.99))
    }

    /// The rest between them is where the lamp goes dark. That gap is the
    /// whole reason the intervals are merged rather than per-note: inside a
    /// run of notes there is no gap to find.
    func testItIsDarkInTheRests() {
        let viola = part([[0, 4], [8, 12]])
        XCTAssertFalse(viola.isSounding(at: 5))
        XCTAssertFalse(viola.isSounding(at: 7.99))
        XCTAssertFalse(viola.isSounding(at: 12))
        XCTAssertFalse(viola.isSounding(at: 99))
    }

    /// Half-open, the same rule the bar map follows: a note ending exactly
    /// where the next begins is continuous, and an interval's end belongs to
    /// the silence after it.
    func testTheEndOfAnIntervalBelongsToTheSilence() {
        let viola = part([[0, 4]])
        XCTAssertTrue(viola.isSounding(at: 3.999))
        XCTAssertFalse(viola.isSounding(at: 4))
    }

    /// A staff that rests through the whole piece never lights. Nil-ish data
    /// must not read as "always on" -- a row of lamps stuck on says nothing.
    func testATacetStaffNeverLights() {
        let silent = part([])
        XCTAssertFalse(silent.isSounding(at: 0))
        XCTAssertFalse(silent.isSounding(at: 50))
    }

    /// Before the music starts, nothing is sounding -- including at a negative
    /// beat, which is where a seek can briefly put the play head.
    func testBeforeTheMusicNothingSounds() {
        let viola = part([[4, 8]])
        XCTAssertFalse(viola.isSounding(at: 0))
        XCTAssertFalse(viola.isSounding(at: -1))
    }

    /// Cheap at any length: the lookup is a binary search, so a part with
    /// hundreds of intervals costs the same as one with two. Asserted by
    /// behaviour rather than by timing -- a correct answer deep inside a long
    /// list is what a linear scan would also give, but this pins the contract.
    func testItFindsTheRightIntervalInALongPart() {
        let many = (0..<400).map { [Double($0) * 4, Double($0) * 4 + 2] }
        let busy = part(many)
        XCTAssertTrue(busy.isSounding(at: 1200))       // start of interval 300
        XCTAssertTrue(busy.isSounding(at: 1201.9))
        XCTAssertFalse(busy.isSounding(at: 1202))      // its rest
        XCTAssertTrue(busy.isSounding(at: 1596))       // the last one
        XCTAssertFalse(busy.isSounding(at: 1600))
    }

    /// The decode, against the shape the engine really emits.
    func testItDecodesTheEnginesOwnShape() throws {
        let json = """
        {"parts":[{"index":0,"name":"Voice","instrument":null,"program":null,
                   "sounding":[[24.0,69.0],[72.0,115.0]]}],
         "bars":[],"clicks":[],"tempos":[]}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let timeline = try decoder.decode(PlaybackTimeline.self,
                                          from: Data(json.utf8))
        XCTAssertEqual(timeline.parts[0].sounding.count, 2)
        XCTAssertTrue(timeline.parts[0].isSounding(at: 50))
        XCTAssertFalse(timeline.parts[0].isSounding(at: 70))
    }

    /// A timeline from before this field existed still decodes: the engine and
    /// the app ship separately on iPad, and a missing key must not take the
    /// whole performance down with it.
    func testATimelineWithoutTheFieldStillDecodes() throws {
        let json = """
        {"parts":[{"index":0,"name":"Voice","instrument":null,"program":null}],
         "bars":[],"clicks":[],"tempos":[]}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let timeline = try decoder.decode(PlaybackTimeline.self, from: Data(json.utf8))
        XCTAssertEqual(timeline.parts[0].sounding, [])
        XCTAssertFalse(timeline.parts[0].isSounding(at: 1))
    }
}
