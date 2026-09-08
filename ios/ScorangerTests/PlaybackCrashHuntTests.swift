import AVFoundation
import XCTest

/// A hard reproduction pass at Ali's crash, using his own material.
///
/// "App crashes in playback of Sous le ciel de Paris." The earlier harness
/// drove the app on a phone and could not make it fall over, and ruled out the
/// null-instrument part, the track/part assumption and the zero-note staff by
/// measurement. It named the MATERIAL as the gap: his library reads ~14:36
/// where the dev workspace had 3:24.
///
/// That reading was wrong, and it is worth writing down because it sent the
/// search the wrong way. 14:36 is his library TOTAL across four arrangements,
/// about 3:39 each; the arrangement here performs in 3:24. The material is not
/// meaningfully longer, so length was never the difference.
///
/// So this drives the REAL thing instead of an approximation: the actual
/// performance MIDI of the actual arrangement -- 136 bars, four staves, 1442
/// note-ons -- through the shipping PlaybackGraph, rendered offline, while the
/// mixer is worked underneath it. A trap becomes a test failure here, where a
/// device gives back a crash log nobody has.
///
/// The MIDI fixture is deliberately the PRE-FIX performance, the one his build
/// would have produced: `Acc. Chords` is a names-only staff and its channel
/// carries 485 note-ons it should never have had (see the chord-symbol fix).
/// If the crash lived in that mismatch -- a channel sounding for a part the
/// score says has no notes -- this is the material that would show it.
final class PlaybackCrashHuntTests: XCTestCase {

    private let sampleRate = 44_100.0
    private let block: AVAudioFrameCount = 4_096

