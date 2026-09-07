import Accelerate
import AVFoundation
import XCTest

/// A flute does not sound like a piano.
///
/// Every audio assertion in this app measured a LEVEL: something came out, it
/// was quieter with the fader down, it stopped when muted. None of them could
/// tell WHICH sound made it, and that blind spot is exactly the shape of the
/// bug Ali reported -- "all playback is using the same synth; it sounds like
/// pure sinusoids; changing instruments does nothing." Every one of those
/// tests passed while it was true on his iPad.
///
/// So this suite measures the SPECTRUM. One note, one key, one velocity, two
/// programs: if the two renders have the same harmonic content, they are the
/// same sound whatever the meter says.
///
/// **The control is the point.** A difference metric nobody has watched go to
/// zero proves nothing, so every assertion here is bracketed:
///
///   - the same program rendered twice must come out IDENTICAL (the metric
///     sees no difference where there is none), and
///   - `testASamplerWithNoBankIsWhatTheBugSoundedLike` reproduces the fault
///     itself -- two different programs on a sampler with no bank loaded --
///     and asserts they collapse to one tone. That is the failure this suite
///     would have caught, measured rather than described.
///
/// Rendered offline through `AVAudioEngine.enableManualRenderingMode`: no
/// audio session, no hardware, no host app.
///
/// It cannot replace `PlaybackBankTests`, and the two are not alternatives. In
/// the SIMULATOR the old code loaded Apple's bank straight off the host Mac's
/// filesystem, so the timbres were real and this suite would have passed on
/// it. Only "the app may not depend on a file it does not carry" fails there.
final class PlaybackTimbreTests: XCTestCase {

    private let sampleRate = 44100.0
    private let block: AVAudioFrameCount = 4096
    /// The window analysed: 4096 samples is 93ms and 10.8Hz bins at 44.1kHz,
    /// which resolves the partials of a note in the middle of the keyboard.
    private let window = 4096
    /// Two spectra this alike are one sound. The failure this suite exists
    /// for measures 1.0 exactly -- a sampler with no bank answers every
    /// program with the same buffer -- so identity is what has to be refused.
    private let same = 0.99
    /// Taken 100ms in, past the attack. A piano's hammer noise and a flute's
    /// breath differ so violently that comparing attacks would pass on two
    /// programs whose sustained tone was identical.
    private let skip = 4410

    // MARK: - Rendering one note

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

    private func timeline(parts: [PlaybackTimeline.Part]) -> PlaybackTimeline {
        let bars = stride(from: 0.0, to: 16.0, by: 4).map {
            PlaybackTimeline.Bar(measure: Int($0 / 4) + 1, start: $0, end: $0 + 4)
        }
        return PlaybackTimeline(parts: parts, bars: bars, clicks: [],
                                tempos: [.init(beat: 0, bpm: 120)])
    }

