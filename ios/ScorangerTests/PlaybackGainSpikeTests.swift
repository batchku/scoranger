import AVFoundation
import XCTest

/// SPIKE: can a channel have its own GAIN, and can a test hear it?
///
/// Two questions the 0.6 plan turns on, neither of them answerable by reading
/// documentation:
///
///   1. `AVMusicTrack` has no gain property. The intended route is per-track
///      `destinationAudioUnit` into its own `AVAudioUnitSampler`, controlling
///      that node's volume. Does changing it actually change the audio?
///   2. Does any of this SOUND at all? The synth path has never produced a
///      sample anybody measured. `enableManualRenderingMode` renders offline
///      into a buffer, so this is a measurement rather than an anecdote.
///
/// Offline rendering also means no audio session, no hardware and no host app,
/// which is why it can live in this target.
final class PlaybackGainSpikeTests: XCTestCase {

    private let sampleRate = 44100.0
    private let block: AVAudioFrameCount = 4096

    private func fixture(_ name: String) throws -> URL {
        guard let url = Bundle(for: Self.self).url(forResource: name,
                                                   withExtension: "mid",
                                                   subdirectory: "Fixtures") else {
            throw XCTSkip("fixture \(name).mid is not in the test bundle")
        }
        return url
    }

    /// The whole graph the app builds, wired for offline rendering.
    private struct Rig {
        let engine: AVAudioEngine
        let sequencer: AVAudioSequencer
        let samplers: [AVAudioUnitSampler]
        let bankLoaded: [Bool]
    }

    private func rig(_ fixtureName: String, parts: Int) throws -> Rig {
        let engine = AVAudioEngine()
        var samplers: [AVAudioUnitSampler] = []
        var loaded: [Bool] = []
        for _ in 0..<parts {
            let sampler = AVAudioUnitSampler()
            engine.attach(sampler)
            engine.connect(sampler, to: engine.mainMixerNode, format: nil)
            do {
                try sampler.loadSoundBankInstrument(at: PlaybackSound.bank,
                                                    program: 40,
                                                    bankMSB: PlaybackSound.melodicBankMSB,
                                                    bankLSB: PlaybackSound.bankLSB)
                loaded.append(true)
            } catch {
                loaded.append(false)
            }
            samplers.append(sampler)
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: format,
                                             maximumFrameCount: block)
        let sequencer = AVAudioSequencer(audioEngine: engine)
        try sequencer.load(from: try fixture(fixtureName), options: [])
        for (index, track) in sequencer.tracks.enumerated() where index < samplers.count {
            track.destinationAudioUnit = samplers[index]
        }
        return Rig(engine: engine, sequencer: sequencer,
                   samplers: samplers, bankLoaded: loaded)
    }

    /// Render `seconds` of audio and return its RMS.
    private func render(_ rig: Rig, seconds: Double) throws -> Double {
        try rig.engine.start()
        rig.sequencer.prepareToPlay()
        try rig.sequencer.start()

        let buffer = AVAudioPCMBuffer(pcmFormat: rig.engine.manualRenderingFormat,
                                      frameCapacity: block)!
        let target = AVAudioFramePosition(seconds * sampleRate)
        var sum = 0.0
        var counted = 0
        while rig.engine.manualRenderingSampleTime < target {
            let remaining = target - rig.engine.manualRenderingSampleTime
            let frames = AVAudioFrameCount(min(AVAudioFramePosition(block), remaining))
            let status = try rig.engine.renderOffline(frames, to: buffer)
            guard status == .success else { break }
            guard let channels = buffer.floatChannelData else { break }
            for channel in 0..<Int(buffer.format.channelCount) {
                let samples = channels[channel]
                for frame in 0..<Int(buffer.frameLength) {
                    let value = Double(samples[frame])
                    sum += value * value
                    counted += 1
                }
            }
        }
        rig.sequencer.stop()
        rig.engine.stop()
        return counted > 0 ? (sum / Double(counted)).squareRoot() : 0
    }

    /// Q0, and everything else depends on it: does the bundled General MIDI
    /// bank load, and does the sequencer advance while the engine is rendering
    /// offline? Either answer being no would sink the whole approach.
    func testTheSynthActuallyMakesASound() throws {
        let rig = try rig("quartet-playback", parts: 4)
        XCTAssertEqual(rig.bankLoaded, [true, true, true, true],
                       "the General MIDI bank at \(PlaybackSound.bank.path) did not load")
        let rms = try render(rig, seconds: 2.0)
        print("SPIKE full-volume RMS = \(rms)")
        XCTAssertGreaterThan(rms, 1e-4, "the graph rendered silence")
    }

