import AVFoundation
import XCTest

/// What a listener would actually hear.
///
/// Every audio claim in this app used to be structural -- the right objects
/// were connected to each other -- and nobody had ever checked that a sample
/// came out of the far end. `AVAudioEngine.enableManualRenderingMode` renders
/// offline into a buffer with no audio session, no hardware and no host app, so
/// this is a measurement rather than an anecdote.
///
/// It drives `PlaybackGraph`, which is the graph that ships. A test that built
/// its own parallel wiring would prove only that the test works.
///
/// Three things this established that were assumed before it existed: the
/// bundled General MIDI bank loads on the simulator runtime, `AVAudioSequencer`
/// advances while the engine renders offline, and `AVAudioUnitSampler.volume`
/// is exactly linear in amplitude.
final class PlaybackAudioTests: XCTestCase {

    private let sampleRate = 44100.0
    private let block: AVAudioFrameCount = 4096
    /// Below this is silence. Not zero: a synth's own noise floor and the
    /// tail of the render are not notes.
    private let silence = 1e-5

    // MARK: - Rendering

    private func fixture(_ name: String) throws -> URL {
        guard let url = Bundle(for: Self.self).url(forResource: name,
                                                   withExtension: "mid",
                                                   subdirectory: "Fixtures") else {
            throw XCTSkip("fixture \(name).mid is not in the test bundle")
        }
        return url
    }

    private func quartet(_ count: Int = 4) -> [PlaybackTimeline.Part] {
        let names = ["Violin I", "Violin II", "Viola", "Violoncello"]
        let programs = [40, 40, 41, 42]
        return (0..<count).map {
            .init(index: $0, name: names[$0], instrument: names[$0],
                  program: programs[$0])
        }
    }

    /// A timeline whose clicks land on every beat, so the metronome has
    /// something to play in the window rendered.
    private func timeline(parts: [PlaybackTimeline.Part],
                          beats: Double = 16) -> PlaybackTimeline {
        let bars = stride(from: 0.0, to: beats, by: 4).map {
            PlaybackTimeline.Bar(measure: Int($0 / 4) + 1, start: $0, end: $0 + 4)
        }
        let clicks = stride(from: 0.0, to: beats, by: 1).map {
            PlaybackTimeline.Click(beat: $0, down: $0.truncatingRemainder(dividingBy: 4) == 0)
        }
        return PlaybackTimeline(parts: parts, bars: bars, clicks: clicks,
                                tempos: [.init(beat: 0, bpm: 120)])
    }

    private func loaded(_ fixtureName: String, parts: [PlaybackTimeline.Part],
                        voices: PlaybackVoices = PlaybackVoices(),
                        metronome: Bool = false) throws -> PlaybackGraph {
        let graph = PlaybackGraph()
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        try graph.engine.enableManualRenderingMode(.offline, format: format,
                                                   maximumFrameCount: block)
        try graph.load(midi: try fixture(fixtureName), timeline: timeline(parts: parts))
        graph.apply(voices, parts: parts, metronome: metronome)
        return graph
    }

    /// Render `seconds` and return (rms, peak).
    @discardableResult
    private func render(_ graph: PlaybackGraph,
                        seconds: Double) throws -> (rms: Double, peak: Double) {
        if !graph.engine.isRunning { try graph.engine.start() }
        graph.sequencer?.prepareToPlay()
        try graph.sequencer?.start()
        let buffer = AVAudioPCMBuffer(pcmFormat: graph.engine.manualRenderingFormat,
                                      frameCapacity: block)!
        let target = graph.engine.manualRenderingSampleTime
            + AVAudioFramePosition(seconds * sampleRate)
        var sum = 0.0, peak = 0.0, counted = 0
        while graph.engine.manualRenderingSampleTime < target {
            let remaining = target - graph.engine.manualRenderingSampleTime
            let frames = AVAudioFrameCount(min(AVAudioFramePosition(block), remaining))
            let status = try graph.engine.renderOffline(frames, to: buffer)
            guard status == .success, let channels = buffer.floatChannelData else { break }
            for channel in 0..<Int(buffer.format.channelCount) {
                let samples = channels[channel]
                for frame in 0..<Int(buffer.frameLength) {
                    let value = Double(samples[frame])
                    sum += value * value
                    peak = max(peak, abs(value))
                    counted += 1
                }
            }
        }
        return (counted > 0 ? (sum / Double(counted)).squareRoot() : 0, peak)
    }

