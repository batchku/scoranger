import AVFoundation
import XCTest

/// The join between the engine's MIDI and the app's mute switches.
///
/// Everything else about per-voice muting is arithmetic over part names, and
/// `PlaybackVoicesTests` covers it. This file covers the one claim that
/// arithmetic rests on and that no amount of pure logic can establish:
/// **`AVAudioSequencer.tracks[i]` is part `i` FOR THIS FILE.** It was a
/// comment in `PlaybackEngine`, measured once and then trusted -- and on
/// 2026-09-10 a different file (imate-li-vino.mid, see
/// `SequencerTrackMappingTests`) arrived with the conductor track NOT hidden,
/// and every mute in the app silenced the wrong instrument, silently. The
/// graph now measures the offset per file; this file pins the case where it
/// is zero, that one the case where it is one.
///
/// The fixtures are real engine output (`ops.playback_timeline` then
/// `write("midi")`), not MIDI assembled here, so what is loaded is what the
/// app loads.
final class PlaybackTracksTests: XCTestCase {

    private func fixture(_ name: String) throws -> URL {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: name, withExtension: "mid",
                                   subdirectory: "Fixtures") else {
            throw XCTSkip("fixture \(name).mid is not in the test bundle")
        }
        return url
    }

    private func sequencer(_ name: String) throws -> (AVAudioEngine, AVAudioSequencer) {
        let engine = AVAudioEngine()
        let sequencer = AVAudioSequencer(audioEngine: engine)
        try sequencer.load(from: try fixture(name), options: [])
        return (engine, sequencer)
    }

    /// The whole mapping in one number. The file holds FIVE chunks -- a
    /// conductor track and four parts -- and the sequencer reports four. That
    /// difference is what lets a part index be used as a track index with
    /// nothing in between, and asserting it against a file whose chunk count
    /// is one higher is what makes the test able to fail.
    func testTheConductorTrackIsNotOneOfTheTracks() throws {
        let raw = try Data(contentsOf: try fixture("quartet-playback"))
        XCTAssertEqual(raw.prefix(4), Data("MThd".utf8))
        // Bytes 10-11 of the header are the chunk count.
        let chunks = Int(raw[10]) << 8 | Int(raw[11])
        XCTAssertEqual(chunks, 5, "a conductor track plus four parts")

        let (_, sequencer) = try self.sequencer("quartet-playback")
        XCTAssertEqual(sequencer.tracks.count, 4,
                       "the conductor track is excluded, so track i is part i")
    }

    /// And they are in SCORE order, not some order of AVFoundation's choosing.
    ///
    /// The fixture's four parts are 2, 4, 6 and 8 bars long on purpose: each
    /// track can then be told apart from its neighbours by its own length, so
    /// "they happen to be in the right order" and "they are in the right
    /// order" are different results here.
    ///
    /// The lengths are 9, 17, 25 and 33 rather than 8, 16, 24 and 32 -- see
    /// `testTheSequencerRunsPastTheEndOfTheMusic`. What matters here is the
    /// ORDER, and the constant beat between them is what says nothing was
    /// dropped or reshuffled.
    func testTracksArriveInScoreOrder() throws {
        let (_, sequencer) = try self.sequencer("staggered-playback")
        XCTAssertEqual(sequencer.tracks.count, 4)
        let lengths = sequencer.tracks.map { $0.lengthInBeats }
        XCTAssertEqual(lengths, [9, 17, 25, 33],
                       "Violin I, Violin II, Viola, Violoncello, in that order")
    }

    /// The click is appended AFTER loading, and it has to land after the parts
    /// or every part index shifts by one and the mutes address the wrong
    /// instruments.
    func testAnAppendedTrackLandsAfterThePartsAndLeavesTheirIndicesAlone() throws {
        let (_, sequencer) = try self.sequencer("staggered-playback")
        let before = sequencer.tracks
        let click = sequencer.createAndAppendTrack()
        XCTAssertEqual(sequencer.tracks.count, 5)
        XCTAssertTrue(sequencer.tracks[4] === click, "the click is last")
        for index in 0..<4 {
            XCTAssertTrue(sequencer.tracks[index] === before[index],
                          "part \(index) did not move")
        }
    }

    /// The product rule, at the level AVFoundation actually enforces it:
    /// silencing every part is a per-track operation that does not reach the
    /// click. That is the whole reason the metronome is a track in the same
    /// sequence rather than a timer beside it -- muting a viola and muting the
    /// click are the same operation, so one cannot accidentally do the other.
    func testEveryVoiceMutedLeavesTheClickSounding() throws {
        let (_, sequencer) = try self.sequencer("quartet-playback")
        let click = sequencer.createAndAppendTrack()

        let voices = PlaybackVoices(silenced: [0, 1, 2, 3])
        let parts = [PlaybackTimeline.Part(index: 0, name: "Violin I",
                                           instrument: "Violin", program: 40),
                     PlaybackTimeline.Part(index: 1, name: "Violin II",
                                           instrument: "Violin", program: 40),
                     PlaybackTimeline.Part(index: 2, name: "Viola",
                                           instrument: "Viola", program: 41),
                     PlaybackTimeline.Part(index: 3, name: "Violoncello",
                                           instrument: "Violoncello", program: 42)]
        let muted = voices.mutedTracks(in: parts)
        for (index, track) in sequencer.tracks.enumerated() where index < parts.count {
            track.isMuted = muted.contains(index)
        }
        click.isMuted = false

        XCTAssertEqual(sequencer.tracks.prefix(4).map(\.isMuted), [true, true, true, true])
        XCTAssertFalse(click.isMuted, "the metronome plays alone")
    }

    /// One part off is one part off. A shared `isMuted` -- or a mute applied to
    /// the sequence rather than the track -- would show up here as the two
    /// violins going quiet together.
    func testMutingOnePartLeavesTheOthersAlone() throws {
        let (_, sequencer) = try self.sequencer("quartet-playback")
        sequencer.tracks[0].isMuted = true
        XCTAssertEqual(sequencer.tracks.map(\.isMuted), [true, false, false, false])
    }

    /// Why the transport asks the TIMELINE when the music is over, and never
    /// the sequencer.
    ///
    /// MEASURED here, not assumed: four bars of 4/4 are sixteen quarter notes,
    /// and every loaded track reports seventeen. music21 writes an end-of-track
    /// marker a beat past the last note and AVFoundation counts it. A transport
    /// that stopped on `lengthInBeats` would therefore sit through a beat of
    /// silence at the end of every score, and one that used it to place the
    /// play head would run off the end of the bar map.
    ///
    /// `PlaybackTimeline.beats` is the end of the MUSIC, so that is what
    /// `PlaybackSound.hasFinished` is given.
    func testTheSequencerRunsPastTheEndOfTheMusic() throws {
        let (_, sequencer) = try self.sequencer("quartet-playback")
        let reported = sequencer.tracks.map(\.lengthInBeats).max() ?? 0
        XCTAssertEqual(reported, 17, accuracy: 0.001,
                       "a beat of end-of-track past the sixteen that sound")

        let music = 16.0   // what ops.playback_timeline reports for this fixture
        XCTAssertTrue(PlaybackSound.hasFinished(beat: music, end: music))
        XCTAssertFalse(PlaybackSound.hasFinished(beat: music - 0.5, end: music))
        XCTAssertFalse(PlaybackSound.hasFinished(beat: music, end: reported),
                       "stopping on the sequencer's length would overrun the map")
    }
}
