import AVFoundation
import XCTest

/// `PlaybackGraph` wires `sequencer.tracks` to one sampler per part. It was
/// built on the belief that `AVAudioSequencer.tracks` omits music21's leading
/// conductor track, so `tracks[i]` was part `i`. Measured on the MIDI the
/// engine wrote for the score in Ali's video (2026-09-10), that is false: a
/// three-part score comes back as FOUR tracks, the first of them the conductor
/// with no notes in it. Every part was therefore wired to the sampler one
/// place too low -- the piano's left hand sounded with the voice's instrument,
/// the voice's own track had no sampler at all and fell back to the engine's
/// default piano, and muting "Voice" muted the piano's left hand. "Voice was
/// mapped to grand piano", "the registration made no sense" and "I mute voices
/// and still hear them" were one off-by-one.
///
/// So the mapping is now an OFFSET the graph measures at load, and both the
/// measurement and the rule are pinned here.
final class SequencerTrackMappingTests: XCTestCase {

    private func fixture() throws -> URL {
        guard let url = Bundle(for: Self.self).url(forResource: "imate-li-vino",
                                                   withExtension: "mid",
                                                   subdirectory: "Fixtures") else {
            throw XCTSkip("imate-li-vino.mid is not in the test bundle")
        }
        return url
    }

    private func noteEvents(in track: AVMusicTrack) -> Int {
        var count = 0
        track.enumerateEvents(in: AVBeatRange(start: 0, length: max(track.lengthInBeats, 1))) {
            event, _, _ in
            if event is AVMIDINoteEvent { count += 1 }
        }
        return count
    }

    // MARK: - the measurement

    func testThreePartsArriveAsFourTracksWithTheConductorFirst() throws {
        let sequencer = AVAudioSequencer(audioEngine: AVAudioEngine())
        try sequencer.load(from: try fixture(), options: [])
        XCTAssertEqual(sequencer.tracks.count, 4,
                       "the assumption that the conductor track is omitted is what broke the mixer")
        XCTAssertEqual(noteEvents(in: sequencer.tracks[0]), 0,
                       "the first track is the conductor: it carries no notes")
        for index in 1..<sequencer.tracks.count {
            XCTAssertGreaterThan(noteEvents(in: sequencer.tracks[index]), 0,
                                 "track \(index) should be a part with notes in it")
        }
    }

    // MARK: - the rule

    func testTheOffsetIsTheExtraTrackAndNothingElse() {
        XCTAssertEqual(PlaybackGraph.trackOffset(trackCount: 4, partCount: 3), 1)
        XCTAssertEqual(PlaybackGraph.trackOffset(trackCount: 3, partCount: 3), 0,
                       "a file whose conductor track IS omitted still maps straight")
    }

    func testAnUnexplainedTrackCountIsRefusedRatherThanGuessedAt() {
        // Two extra tracks, or fewer tracks than parts: nothing here knows
        // which is which, and wiring them anyway is how the wrong instrument
        // lands on the wrong staff. Nil, so the caller can say so.
        XCTAssertNil(PlaybackGraph.trackOffset(trackCount: 5, partCount: 3))
        XCTAssertNil(PlaybackGraph.trackOffset(trackCount: 2, partCount: 3))
    }

    func testTheRealFileMapsEveryPartToItsOwnTrack() throws {
        let sequencer = AVAudioSequencer(audioEngine: AVAudioEngine())
        try sequencer.load(from: try fixture(), options: [])
        guard let offset = PlaybackGraph.trackOffset(trackCount: sequencer.tracks.count,
                                                     partCount: 3) else {
            return XCTFail("the real file's track count should be explainable")
        }
        // Part i is tracks[i + offset], and every one of those has notes.
        for part in 0..<3 {
            XCTAssertGreaterThan(noteEvents(in: sequencer.tracks[part + offset]), 0,
                                 "part \(part) maps to a track with no notes")
        }
    }
}
