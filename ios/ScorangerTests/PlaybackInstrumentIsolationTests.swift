import Accelerate
import AVFoundation
import XCTest

/// Does a strip's INSTRUMENT reach the part it names?
///
/// Ali: "I still hear the wrong instruments on the wrong staffs." Gain and
/// mute are measured correct in `PlaybackChannelIsolationTests`, and the
/// instrument travels the same index -- `channel: part.index` -- but it is a
/// different call on a different property of the sampler, and nothing had ever
/// listened to it. An argument that it must be right is not a measurement.
///
/// So this changes one strip's instrument and listens to all four parts. The
/// part whose strip changed must sound different; the other three must sound
/// exactly as they did. Done for every strip in turn, so a systematic
/// off-by-one shows up as "strip 1 changed part 0" rather than as a vague
/// failure.
///
/// The discriminator is the one `PlaybackTimbreTests` established: cosine
/// similarity between magnitude spectra. Two renders of the same program are
/// identical to within 1e-6; a flute against a violin is far apart.
final class PlaybackInstrumentIsolationTests: XCTestCase {

    private let sampleRate = 44100.0
    private let block: AVAudioFrameCount = 4096
    private let skip = 8192
    private let window = 8192

    /// Violin on every part to begin with, so the only thing that can change
    /// a part's timbre is the strip being pointed at it.
    private let startingProgram: UInt8 = 40
    /// A flute: about as far from a bowed string as the bank goes, and the
    /// pair `PlaybackTimbreTests` measured at 0.665 similarity.
    private let changedProgram: UInt8 = 73

    private let pitches: [Double] = [196.00, 293.66, 440.00, 659.26]

    private func parts() -> [PlaybackTimeline.Part] {
        pitches.indices.map { index in
            .init(index: index, name: "Part \(index)", instrument: "Violin",
                  program: Int(startingProgram))
        }
    }

    private func timeline(_ parts: [PlaybackTimeline.Part]) -> PlaybackTimeline {
        let bars = stride(from: 0.0, to: 16.0, by: 4).map {
            PlaybackTimeline.Bar(measure: Int($0 / 4) + 1, start: $0, end: $0 + 4)
        }
        return PlaybackTimeline(parts: parts, bars: bars, clicks: [],
                                tempos: [.init(beat: 0, bpm: 120)])
    }

    private func fixture() throws -> URL {
        guard let url = Bundle(for: Self.self).url(forResource: "four-distinct-parts",
                                                   withExtension: "mid",
                                                   subdirectory: "Fixtures") else {
            throw XCTSkip("four-distinct-parts.mid is not in the test bundle")
        }
        return url
    }

    /// One part audible, with `change` applied to whichever strip it names.
    /// Returns the magnitude spectrum of what came out.
    private func spectrumHearing(part audible: Int,
                                 changing strip: Int?,
                                 to program: UInt8) throws -> [Double] {
        let graph = PlaybackGraph()
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                   channels: 2)!
        try graph.engine.enableManualRenderingMode(.offline, format: format,
                                                   maximumFrameCount: block)
        let parts = self.parts()
        try graph.load(midi: try fixture(), timeline: timeline(parts))

        // The instrument change goes through the SAME call the picker makes:
        // `PlaybackEngine.setInstrument` does exactly this with the part's own
        // index, so the routing under test is the routing that ships.
        if let strip {
            graph.setInstrument(program: program, bank: .melodic,
                                channel: parts[strip].index)
        }
        var voices = PlaybackVoices()
        voices.setAll(on: false, parts: parts)
        voices.toggle(audible)
        graph.apply(voices, parts: parts, metronome: false)
        return spectrum(try render(graph))
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

    /// Cosine similarity: 1.0 is the same spectrum, lower is a different one.
    private func similarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for index in a.indices {
            dot += a[index] * b[index]
            na += a[index] * a[index]
            nb += b[index] * b[index]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    // MARK: - The assertion

    /// CHANGING STRIP i CHANGES PART i, AND NOTHING ELSE.
    ///
    /// Four strips, and for each one all four parts are listened to. Sixteen
    /// comparisons against four baselines: the diagonal must move and every
    /// off-diagonal must not. An off-by-one anywhere in the instrument path
    /// puts the movement one row off the diagonal and this says which way.
    func testChangingOneStripsInstrumentChangesOnlyThatPart() throws {
        var baseline: [[Double]] = []
        for part in pitches.indices {
            baseline.append(try spectrumHearing(part: part, changing: nil,
                                                to: startingProgram))
        }
        // The measurement has to be able to tell the two programs apart at
        // all, or every assertion below passes for the wrong reason.
        let changedSame = try spectrumHearing(part: 0, changing: 0,
                                              to: changedProgram)
        let separation = similarity(baseline[0], changedSame)
        XCTAssertLessThan(separation, 0.95,
                          "a violin and a flute measure \(separation) alike on "
                          + "this runtime, so this suite cannot tell an "
                          + "instrument change from no change at all")

        for strip in pitches.indices {
            for part in pitches.indices {
                let heard = try spectrumHearing(part: part, changing: strip,
                                                to: changedProgram)
                let same = similarity(baseline[part], heard)
                if part == strip {
                    XCTAssertLessThan(same, 0.95,
                                      "strip \(strip)'s instrument was changed "
                                      + "and part \(part) -- its own part -- "
                                      + "sounds \(same) identical to before. "
                                      + "The change did not reach it.")
                } else {
                    XCTAssertGreaterThan(same, 0.99,
                                         "strip \(strip)'s instrument was "
                                         + "changed and part \(part) sounds "
                                         + "different (\(same)). The strip is "
                                         + "driving the wrong part.")
                }
            }
        }
    }

    /// And `applyInstruments`, the whole-mixer pass, keeps the same mapping.
    /// "Every voice on a piano" goes through a different function from the
    /// picker, and a mapping that held in one and not the other would be a
    /// mapping that held nowhere.
    func testTheWholeMixerPassKeepsTheMapping() throws {
        let parts = self.parts()
        var instruments = PlaybackInstruments()
        // One part changed, through the store the picker writes to.
        instruments.choose(program: changedProgram, bank: .melodic,
                           for: parts[2])

        for part in pitches.indices {
            let graph = PlaybackGraph()
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                       channels: 2)!
            try graph.engine.enableManualRenderingMode(.offline, format: format,
                                                       maximumFrameCount: block)
            try graph.load(midi: try fixture(), timeline: timeline(parts))
            graph.applyInstruments(instruments, parts: parts)
            var voices = PlaybackVoices()
            voices.setAll(on: false, parts: parts)
            voices.toggle(part)
            graph.apply(voices, parts: parts, metronome: false)
            let heard = spectrum(try render(graph))
            let plain = try spectrumHearing(part: part, changing: nil,
                                            to: startingProgram)
            let same = similarity(plain, heard)
            if part == 2 {
                XCTAssertLessThan(same, 0.95,
                                  "part 2 was chosen and did not change (\(same))")
            } else {
                XCTAssertGreaterThan(same, 0.99,
                                     "part 2 was chosen and part \(part) "
                                     + "changed instead (\(same))")
            }
        }
    }
}
