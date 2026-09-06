import Accelerate
import AVFoundation
import XCTest

/// Does a strip control the voice it NAMES?
///
/// Ali, on a four-staff score: he "turned down everything but voice one" and
/// still heard all four. Every existing audio assertion in this suite is about
/// the graph as a whole -- there is a sound, everything muted leaves the click,
/// the taper is a square law -- and not one of them says WHICH part a channel
/// belongs to. A mixer wired entirely to the wrong parts passes all of them.
///
/// So this identifies the sound. The fixture's four parts hold four sustained
/// pitches a fifth apart -- G3 196.0, D4 293.7, A4 440.0, E5 659.3 -- chosen so
/// that none is a harmonic of another. Turn up exactly one strip, render, find
/// the loudest peak: that frequency names the part that actually sounded, and
/// it has to be the part whose strip was up.
final class PlaybackChannelIsolationTests: XCTestCase {

    private let sampleRate = 44100.0
    private let block: AVAudioFrameCount = 4096
    /// Past the attack, so what is measured is the tone rather than the onset.
    private let skip = 8192
    private let window = 8192
    private let silence = 1e-5

    /// The fixture's parts, in order, with the pitch each one holds.
    private let expected: [(name: String, hz: Double)] = [
        ("Part One", 196.00),   // G3
        ("Part Two", 293.66),   // D4
        ("Part Three", 440.00), // A4
        ("Part Four", 659.26),  // E5
    ]

    private func parts() -> [PlaybackTimeline.Part] {
        expected.enumerated().map { index, part in
            .init(index: index, name: part.name, instrument: "Violin", program: 40)
        }
    }

    private func timeline(_ parts: [PlaybackTimeline.Part]) -> PlaybackTimeline {
        let bars = stride(from: 0.0, to: 16.0, by: 4).map {
            PlaybackTimeline.Bar(measure: Int($0 / 4) + 1, start: $0, end: $0 + 4)
        }
        return PlaybackTimeline(parts: parts, bars: bars, clicks: [],
                                tempos: [.init(beat: 0, bpm: 120)])
    }

    private func fixture(_ name: String = "four-distinct-parts") throws -> URL {
        guard let url = Bundle(for: Self.self).url(forResource: name,
                                                   withExtension: "mid",
                                                   subdirectory: "Fixtures") else {
            throw XCTSkip("\(name).mid is not in the test bundle")
        }
        return url
    }