    /// The graph that ships, in manual rendering mode, transport never started
    /// -- the notes here are played straight at a sampler so the only sound in
    /// the buffer is the one under test.
    private func graph() throws -> PlaybackGraph {
        let graph = PlaybackGraph()
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                   channels: 2)!
        try graph.engine.enableManualRenderingMode(.offline, format: format,
                                                   maximumFrameCount: block)
        let parts = quartet()
        try graph.load(midi: try fixture("quartet-playback"),
                       timeline: timeline(parts: parts))
        graph.apply(PlaybackVoices(), parts: parts, metronome: false)
        if !graph.engine.isRunning { try graph.engine.start() }
        return graph
    }

    /// Render `frames` of the left channel into an array.
    private func samples(_ engine: AVAudioEngine, frames: Int) throws -> [Float] {
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                      frameCapacity: block)!
        var out: [Float] = []
        out.reserveCapacity(frames)
        while out.count < frames {
            let want = AVAudioFrameCount(min(Int(block), frames - out.count))
            let status = try engine.renderOffline(want, to: buffer)
            guard status == .success, let channels = buffer.floatChannelData else { break }
            out.append(contentsOf: UnsafeBufferPointer(start: channels[0],
                                                       count: Int(buffer.frameLength)))
        }
        return out
    }

    /// One note on one sampler, sampled past its attack.
    ///
    /// All-sound-off (controller 120) first: a sampler's tail is long, and a
    /// church organ still ringing from the previous program would be measured
    /// as part of the next one.
    private func note(_ engine: AVAudioEngine, on sampler: AVAudioUnitSampler,
                      key: UInt8 = 60, velocity: UInt8 = 100) throws -> [Float] {
        sampler.sendController(120, withValue: 0, onChannel: 0)
        _ = try samples(engine, frames: 2048)
        sampler.startNote(key, withVelocity: velocity, onChannel: 0)
        let rendered = try samples(engine, frames: skip + window)
        sampler.stopNote(key, onChannel: 0)
        sampler.sendController(120, withValue: 0, onChannel: 0)
        _ = try samples(engine, frames: 2048)
        return Array(rendered.dropFirst(skip).prefix(window))
    }

    // MARK: - The spectrum

    /// Magnitude spectrum of a Hann-windowed real signal, via Accelerate.
    /// Hann because a note is not periodic in 4096 samples and the leakage of
    /// a rectangular window smears the partials this test is looking at.
    /// Loudness, for "did this channel go silent" rather than "did its timbre
    /// change". A channel left disconnected is not a different sound; it is no
    /// sound, and similarity cannot tell the difference.
    private func rms(_ signal: [Float]) -> Double {
        guard !signal.isEmpty else { return 0 }
        let sum = signal.reduce(0.0) { $0 + Double($1) * Double($1) }
        return (sum / Double(signal.count)).squareRoot()
    }

    private func spectrum(_ signal: [Float]) -> [Double] {
        let n = window
        var input = signal
        if input.count < n { input += [Float](repeating: 0, count: n - input.count) }
        input = Array(input.prefix(n))

        var hann = [Float](repeating: 0, count: n)
        vDSP_hann_window(&hann, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(input, 1, hann, 1, &input, 1, vDSP_Length(n))

        let half = n / 2
        let log2n = vDSP_Length(log2(Double(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return []
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!,
                                            imagp: imaginaryPointer.baseAddress!)
                input.withUnsafeBufferPointer { raw in
                    raw.baseAddress!.withMemoryRebound(to: DSPComplex.self,
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

    /// How alike two spectra are, as the cosine of the angle between them:
    /// 1 is the same shape, 0 shares no partial.
    ///
    /// The SHAPE and not the level, deliberately. Two programs at different
    /// volumes are still two sounds, and a metric that could be satisfied by
    /// turning one down would be measuring the fader again.
    private func similarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return .nan }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for (x, y) in zip(a, b) {
            dot += x * y
            normA += x * x
            normB += y * y
        }
        guard normA > 0, normB > 0 else { return .nan }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }

    /// The centre of mass of the spectrum, in Hz -- roughly, how bright the
    /// sound is. Reported rather than asserted against a fixed number: it is
    /// the readable summary of a 2048-bin vector, and a bank is allowed to
    /// voice its flute differently than the next bank does.
    private func centroid(_ magnitudes: [Double]) -> Double {
        var weighted = 0.0, total = 0.0
        for (bin, magnitude) in magnitudes.enumerated() {
            weighted += Double(bin) * magnitude
            total += magnitude
        }
        guard total > 0 else { return 0 }
        return weighted / total * (sampleRate / Double(window))
    }

    private func energy(_ signal: [Float]) -> Double {
        guard !signal.isEmpty else { return 0 }
        let sum = signal.reduce(0.0) { $0 + Double($1) * Double($1) }
        return (sum / Double(signal.count)).squareRoot()
    }

    // MARK: - The control: the metric can see nothing

    /// The same program, twice, on the same sampler. If this is not 1 then
    /// every number below is render noise and the suite proves nothing.
    func testTheSameProgramRenderedTwiceIsTheSameSpectrum() throws {
        let graph = try graph()
        XCTAssertTrue(graph.setInstrument(program: 0, bank: .melodic, channel: 0))
        let first = spectrum(try note(graph.engine, on: graph.samplers[0]))
        let second = spectrum(try note(graph.engine, on: graph.samplers[0]))
        XCTAssertGreaterThan(energy(try note(graph.engine, on: graph.samplers[0])),
                             1e-4, "there is nothing here to compare")
        XCTAssertEqual(similarity(first, second), 1.0, accuracy: 1e-6,
                       "a program compared with itself must be identical, or "
                       + "the difference measured below is the renderer")
    }

    // MARK: - Two programs are two sounds

    /// The one Ali's report comes down to. Flute and piano, same key, same
    /// velocity, same sampler, same graph: different sound.
    ///
    /// 0.9 is not a tuned threshold, it is a wide one. Measured on the
    /// bundled bank these two come out at 0.665 -- centroids 4442Hz and
    /// 1297Hz, a struck string against a breathy near-fundamental -- and two
    /// programs above 0.9 would be the same patch under two names.
    func testAFluteAndAPianoDoNotRenderTheSameSpectrum() throws {
        let graph = try graph()
        let sampler = graph.samplers[0]

        XCTAssertTrue(graph.setInstrument(program: 0, bank: .melodic, channel: 0))
        let piano = spectrum(try note(graph.engine, on: sampler))
        XCTAssertTrue(graph.setInstrument(program: 73, bank: .melodic, channel: 0))
        let flute = spectrum(try note(graph.engine, on: sampler))

        XCTAssertLessThan(similarity(piano, flute), 0.9,
                          "Acoustic Grand Piano and Flute render the same "
                          + "spectrum, which is what a sampler with no bank "
                          + "loaded does")
        print("    piano centroid \(Int(centroid(piano)))Hz, "
              + "flute centroid \(Int(centroid(flute)))Hz, "
              + "similarity \(String(format: "%.3f", similarity(piano, flute)))")
    }

    /// And not one lucky pair. Eight programs from eight General MIDI
    /// families, every pair compared: 28 comparisons, none of them the same
    /// sound. A bank that had loaded only its piano would pass the test above
    /// by comparing a piano against a fallback tone.
    ///
    /// The bar here is `same` -- 0.99, near-identity -- and NOT the 0.9 the
    /// flute/piano pair clears, because a wider bar would be a claim that is
    /// not true. Violin and Flute at C4 measure 0.886: two sustained,
    /// fundamental-dominant tones ARE spectrally close, and a threshold tuned
    /// until they came apart would be a threshold chosen to pass. What this
    /// asserts is the thing the bug violated -- eight programs must not be one
    /// sound -- and the bug's own measurement is 1.0 exactly, so near-identity
    /// is where the line belongs. The worst of the 28 is printed on every run,
    /// which is the honest way to show the headroom rather than describe it.
    ///
    /// A harmonic-profile metric was tried here first and was WORSE at this
    /// (Violin/Flute 0.918, and Church Organ/Flute over 0.9 as well) --
    /// normalising twelve partials to the loudest leaves both vectors led by
    /// a 1.0, which is most of the similarity. Recorded so the next person
    /// does not spend the afternoon rediscovering it.
    func testEightFamiliesRenderEightDifferentSpectra() throws {
        let graph = try graph()
        let sampler = graph.samplers[0]
        let chosen: [UInt8] = [
            0,    // Acoustic Grand Piano
            19,   // Church Organ
            24,   // Acoustic Guitar (nylon)
            40,   // Violin
            56,   // Trumpet
            71,   // Clarinet
            73,   // Flute
            114,  // Steel Drums
        ]
        var spectra: [(UInt8, [Double])] = []
        for program in chosen {
            XCTAssertTrue(graph.setInstrument(program: program, bank: .melodic,
                                              channel: 0),
                          "\(GeneralMIDI.name(program: program)) would not load")
            let signal = try note(graph.engine, on: sampler)
            XCTAssertGreaterThan(energy(signal), 1e-4,
                                 "\(GeneralMIDI.name(program: program)) is silent")
            spectra.append((program, spectrum(signal)))
        }

        var alike: [String] = []
        var worst = (score: 0.0, pair: "")
        for i in spectra.indices {
            for j in spectra.indices where j > i {
                let score = similarity(spectra[i].1, spectra[j].1)
                let pair = "\(GeneralMIDI.name(program: spectra[i].0)) ~ "
                    + "\(GeneralMIDI.name(program: spectra[j].0))"
                if score >= same {
                    alike.append("\(pair) (\(String(format: "%.3f", score)))")
                }
                if score > worst.score { worst = (score, pair) }
            }
        }
        XCTAssertEqual(alike, [], "these render as the same sound")
        for (program, magnitudes) in spectra {
            print("    \(GeneralMIDI.name(program: program)): "
                  + "centroid \(Int(centroid(magnitudes)))Hz")
        }
        print("    closest of the 28 pairs: \(worst.pair) at "
              + "\(String(format: "%.3f", worst.score))")
    }

    // MARK: - A program change reaches the air

    /// The other half of Ali's report: "changing instruments does nothing."
    /// One sampler, one key, a program change between the two notes.
    /// Changing instrument on a RUNNING graph leaves the channel audible and
    /// re-patched.
    ///
    /// The crash this guards (TestFlight 0.6.14 build 173, "Crash on
    /// playback") was a dangling sample pointer: `loadSoundBankInstrument`
    /// replaced the buffers a sounding voice was walking. The fix stops the
    /// sequencer for the length of the load (`PlaybackGraph.reseat`), and the
    /// two ways to get that wrong are both silent failures -- a channel taken
    /// out of the graph and not put back, or a transport that never resumes.
    ///
    /// It fails 22 assertions across this suite against a channel left
    /// disconnected. It does NOT fail against the code that crashed: manual
    /// rendering pulls frames on this thread, so there is no concurrent render
    /// to race with and the fault cannot be reproduced here. The ordering is
    /// what is asserted; the race is what the ordering removes.
    func testChangingInstrumentWhileRunningKeepsTheChannelAudible() throws {
        let graph = try graph()
        // The sequencer must be PLAYING, or `reseat` takes its stopped-graph
        // path and this measures the plain load instead of the fix.
        graph.sequencer?.prepareToPlay()
        try graph.sequencer?.start()
        XCTAssertEqual(graph.sequencer?.isPlaying, true,
                       "the live path is the one under test")

        XCTAssertTrue(graph.setInstrument(program: 40, bank: .melodic, channel: 0))
        let violin = try note(graph.engine, on: graph.samplers[0])
        XCTAssertGreaterThan(rms(violin), 0.0001, "the violin should sound at all")

        XCTAssertTrue(graph.setInstrument(program: 47, bank: .melodic, channel: 0))
        let timpani = try note(graph.engine, on: graph.samplers[0])

        XCTAssertGreaterThan(rms(timpani), 0.0001,
                             "the channel went silent after a live change")
        XCTAssertLessThan(similarity(spectrum(violin), spectrum(timpani)), 0.9,
                          "the reload did not take effect on a running graph")
    }

    /// Many changes in a row, on every channel, while the graph runs.
    ///
    /// One change can pass by luck. This walks the picker the way a reader
    /// hunting for a sound does and asserts every channel is still audible at
    /// the end -- a leaked disconnect or a sequencer that stopped shows up here
    /// as a dead channel rather than as a crash on somebody's iPhone.
    func testRepeatedLiveInstrumentChangesLeaveEveryChannelAudible() throws {
        let graph = try graph()
        graph.sequencer?.prepareToPlay()
        try graph.sequencer?.start()
        XCTAssertEqual(graph.sequencer?.isPlaying, true,
                       "the live path is the one under test")
        let programs: [UInt8] = [0, 40, 47, 73, 24, 56, 12]
        for channel in graph.samplers.indices {
            for program in programs {
                XCTAssertTrue(graph.setInstrument(program: program, bank: .melodic,
                                                  channel: channel),
                              "program \(program) refused on channel \(channel)")
                _ = try note(graph.engine, on: graph.samplers[channel])
            }
        }
        for channel in graph.samplers.indices {
            XCTAssertGreaterThan(rms(try note(graph.engine, on: graph.samplers[channel])),
                                 0.0001,
                                 "channel \(channel) is silent after "
                                 + "\(programs.count) live changes")
        }
    }

    /// A program change does NOT re-patch this sampler, bank loaded or not.
    /// Measured, because it is the obvious fix for the 0.6.14 crash and it does
    /// not work: `loadSoundBankInstrument` pins one preset per unit, so a
    /// picker wired to a program change would silently do nothing.
    ///
    /// This is a record of the platform's behaviour, and it is meant to fail if
    /// that behaviour ever changes -- at which point `PlaybackGraph.reseat` can
    /// stop pausing the sequencer and the music need not hesitate at all.
    func testAProgramChangeDoesNotRePatchALoadedSampler() throws {
        let graph = try graph()
        XCTAssertTrue(graph.setInstrument(program: 40, bank: .melodic, channel: 0))
        let loaded = spectrum(try note(graph.engine, on: graph.samplers[0]))

        graph.samplers[0].sendProgramChange(47, bankMSB: GeneralMIDI.Bank.melodic.msb,
                                            bankLSB: PlaybackSound.bankLSB,
                                            onChannel: 0)
        XCTAssertEqual(similarity(loaded, spectrum(try note(graph.engine,
                                                            on: graph.samplers[0]))),
                       1.0, accuracy: 1e-6,
                       "bank-select program change re-patched the sampler -- if this "
                       + "now works, reseat can go back to a program change")

        graph.samplers[0].sendProgramChange(47, onChannel: 0)
        XCTAssertEqual(similarity(loaded, spectrum(try note(graph.engine,
                                                            on: graph.samplers[0]))),
                       1.0, accuracy: 1e-6,
                       "plain program change re-patched the sampler")
    }

    func testAProgramChangeChangesWhatComesOut() throws {
        let graph = try graph()
        let sampler = graph.samplers[0]
        XCTAssertTrue(graph.setInstrument(program: 40, bank: .melodic, channel: 0))
        let before = spectrum(try note(graph.engine, on: sampler))
        XCTAssertTrue(graph.setInstrument(program: 47, bank: .melodic, channel: 0))
        let after = spectrum(try note(graph.engine, on: sampler))
        XCTAssertLessThan(similarity(before, after), 0.9,
                          "a Violin re-patched to Timpani sounds the same")
    }

    /// And through the type the mixer actually calls, on the parts a score
    /// arrives with, rather than through `setInstrument` directly: "every
    /// voice on a piano" has to reach every channel.
    func testTheMixersOwnPathRepatchesEveryChannel() throws {
        let graph = try graph()
        let parts = quartet()

        // As loaded: the two violins share program 40, the viola is 41.
        let violin = spectrum(try note(graph.engine, on: graph.samplers[0]))
        let viola = spectrum(try note(graph.engine, on: graph.samplers[2]))
        XCTAssertLessThan(similarity(violin, viola), 0.99,
                          "Violin and Viola arrived on the same patch")

        var instruments = PlaybackInstruments()
        instruments.chooseAll(program: 47, parts: parts)  // Timpani, on everything
        graph.applyInstruments(instruments, parts: parts)

        var changed: [Int] = []
        for part in parts {
            let after = spectrum(try note(graph.engine, on: graph.samplers[part.index]))
            let was = part.index == 2 ? viola : violin
            if similarity(was, after) >= 0.9 { changed.append(part.index) }
        }
        XCTAssertEqual(changed, [],
                       "these channels kept their old sound after every "
                       + "staff was put on one program")
    }

    // MARK: - The bug itself, measured

    /// **What the iPad was doing.** An `AVAudioUnitSampler` with no instrument
    /// loaded is what the old absolute macOS bank path produced on a device,
    /// and this is the sound it made: one built-in tone, the same on every
    /// channel, unmoved by a program change.
    ///
    /// This is the assertion that gives the numbers above their meaning. The
    /// similarity metric goes to 1.0 here and to 0.665 for two real programs,
    /// so it is measuring the thing it claims to measure.
    ///
    /// It also names the fallback rather than repeating Ali's word for it, and
    /// the measurement agrees with him: on key 60 the fallback's spectral
    /// centroid is 266Hz against a fundamental of 261.6Hz. Essentially all of
    /// its energy is in the first partial. It is a sine wave.
    func testASamplerWithNoBankIsWhatTheBugSoundedLike() throws {
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                   channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: format,
                                             maximumFrameCount: block)
        // No bank, no patch. Exactly the state loadSoundBankInstrument left
        // these in on a device when it threw.
        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        try engine.start()

        sampler.sendProgramChange(0, onChannel: 0)
        let asPiano = try note(engine, on: sampler)
        sampler.sendProgramChange(73, onChannel: 0)
        let asFlute = try note(engine, on: sampler)

        // Whatever this tone is, a program change does not touch it. That is
        // the whole bug: an instrument picker wired to a sampler that has
        // nothing to pick from.
        XCTAssertEqual(similarity(spectrum(asPiano), spectrum(asFlute)), 1.0,
                       accuracy: 1e-6,
                       "an unloaded sampler answered a program change -- then "
                       + "the fallback tone is not what Ali heard and this "
                       + "test no longer describes the bug")

        let unloaded = spectrum(asPiano)
        print("    with no bank loaded: rms \(String(format: "%.5f", energy(asPiano))), "
              + "centroid \(Int(centroid(unloaded)))Hz "
              + "(identical before and after a program change)")

        // And against the fix, on the same key: the bundled bank does not
        // sound like this. Not a threshold, a demonstration -- the two
        // measurements meet here, which is what makes the pair a proof.
        let real = try graph()
        XCTAssertTrue(real.setInstrument(program: 73, bank: .melodic, channel: 0))
        let bundledFlute = spectrum(try note(real.engine, on: real.samplers[0]))
        XCTAssertLessThan(similarity(unloaded, bundledFlute), 0.9,
                          "the bundled bank's Flute is the same sound as a "
                          + "sampler with no bank at all")
    }
}
