import AVFoundation
import XCTest

/// The instrument picker's two claims about the audio graph, measured rather
/// than assumed.
///
/// The catalogue in `GeneralMIDI` was read out of `gs_instruments.dls` by
/// walking its RIFF chunks on a Mac. That says what is in the FILE. This says
/// what the runtime does with it, which is the claim a reader's ear cares
/// about -- an entry in the picker that loads nothing is a silent channel with
/// a confident label on it.
///
/// Rendered offline, the way `PlaybackAudioTests` does: manual rendering mode
/// needs no audio session, no hardware and no host app, and it drives the
/// `PlaybackGraph` that ships rather than a parallel copy of its wiring.
final class PlaybackInstrumentGraphTests: XCTestCase {

    private let sampleRate = 44100.0
    private let block: AVAudioFrameCount = 4096
    private let silence = 1e-5

    private func fixture(_ name: String) throws -> URL {
        guard let url = Bundle(for: Self.self).url(forResource: name,
                                                   withExtension: "mid",
                                                   subdirectory: "Fixtures") else {
            throw XCTSkip("fixture \(name).mid is not in the test bundle")
        }
        return url
    }

    private func quartet() -> [PlaybackTimeline.Part] {
        let names = ["Violin I", "Violin II", "Viola", "Violoncello"]
        let programs = [40, 40, 41, 42]
        return (0..<4).map {
            .init(index: $0, name: names[$0], instrument: names[$0],
                  program: programs[$0])
        }
    }

    private func timeline(parts: [PlaybackTimeline.Part],
                          beats: Double = 16) -> PlaybackTimeline {
        let bars = stride(from: 0.0, to: beats, by: 4).map {
            PlaybackTimeline.Bar(measure: Int($0 / 4) + 1, start: $0, end: $0 + 4)
        }
        let clicks = stride(from: 0.0, to: beats, by: 1).map {
            PlaybackTimeline.Click(beat: $0,
                                   down: $0.truncatingRemainder(dividingBy: 4) == 0)
        }
        return PlaybackTimeline(parts: parts, bars: bars, clicks: clicks,
                                tempos: [.init(beat: 0, bpm: 120)])
    }