    /// The shipping graph, with `voices` applied. No parallel wiring: a test
    /// that built its own graph would prove only that the test works.
    private func graph(voices: PlaybackVoices,
                       fixture name: String = "four-distinct-parts") throws -> PlaybackGraph {
        let graph = PlaybackGraph()
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                   channels: 2)!
        try graph.engine.enableManualRenderingMode(.offline, format: format,
                                                   maximumFrameCount: block)
        let parts = self.parts()
        try graph.load(midi: try fixture(name), timeline: timeline(parts))
        graph.apply(voices, parts: parts, metronome: false)
        return graph
    }

    private func render(_ graph: PlaybackGraph) throws -> [Float] {
        if !graph.engine.isRunning { try graph.engine.start() }
        graph.sequencer?.prepareToPlay()
        try graph.sequencer?.start()
        let buffer = AVAudioPCMBuffer(pcmFormat: graph.engine.manualRenderingFormat,
                                      frameCapacity: block)!
        var out: [Float] = []
        out.reserveCapacity(skip + window)
        while out.count < skip + window {
            let want = AVAudioFrameCount(min(Int(block), skip + window - out.count))
            let status = try graph.engine.renderOffline(want, to: buffer)
            guard status == .success, let channels = buffer.floatChannelData else { break }
            out.append(contentsOf: UnsafeBufferPointer(start: channels[0],
                                                       count: Int(buffer.frameLength)))
        }
        return Array(out.dropFirst(skip).prefix(window))
    }

    private func rms(_ signal: [Float]) -> Double {
        guard !signal.isEmpty else { return 0 }
        return (signal.reduce(0.0) { $0 + Double($1) * Double($1) }
                / Double(signal.count)).squareRoot()
    }

    /// The magnitude spectrum of a Hann-windowed real signal.
    private func spectrum(_ signal: [Float]) -> [Double] {
        let n = window
        guard signal.count == n else { return [] }
        var input = signal.map { $0 }
        var hann = [Float](repeating: 0, count: n)
        vDSP_hann_window(&hann, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(input, 1, hann, 1, &input, 1, vDSP_Length(n))
        let half = n / 2
        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        let log2n = vDSP_Length(log2(Double(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!,
                                            imagp: imaginaryPointer.baseAddress!)
                input.withUnsafeBufferPointer { pointer in
                    pointer.baseAddress!.withMemoryRebound(to: DSPComplex.self,
                                                           capacity: half) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }
        return magnitudes.map(Double.init)
    }

    /// Energy in a narrow band around `hz`.
    private func energy(_ spectrum: [Double], at hz: Double) -> Double {
        guard !spectrum.isEmpty else { return 0 }
        let resolution = sampleRate / Double(window)
        let centre = Int((hz / resolution).rounded())
        // +/- two bins: enough for the sampler's tuning and the window's
        // leakage, narrow enough that neighbouring fundamentals do not overlap
        // (the closest pair here is 196 and 294Hz, about 18 bins apart).
        let low = max(centre - 2, 0)
        let high = min(centre + 2, spectrum.count - 1)
        guard low <= high else { return 0 }
        return (low...high).reduce(0.0) { $0 + spectrum[$1] }
    }

    /// Which part is loudest AT ITS OWN FUNDAMENTAL.
    ///
    /// Not the dominant peak of the whole spectrum, which is what the first
    /// version of this test asked and got wrong: a violin sample's second
    /// harmonic is often louder than its fundamental, so part 0's G3 was
    /// identified as "392Hz, no part of this score" and part 3's E5 as its own
    /// fourth harmonic. Both parts had sounded correctly and the measurement
    /// was the thing at fault.
    ///
    /// Comparing energy at the four fundamentals is immune to that, because
    /// the fixture's pitches are chosen so no part's harmonic series lands on
    /// another part's fundamental: G3's are 392 and 588, D4's 587 and 881,
    /// A4's 880 -- and none of 196, 294, 440, 659 appears in any other's.
    private func loudestFundamental(_ signal: [Float]) -> (part: Int, ratio: Double)? {
        let magnitudes = spectrum(signal)
        guard !magnitudes.isEmpty else { return nil }
        let levels = expected.map { energy(magnitudes, at: $0.hz) }
        guard let best = levels.indices.max(by: { levels[$0] < levels[$1] }),
              levels[best] > 0 else { return nil }
        let others = levels.enumerated().filter { $0.offset != best }.map(\.element)
        let runnerUp = others.max() ?? 0
        return (best, runnerUp > 0 ? levels[best] / runnerUp : .infinity)
    }

    // MARK: - The assertion the mixer never had

    /// ONE STRIP UP, and the part that sounds is the part it names.
    ///
    /// Four renders, one per strip. Each says two things: something sounded at
    /// all, and the loudest thing in it was that strip's own pitch. An
    /// off-by-one anywhere between the strip, the sampler and the MIDI track
    /// fails this on every strip at once.
    func testOneStripUpSoundsThatPartAndNoOther() throws {
        for (index, part) in expected.enumerated() {
            var voices = PlaybackVoices()
            voices.setAll(on: false, parts: parts())
            voices.toggle(index)   // back on
            let rendered = try render(try graph(voices: voices))
            let level = rms(rendered)
            XCTAssertGreaterThan(level, silence,
                                 "strip \(index) (\(part.name)) is the only one "
                                 + "up and nothing sounded at all")
            guard let heard = loudestFundamental(rendered) else {
                XCTFail("strip \(index) rendered nothing measurable")
                continue
            }
            XCTAssertEqual(heard.part, index,
                           "strip \(index) is up -- that is \(part.name) at "
                           + "\(part.hz)Hz -- but the loudest fundamental is "
                           + "part \(heard.part) (\(self.expected[heard.part].name)). "
                           + "The strip is not wired to the voice it names.")
            // And clearly loudest, not marginally: a strip that leaks into its
            // neighbours would still win by a hair.
            XCTAssertGreaterThan(heard.ratio, 3.0,
                                 "strip \(index) is only \(heard.ratio)x louder "
                                 + "at its own pitch than at another part's -- "
                                 + "the channels are bleeding into each other")
        }
    }

    /// THE REPORTED CASE, exactly: everything down but voice one.
    ///
    /// Ali heard all four. The three that were turned down have to be gone --
    /// not quieter, gone -- so this asserts on the level as well as the pitch.
    func testEverythingDownButVoiceOneLeavesOnlyVoiceOne() throws {
        var voices = PlaybackVoices()
        voices.setAll(on: true, parts: parts())
        for index in 1..<expected.count { voices.setFader(0, channel: index) }
        let rendered = try render(try graph(voices: voices))

        var all = PlaybackVoices()
        all.setAll(on: true, parts: parts())
        let everything = rms(try render(try graph(voices: all)))

        let one = rms(rendered)
        XCTAssertGreaterThan(one, silence, "voice one is up and silent")
        XCTAssertLessThan(one, everything * 0.7,
                          "turning three of four voices to zero barely changed "
                          + "the level (\(one) against \(everything)): the "
                          + "faders are not reaching individual parts")
        XCTAssertEqual(loudestFundamental(rendered)?.part, 0,
                       "the voice left up is part 0 at 196Hz, and that is not "
                       + "what is sounding")
    }

    /// THE SAME CLAIM, ON THE ENGINE'S OWN OUTPUT.
    ///
    /// Everything above runs on a MIDI file written straight from music21 for
    /// this test. The app plays a file written by `scor playback`, which
    /// expands repeats, converts written pitch to sounding pitch and emits its
    /// own track order -- so a mapping that holds for one and not the other
    /// would be a mapping that holds nowhere useful. This is the same four
    /// parts taken back out of the engine: imported, played back, and the
    /// resulting file used as the fixture.
    func testTheEnginesOwnFileRoutesTheSameWay() throws {
        for (index, part) in expected.enumerated() {
            var voices = PlaybackVoices()
            voices.setAll(on: false, parts: parts())
            voices.toggle(index)   // back on
            let rendered = try render(try graph(voices: voices,
                                                fixture: "four-distinct-parts-engine"))
            XCTAssertGreaterThan(rms(rendered), silence,
                                 "strip \(index) is up and the engine's own "
                                 + "file rendered silence")
            guard let heard = loudestFundamental(rendered) else {
                XCTFail("strip \(index) rendered nothing measurable")
                continue
            }
            XCTAssertEqual(heard.part, index,
                           "on the ENGINE's file, strip \(index) "
                           + "(\(part.name)) sounded part \(heard.part) instead")
        }
    }

    /// And the invariant the whole mapping rests on, stated where it can fail
    /// loudly: the sequencer hands back ONE track per part.
    ///
    /// `PlaybackGraph` and `PlaybackEngine` both carry the comment that
    /// `AVAudioSequencer.tracks` omits music21's conductor track, and every
    /// index in the mixer depends on it. If a runtime ever includes it, every
    /// strip drives the part above its own and the last part drives nothing --
    /// which is a mixer that looks wired and is not.
    func testTheSequencerHasOneTrackPerPartAndTheClick() throws {
        let graph = try graph(voices: PlaybackVoices())
        let tracks = graph.sequencer?.tracks.count ?? 0
        XCTAssertEqual(tracks, expected.count + 1,
                       "the sequencer reports \(tracks) tracks for "
                       + "\(expected.count) parts plus the click. If it is one "
                       + "more, the conductor track is being counted and every "
                       + "strip is off by one.")
    }
}