    // MARK: - The four assertions

    /// Voices on: there is a sound, and the sound bank behind it loaded.
    func testVoicesOnMakeASound() throws {
        let parts = quartet()
        let graph = try loaded("quartet-playback", parts: parts)
        XCTAssertEqual(graph.bankFailures, [],
                       "the General MIDI bank at \(PlaybackSound.bank.path) did not load")
        let sound = try render(graph, seconds: 2.0)
        XCTAssertGreaterThan(sound.rms, silence, "the graph rendered silence")
    }

    /// Every voice muted, the metronome on: the click, and only the click.
    ///
    /// Told apart from music by its SHAPE rather than its level. A click is a
    /// short transient twice a second against a floor of nothing, so its peak
    /// stands far above its RMS; four sustained string parts do not do that.
    /// Asserting "quieter than the music" alone would pass on a graph that had
    /// simply turned everything down.
    func testEveryVoiceMutedLeavesTheClickAndNothingElse() throws {
        let parts = quartet()
        var silenced = PlaybackVoices()
        silenced.setAll(on: false, parts: parts)

        let click = try render(try loaded("quartet-playback", parts: parts,
                                          voices: silenced, metronome: true),
                               seconds: 2.0)
        let music = try render(try loaded("quartet-playback", parts: parts,
                                          voices: PlaybackVoices(), metronome: false),
                               seconds: 2.0)

        XCTAssertGreaterThan(click.rms, silence, "the metronome did not play alone")
        XCTAssertGreaterThan(click.peak / click.rms, music.peak / music.rms,
                             "what is left should be transients, not held notes")
    }

    /// Everything off: TRUE silence, and the product rule that makes it
    /// acceptable is the playhead, not the sound.
    func testEverythingOffIsSilence() throws {
        let parts = quartet()
        var silenced = PlaybackVoices()
        silenced.setAll(on: false, parts: parts)
        let sound = try render(try loaded("quartet-playback", parts: parts,
                                          voices: silenced, metronome: false),
                               seconds: 2.0)
        XCTAssertLessThan(sound.peak, silence,
                          "everything off should make no sound at all")
    }

    /// The one that stops the fader being a slider wired to nothing.
    func testTheFaderChangesWhatIsRendered() throws {
        let parts = quartet()
        let full = try render(try loaded("quartet-playback", parts: parts),
                              seconds: 2.0)

        var half = PlaybackVoices()
        for part in parts { half.setFader(5, channel: part.index) }
        let quiet = try render(try loaded("quartet-playback", parts: parts,
                                          voices: half),
                               seconds: 2.0)

        // Against the DEFAULT fader, which is 7 and not 10 -- the untouched
        // mixer is already 6 dB below unity, and measuring against unity was
        // wrong by exactly 1/amplitude(7) at every notch. That the ratio comes
        // out at amplitude(5)/amplitude(7) is what ties the number a reader
        // moves to the air that comes out, AND says the default is really
        // being applied rather than assumed.
        let expected = PlaybackGain.amplitude(for: 5)
            / PlaybackGain.amplitude(for: PlaybackGain.defaultFader)
        XCTAssertEqual(quiet.rms / full.rms, expected, accuracy: 0.02)
        XCTAssertLessThan(quiet.rms, full.rms, "5 is quieter than the default 7")
    }

