import AVFoundation
import Foundation

/// The audio graph: samplers, the sequencer, the click track, and the volume
/// on each channel.
///
/// It lives here, beside the pure types, for one reason: **it can be rendered
/// offline.** `AVAudioEngine.enableManualRenderingMode` needs no audio session,
/// no hardware and no host app, so what a listener would hear can be measured
/// in the unit suite. Every audio claim about this app used to be structural --
/// the right objects were connected to each other -- and nobody had ever
/// checked that a sample came out. `PlaybackAudioTests` drives THIS type, so
/// the thing measured is the thing that ships.
///
/// What is NOT here: play/stop state, the sounding bar, anything published.
/// `PlaybackEngine` owns those and owns one of these.
///
/// The shape was measured on the iOS 26.5 runtime:
///
///   - music21 writes one MIDI track per part plus a leading conductor track,
///     and `AVAudioSequencer.tracks` OMITS the conductor track. So `tracks[i]`
///     is part `i`, which is what makes a channel index a track index.
///   - A track appended AFTER loading lands after the parts, so the click is
///     always last and the part indices stay put.
///   - `AVAudioUnitSampler.volume` is linear in amplitude and takes effect
///     while the graph is running, which is what a fader needs.
final class PlaybackGraph {

    let engine = AVAudioEngine()
    private(set) var sequencer: AVAudioSequencer?
    private(set) var samplers: [AVAudioUnitSampler] = []
    private(set) var clickSampler: AVAudioUnitSampler?
    private(set) var clickTrack: AVMusicTrack?
    /// Which parts failed to load a sound bank. They still play, on the
    /// sampler's own default sound; refusing a whole arrangement because one
    /// staff is unusual is the wrong trade for a practice aid.
    private(set) var bankFailures: [Int] = []

    var isLoaded: Bool { sequencer != nil }

    /// Build the graph for a performance.
    ///
    /// Order matters and is not obvious: every sampler must be attached and
    /// connected BEFORE the sequencer loads, because a track's destination has
    /// to be part of a running graph for the sequencer to accept it.
    func load(midi: URL, timeline: PlaybackTimeline) throws {
        teardown()
        for part in timeline.parts {
            let sampler = AVAudioUnitSampler()
            engine.attach(sampler)
            engine.connect(sampler, to: engine.mainMixerNode, format: nil)
            if !loadInstrument(sampler, program: PlaybackSound.program(for: part),
                               bankMSB: PlaybackSound.melodicBankMSB) {
                bankFailures.append(part.index)
            }
            samplers.append(sampler)
        }
        let click = AVAudioUnitSampler()
        engine.attach(click)
        engine.connect(click, to: engine.mainMixerNode, format: nil)
        _ = loadInstrument(click, program: PlaybackSound.clickProgram,
                           bankMSB: PlaybackSound.percussionBankMSB)
        clickSampler = click

        if !engine.isRunning { try engine.start() }
        let loaded = AVAudioSequencer(audioEngine: engine)
        try loaded.load(from: midi, options: [])
        for (index, track) in loaded.tracks.enumerated() where index < samplers.count {
            track.destinationAudioUnit = samplers[index]
        }
        // The click is a TRACK in the same sequence, not a timer beside it.
        // That is what makes it follow the tempo map -- a mid-score change
        // included -- without a line of code here, and what makes it unable to
        // drift away from the music over the length of a movement. It is also
        // what makes silencing the click the same operation as silencing a
        // viola, so one cannot accidentally do the other.
        let metronome = loaded.createAndAppendTrack()
        metronome.destinationAudioUnit = click
        for tick in timeline.clicks {
            let sound = PlaybackSound.click(down: tick.down)
            metronome.addEvent(
                AVMIDINoteEvent(channel: 0, key: UInt32(sound.key),
                                velocity: UInt32(sound.velocity), duration: 0.05),
                at: AVMusicTimeStamp(tick.beat))
        }
        clickTrack = metronome
        sequencer = loaded
    }

    @discardableResult
    private func loadInstrument(_ sampler: AVAudioUnitSampler,
                                program: UInt8, bankMSB: UInt8) -> Bool {
        do {
            try sampler.loadSoundBankInstrument(at: PlaybackSound.bank,
                                                program: program,
                                                bankMSB: bankMSB,
                                                bankLSB: PlaybackSound.bankLSB)
            return true
        } catch {
            return false
        }
    }

    func teardown() {
        sequencer?.stop()
        sequencer = nil
        clickTrack = nil
        bankFailures = []
        for sampler in samplers { engine.detach(sampler) }
        samplers = []
        if let clickSampler { engine.detach(clickSampler) }
        clickSampler = nil
        if engine.isRunning { engine.stop() }
    }

    // MARK: - The mixer

    /// Apply the whole mixer state at once.
    ///
    /// Mute and gain arrive together because they are one number to the graph
    /// (`PlaybackVoices.amplitude`). Applying them separately is how a mute
    /// gets overwritten by the next fader move.
    func apply(_ voices: PlaybackVoices, parts: [PlaybackTimeline.Part],
               metronome: Bool) {
        for part in parts where part.index < samplers.count {
            samplers[part.index].volume = Float(voices.amplitude(part.index))
        }
        // The track mute as well as the volume. Belt and braces on purpose: a
        // muted track sends no events at all, which is cheaper than rendering
        // notes at zero, and it is what makes `isMuted` readable in a test.
        if let sequencer {
            let muted = voices.mutedTracks(in: parts)
            for (index, track) in sequencer.tracks.enumerated()
            where index < parts.count {
                track.isMuted = muted.contains(index)
            }
        }
        clickTrack?.isMuted = !metronome
    }
}