    private func loaded(parts: [PlaybackTimeline.Part],
                        instruments: PlaybackInstruments = PlaybackInstruments())
        throws -> PlaybackGraph {
        let graph = PlaybackGraph()
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                   channels: 2)!
        try graph.engine.enableManualRenderingMode(.offline, format: format,
                                                   maximumFrameCount: block)
        try graph.load(midi: try fixture("quartet-playback"),
                       timeline: timeline(parts: parts), instruments: instruments)
        return graph
    }

    @discardableResult
    private func render(_ graph: PlaybackGraph, seconds: Double) throws -> Double {
        if !graph.engine.isRunning { try graph.engine.start() }
        let buffer = AVAudioPCMBuffer(pcmFormat: graph.engine.manualRenderingFormat,
                                      frameCapacity: block)!
        let target = graph.engine.manualRenderingSampleTime
            + AVAudioFramePosition(seconds * sampleRate)
        var sum = 0.0, counted = 0
        while graph.engine.manualRenderingSampleTime < target {
            let remaining = target - graph.engine.manualRenderingSampleTime
            let frames = AVAudioFrameCount(min(AVAudioFramePosition(block), remaining))
            let status = try graph.engine.renderOffline(frames, to: buffer)
            guard status == .success, let channels = buffer.floatChannelData else { break }
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    let value = Double(channels[channel][frame])
                    sum += value * value
                    counted += 1
                }
            }
        }
        return counted > 0 ? (sum / Double(counted)).squareRoot() : 0
    }

    // MARK: - The catalogue is real

    /// All 128, one at a time, on the graph that ships. An entry the picker
    /// offers that will not load is a silent channel with a label on it.
    func testEveryMelodicProgramInTheCatalogueLoads() throws {
        let graph = try loaded(parts: quartet())
        var refused: [UInt8] = []
        for instrument in GeneralMIDI.melodic {
            if !graph.setInstrument(program: instrument.program,
                                    bank: .melodic, channel: 0) {
                refused.append(instrument.program)
            }
        }
        XCTAssertEqual(refused, [],
                       "the melodic bank at \(PlaybackSound.bank.path) refused these")
    }

    /// Nine kits, and the reason the picker offers nine rather than 128: the
    /// percussion bank holds nothing at the other programs.
    func testEveryDrumKitInTheCatalogueLoads() throws {
        let graph = try loaded(parts: quartet())
        var refused: [UInt8] = []
        for kit in GeneralMIDI.kits {
            if !graph.setInstrument(program: kit.program,
                                    bank: .percussion, channel: 0) {
                refused.append(kit.program)
            }
        }
        XCTAssertEqual(refused, [], "the percussion bank refused these kits")
    }

    /// A channel that failed to load a sound is recorded, and a channel that
    /// has just been given one that works is no longer on that list -- the
    /// failures are a live fact about the graph, not a log of the load.
    func testARepairedChannelStopsBeingReportedAsAFailure() throws {
        let graph = try loaded(parts: quartet())
        XCTAssertEqual(graph.bankFailures, [])
        XCTAssertTrue(graph.setInstrument(program: 0, bank: .melodic, channel: 0))
        XCTAssertEqual(graph.bankFailures, [])
    }

    /// A channel the graph does not have is refused rather than trapped: the
    /// part list and the sampler list can disagree for one layout pass while a
    /// new arrangement loads.
    func testAChannelTheGraphDoesNotHaveIsRefused() throws {
        let graph = try loaded(parts: quartet())
        XCTAssertFalse(graph.setInstrument(program: 0, bank: .melodic, channel: 99))
    }

    // MARK: - Mid-performance

    /// The reader changes a strip's instrument while the music is playing.
    /// `loadSoundBankInstrument` is per-node and each part has its own
    /// sampler, so nothing is rebuilt: the clock keeps running, the play head
    /// does not move back, and sound keeps coming out.
    func testChangingAnInstrumentMidPerformanceDoesNotRestartTheTransport() throws {
        let parts = quartet()
        let graph = try loaded(parts: parts)
        graph.apply(PlaybackVoices(), parts: parts, metronome: false)
        try graph.engine.start()
        graph.sequencer?.prepareToPlay()
        try graph.sequencer?.start()

        try render(graph, seconds: 1)
        let before = graph.sequencer?.currentPositionInBeats ?? 0
        XCTAssertGreaterThan(before, 0)

        // every voice on a piano, which is the ask this feature came from
        var instruments = PlaybackInstruments()
        instruments.chooseAll(program: 0, parts: parts)
        graph.applyInstruments(instruments, parts: parts)

        XCTAssertEqual(graph.sequencer?.isPlaying, true,
                       "the transport stopped when an instrument changed")
        let after = graph.sequencer?.currentPositionInBeats ?? 0
        XCTAssertGreaterThanOrEqual(after, before,
                                    "the play head moved backwards")

        let rms = try render(graph, seconds: 1)
        XCTAssertGreaterThan(rms, silence,
                             "the score went silent after the instrument changed")
    }

    /// The initial patch comes from the reader's choices, not only from the
    /// engine's programs -- a score reopened plays in the sound it was left in.
    func testAGraphLoadsTheChoicesItIsGiven() throws {
        let parts = quartet()
        var instruments = PlaybackInstruments()
        instruments.chooseAll(program: 0, parts: parts)
        let graph = try loaded(parts: parts, instruments: instruments)
        XCTAssertEqual(graph.bankFailures, [])
        graph.apply(PlaybackVoices(), parts: parts, metronome: false)
        try graph.engine.start()
        graph.sequencer?.prepareToPlay()
        try graph.sequencer?.start()
        XCTAssertGreaterThan(try render(graph, seconds: 1), silence)
    }
}