    private func fixture(_ name: String, _ ext: String) throws -> URL {
        // subdirectory: Fixtures is declared as a FOLDER reference in
        // project.yml, so its contents are not at the bundle root
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: name, withExtension: ext, subdirectory: "Fixtures"),
            "no fixture Fixtures/\(name).\(ext)")
        return url
    }

    /// His arrangement's real timeline, decoded from the engine's own output.
    private func realTimeline() throws -> PlaybackTimeline {
        let data = try Data(contentsOf: try fixture("sous-le-ciel-timeline", "json"))
        return try JSONDecoder().decode(PlaybackTimeline.self, from: data)
    }

    private func realGraph(_ timeline: PlaybackTimeline) throws -> PlaybackGraph {
        let graph = PlaybackGraph()
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                                 channels: 2))
        try graph.engine.enableManualRenderingMode(.offline, format: format,
                                                   maximumFrameCount: block)
        try graph.load(midi: try fixture("sous-le-ciel-performance", "mid"),
                       timeline: timeline, instruments: PlaybackInstruments())
        return graph
    }

    /// Start the transport. `load` builds the graph and does NOT start the
    /// sequencer -- PlaybackEngine.play does that -- so a render without this
    /// produces SILENCE, and a stress test rendering silence stresses nothing.
    /// The first version of this file made exactly that mistake.
    private func start(_ graph: PlaybackGraph) throws {
        let sequencer = try XCTUnwrap(graph.sequencer)
        if !graph.engine.isRunning { try graph.engine.start() }
        sequencer.prepareToPlay()
        try sequencer.start()
    }

    /// Render `seconds` of it, and return the loudest sample seen, so a caller
    /// can prove the performance was audible rather than assuming it.
    @discardableResult
    private func render(_ graph: PlaybackGraph, seconds: Double) throws -> Float {
        if !graph.engine.isRunning { try graph.engine.start() }
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: graph.engine.manualRenderingFormat, frameCapacity: block))
        let target = graph.engine.manualRenderingSampleTime
            + AVAudioFramePosition(seconds * sampleRate)
        var peak: Float = 0
        while graph.engine.manualRenderingSampleTime < target {
            let frames = AVAudioFrameCount(min(Double(block),
                Double(target - graph.engine.manualRenderingSampleTime)))
            if frames == 0 { break }
            let status = try graph.engine.renderOffline(frames, to: buffer)
            guard status == .success else { break }
            if let channel = buffer.floatChannelData?[0] {
                for frame in 0..<Int(buffer.frameLength) {
                    peak = max(peak, abs(channel[frame]))
                }
            }
        }
        return peak
    }

    /// How far the offline clock actually got, in seconds.
    private func rendered(_ graph: PlaybackGraph) -> Double {
        Double(graph.engine.manualRenderingSampleTime) / sampleRate
    }

    // MARK: what the material itself claims

    func testTheFixtureIsTheRealArrangement() throws {
        let timeline = try realTimeline()
        XCTAssertEqual(timeline.parts.count, 4)
        XCTAssertEqual(timeline.parts.map(\.name),
                       ["Violin I", "Accordion R.H.", "Acc. Chords", "Acc. Bass"])
        XCTAssertEqual(timeline.bars.count, 136)
        // 3:24 at 120bpm, not the 14:36 the earlier note reached for
        XCTAssertEqual(timeline.bars.last?.end, 408.0)
    }

    func testTheWholePerformanceRendersWithoutFallingOver() throws {
        let timeline = try realTimeline()
        let graph = try realGraph(timeline)
        try start(graph)
        // the entire 3:24, in one go
        let peak = try render(graph, seconds: 205)
        XCTAssertGreaterThan(rendered(graph), 204,
                             "the offline clock did not reach the end of the piece")
        XCTAssertGreaterThan(peak, 1e-4,
                             "it rendered silence -- the transport was not running, "
                             + "so nothing was actually performed")
    }

    func testTheMixerIsWorkedThroughoutThePerformance() throws {
        let timeline = try realTimeline()
        let graph = try realGraph(timeline)
        try start(graph)
        var voices = PlaybackVoices()
        // every channel muted, unmuted, and faded, over and over, while the
        // music runs -- including the phantom channel
        for step in 0..<40 {
            let channel = step % timeline.parts.count
            if voices.isOn(channel) != (step % 2 == 0) { voices.toggle(channel) }
            voices.setFader(step % 11, channel: channel)
            graph.apply(voices, parts: timeline.parts, metronome: step % 3 == 0)
            try render(graph, seconds: 1)
        }
        XCTAssertGreaterThan(rendered(graph), 39, "the 40 seconds were not rendered")
    }

    func testInstrumentsAreChangedUnderTheRunningPerformance() throws {
        let timeline = try realTimeline()
        let graph = try realGraph(timeline)
        try start(graph)
        for (step, program) in [0, 24, 40, 56, 73, 105, 127].enumerated() {
            let channel = step % timeline.parts.count
            _ = graph.setInstrument(program: UInt8(program), bank: .melodic,
                                    channel: channel)
            try render(graph, seconds: 2)
        }
        XCTAssertGreaterThan(rendered(graph), 13, "the 14 seconds were not rendered")
    }

    /// The channel the score says has no notes.
    ///
    /// Every question asked of it at once, at beats spread across the whole
    /// performance: is it sounding, what bar is this, what is its label, what
    /// is its gain. This is the part whose reported note count and whose audio
    /// disagreed, and disagreement is where an index goes out of range.
    func testTheNamesOnlyChannelAnswersEveryQuestionAtEveryBeat() throws {
        let timeline = try realTimeline()
        let chords = try XCTUnwrap(timeline.parts.first { $0.name == "Acc. Chords" })
        var voices = PlaybackVoices()
        if voices.isOn(chords.index) { voices.toggle(chords.index) }
        for beat in stride(from: -8.0, through: 420.0, by: 0.25) {
            _ = chords.isSounding(at: beat)
            _ = timeline.bar(atBeat: beat)
            _ = timeline.span(atBeat: beat)
            _ = voices.amplitude(chords.index)
        }
        XCTAssertEqual(PlaybackChannels.label(at: chords.index, in: timeline.parts),
                       "Acc. Chords")
    }

    /// Beats no performance should ever produce, asked of the real timeline.
    ///
    /// The play head is a Double coming out of AVAudioSequencer, and the code
    /// around it does arithmetic and array lookups. A negative beat happens on
    /// a pickup; the others are what a stalled or reset sequencer can hand
    /// back, and `Int(nan)` is a trap rather than an error.
    func testTheTimelineSurvivesBeatsThatShouldNotHappen() throws {
        let timeline = try realTimeline()
        for beat in [-1.0, -1e9, 0.0, 407.999, 408.0, 1e9,
                     .infinity, -.infinity, .nan] as [Double] {
            _ = timeline.bar(atBeat: beat)
            _ = timeline.span(atBeat: beat)
            for part in timeline.parts { _ = part.isSounding(at: beat) }
        }
    }
}