    /// And the curve itself, through the audio rather than through arithmetic.
    func testTheRenderedLevelFollowsTheCurveAtEveryNotch() throws {
        let parts = quartet()
        let full = try render(try loaded("quartet-playback", parts: parts), seconds: 1.5)
        for notch in [8, 5, 3] {
            var voices = PlaybackVoices()
            for part in parts { voices.setFader(notch, channel: part.index) }
            let sound = try render(try loaded("quartet-playback", parts: parts,
                                              voices: voices),
                                   seconds: 1.5)
            let expected = PlaybackGain.amplitude(for: notch)
                / PlaybackGain.amplitude(for: PlaybackGain.defaultFader)
            XCTAssertEqual(sound.rms / full.rms, expected,
                           accuracy: 0.02, "notch \(notch)")
        }
    }

    /// A fader is PER CHANNEL. The staggered fixture has parts of 2, 4, 6 and
    /// 8 bars, so pulling one down cannot be confused with pulling the master.
    func testAFaderTouchesOneChannelOnly() throws {
        let parts = quartet()
        let all = try render(try loaded("staggered-playback", parts: parts), seconds: 2.0)

        var one = PlaybackVoices()
        one.setFader(0, channel: 0)
        let rest = try render(try loaded("staggered-playback", parts: parts, voices: one),
                              seconds: 2.0)

        XCTAssertLessThan(rest.rms, all.rms, "pulling one fader down changed nothing")
        XCTAssertGreaterThan(rest.rms, all.rms * 0.2,
                             "pulling one fader down took more than one channel")
    }

    /// The play head does not depend on hearing anything.
    ///
    /// Every channel muted and the metronome off is TRUE silence, and the
    /// transport must still run through it -- that silent state is only
    /// allowed because the reader can see where the music is. A cursor driven
    /// off audio, or stopped when nothing sounds, would make the one state the
    /// feature exists for the one state it does not work in.
    func testAMutedChannelDoesNotStopTheClock() throws {
        let parts = quartet()
        var silenced = PlaybackVoices()
        silenced.setAll(on: false, parts: parts)
        let graph = try loaded("quartet-playback", parts: parts,
                               voices: silenced, metronome: false)
        let sound = try render(graph, seconds: 2.0)
        XCTAssertLessThan(sound.peak, silence, "this must be the silent case")
        // Two seconds at 120bpm is four quarter notes.
        XCTAssertEqual(graph.sequencer?.currentPositionInBeats ?? 0, 4.0,
                       accuracy: 0.25,
                       "the play head stopped when the sound did")
    }

    /// A fader moved WHILE the music runs. One that only took effect before
    /// `start` would make every strip in the mixer feel broken.
    ///
    /// Rendered against a SECOND graph running in lockstep, untouched. The
    /// first attempt compared the second of audio against the first and very
    /// nearly passed for the wrong reason: the two windows hold different
    /// notes, so their levels differ by a quarter before any fader moves.
    /// Comparing like against like leaves the fader as the only difference.
    func testAFaderMovedDuringPlaybackTakesEffectImmediately() throws {
        let parts = quartet()
        let moving = try loaded("quartet-playback", parts: parts)
        let steady = try loaded("quartet-playback", parts: parts)

        let openingMoving = try render(moving, seconds: 1.0)
        let openingSteady = try render(steady, seconds: 1.0)
        XCTAssertGreaterThan(openingMoving.rms, silence, "nothing was playing")
        XCTAssertEqual(openingMoving.rms, openingSteady.rms, accuracy: 1e-6,
                       "the two graphs must start identical or nothing below holds")

        var quieter = PlaybackVoices()
        for part in parts { quieter.setFader(5, channel: part.index) }
        moving.apply(quieter, parts: parts, metronome: false)

        let after = try render(moving, seconds: 1.0)
        let reference = try render(steady, seconds: 1.0)

        let expected = PlaybackGain.amplitude(for: 5)
            / PlaybackGain.amplitude(for: PlaybackGain.defaultFader)
        XCTAssertEqual(after.rms / reference.rms, expected, accuracy: 0.03,
                       "the fader moved mid-playback and the level did not follow")
    }
}