    /// Q1: per-channel gain, via the sampler node's own mixer volume.
    func testAChannelsVolumeChangesWhatIsRendered() throws {
        let loud = try rig("quartet-playback", parts: 4)
        let loudRMS = try render(loud, seconds: 2.0)

        let quiet = try rig("quartet-playback", parts: 4)
        for sampler in quiet.samplers { sampler.volume = 0.25 }
        let quietRMS = try render(quiet, seconds: 2.0)

        print("SPIKE volume: loud = \(loudRMS), quarter = \(quietRMS), "
              + "ratio = \(loudRMS > 0 ? quietRMS / loudRMS : -1)")
        XCTAssertGreaterThan(loudRMS, 1e-4, "nothing to turn down")
        XCTAssertLessThan(quietRMS, loudRMS * 0.6,
                          "AVAudioMixing.volume on the sampler node did nothing")
    }

    /// Q1b: the other candidate, in case the mixer volume is the one that does
    /// nothing. Reported either way so the owner sees both.
    func testTheSamplersOwnGainAlsoChangesWhatIsRendered() throws {
        let loud = try rig("quartet-playback", parts: 4)
        let loudRMS = try render(loud, seconds: 2.0)

        let quiet = try rig("quartet-playback", parts: 4)
        for sampler in quiet.samplers { sampler.overallGain = -20 }
        let quietRMS = try render(quiet, seconds: 2.0)

        print("SPIKE overallGain: loud = \(loudRMS), -20dB = \(quietRMS), "
              + "ratio = \(loudRMS > 0 ? quietRMS / loudRMS : -1)")
        XCTAssertLessThan(quietRMS, loudRMS * 0.6,
                          "AVAudioUnitSampler.overallGain did nothing")
    }

    /// The way the mixer will actually use it: a fader moved WHILE the music
    /// is running. A volume that only takes effect before `start` would make
    /// every strip in the panel feel broken.
    func testAFaderMovedDuringPlaybackTakesEffectImmediately() throws {
        let rig = try rig("quartet-playback", parts: 4)
        try rig.engine.start()
        rig.sequencer.prepareToPlay()
        try rig.sequencer.start()

        let first = try renderMore(rig, seconds: 1.0)
        for sampler in rig.samplers { sampler.volume = 0.25 }
        let second = try renderMore(rig, seconds: 1.0)
        rig.sequencer.stop()
        rig.engine.stop()

        print("SPIKE live fader: before = \(first), after = \(second), "
              + "ratio = \(first > 0 ? second / first : -1)")
        XCTAssertGreaterThan(first, 1e-4, "nothing was playing to turn down")
        XCTAssertLessThan(second, first * 0.6,
                          "moving the fader mid-playback changed nothing")
    }

    /// Render from wherever the engine already is, without restarting it.
    private func renderMore(_ rig: Rig, seconds: Double) throws -> Double {
        let buffer = AVAudioPCMBuffer(pcmFormat: rig.engine.manualRenderingFormat,
                                      frameCapacity: block)!
        let target = rig.engine.manualRenderingSampleTime
            + AVAudioFramePosition(seconds * sampleRate)
        var sum = 0.0
        var counted = 0
        while rig.engine.manualRenderingSampleTime < target {
            let remaining = target - rig.engine.manualRenderingSampleTime
            let frames = AVAudioFrameCount(min(AVAudioFramePosition(block), remaining))
            let status = try rig.engine.renderOffline(frames, to: buffer)
            guard status == .success, let channels = buffer.floatChannelData else { break }
            for channel in 0..<Int(buffer.format.channelCount) {
                let samples = channels[channel]
                for frame in 0..<Int(buffer.frameLength) {
                    let value = Double(samples[frame])
                    sum += value * value
                    counted += 1
                }
            }
        }
        return counted > 0 ? (sum / Double(counted)).squareRoot() : 0
    }

    /// And that the gain is PER CHANNEL, not a master. Turning one of four
    /// down must move the total, but not to a quarter of it.
    func testTurningOneChannelDownIsNotTurningAllOfThemDown() throws {
        let all = try rig("quartet-playback", parts: 4)
        let allRMS = try render(all, seconds: 2.0)

        let one = try rig("quartet-playback", parts: 4)
        one.samplers[0].volume = 0
        let oneRMS = try render(one, seconds: 2.0)

        print("SPIKE per-channel: all = \(allRMS), one silenced = \(oneRMS)")
        XCTAssertLessThan(oneRMS, allRMS, "silencing one channel changed nothing")
        XCTAssertGreaterThan(oneRMS, allRMS * 0.2,
                             "silencing one channel silenced more than one")
    }
}
