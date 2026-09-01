import AVFoundation
import Combine
import Foundation

/// The sound of the score, and where in it the sound has got to.
///
/// Deliberately thin. Every decision this makes lives in `PlaybackSound`,
/// `PlaybackVoices` and `PlaybackTimeline`, which are pure and tested without a
/// device; what is left here is AVFoundation wiring that only a real audio
/// stack can exercise. When something about playback needs changing, check
/// whether it is a decision before adding it to this file.
///
/// The shape was measured on the iOS 26.5 runtime before it was written:
///
///   - music21 writes one MIDI track per part plus a leading conductor track,
///     and `AVAudioSequencer.tracks` OMITS the conductor track. So `tracks[i]`
///     is part `i` with nothing offset between them, which is what makes
///     muting one part a one-line operation.
///   - A track appended AFTER loading lands after the parts, so the click is
///     always last and the part indices stay put.
///   - `currentPositionInBeats` is in quarter notes and runs through the tempo
///     map, so a mid-score tempo change needs no handling here at all.
///   - Seeking while playing works, which is what a tap on a bar does.
@MainActor
final class PlaybackEngine: ObservableObject {

    /// Playing or not: the transport's state and nothing else's.
    @Published private(set) var isPlaying = false
    /// The bar sounding right now, or nil when nothing is.
    @Published private(set) var soundingBar: Int?
    /// Where the play head is, in quarter notes.
    @Published private(set) var beat: Double = 0
    /// The map being played against. Empty until something is loaded.
    @Published private(set) var timeline = PlaybackTimeline.empty
    /// Why playback is unavailable, when it is. Shown rather than swallowed:
    /// silence with no explanation reads as a broken app.
    @Published private(set) var unavailable: String?

    /// Which parts sound. Kept across scores on purpose -- a reader who has
    /// switched the melody off to practise against it keeps that while they
    /// move through the arrangement.
    @Published var voices = PlaybackVoices() { didSet { applyMutes() } }
    @Published var metronome = false { didSet { applyMutes() } }

    private let engine = AVAudioEngine()
    private var sequencer: AVAudioSequencer?
    private var samplers: [AVAudioUnitSampler] = []
    private var click: AVAudioUnitSampler?
    private var clickTrack: AVMusicTrack?
    /// Polls the play head. A task and not a display link: the bar changes a
    /// few times a second at most, and 60Hz of main-actor work to notice it
    /// would be paid on every frame of a scroll the reader is also driving.
    private var follower: Task<Void, Never>?
    private static let pollInterval = Duration.milliseconds(50)

    /// What is loaded ("<slug>/<version>"), so re-selecting the same version
    /// does not rebuild the graph underneath a score that is playing.
    private(set) var loadedKey: String?

    // MARK: - Loading

    /// Take a performed MIDI file and the map that goes with it.
    ///
    /// Throws rather than reporting, because the caller knows whether this was
    /// the reader pressing play (say so) or a prefetch (stay quiet).
    func load(midi: URL, timeline: PlaybackTimeline, key: String) throws {
        stop()
        teardown()

        self.timeline = timeline
        // One sampler per part, attached and connected BEFORE the sequencer
        // loads: a track's destination has to be part of a running graph
        // already for the sequencer to accept it.
        for part in timeline.parts {
            let sampler = AVAudioUnitSampler()
            engine.attach(sampler)
            engine.connect(sampler, to: engine.mainMixerNode, format: nil)
            loadInstrument(sampler, program: PlaybackSound.program(for: part),
                           bankMSB: PlaybackSound.melodicBankMSB)
            samplers.append(sampler)
        }
        let clickSampler = AVAudioUnitSampler()
        engine.attach(clickSampler)
        engine.connect(clickSampler, to: engine.mainMixerNode, format: nil)
        loadInstrument(clickSampler, program: PlaybackSound.clickProgram,
                       bankMSB: PlaybackSound.percussionBankMSB)
        click = clickSampler

        try engine.start()
        let loaded = AVAudioSequencer(audioEngine: engine)
        try loaded.load(from: midi, options: [])
        for (index, track) in loaded.tracks.enumerated() where index < samplers.count {
            track.destinationAudioUnit = samplers[index]
        }
        // The click is a TRACK in the same sequence, not a timer beside it.
        // That is what makes it follow the tempo map -- a mid-score change
        // included -- without a line of code here, and what makes it unable to
        // drift away from the music over the length of a movement.
        let metronomeTrack = loaded.createAndAppendTrack()
        metronomeTrack.destinationAudioUnit = clickSampler
        for tick in timeline.clicks {
            let sound = PlaybackSound.click(down: tick.down)
            metronomeTrack.addEvent(
                AVMIDINoteEvent(channel: 0, key: UInt32(sound.key),
                                velocity: UInt32(sound.velocity), duration: 0.05),
                at: AVMusicTimeStamp(tick.beat))
        }
        clickTrack = metronomeTrack

        sequencer = loaded
        loadedKey = key
        unavailable = nil
        applyMutes()
    }

    /// A part whose program will not load still plays, on the sampler's own
    /// default sound. Refusing a whole arrangement because one staff is
    /// unusual is the wrong trade for a practice aid.
    private func loadInstrument(_ sampler: AVAudioUnitSampler,
                                program: UInt8, bankMSB: UInt8) {
        try? sampler.loadSoundBankInstrument(at: PlaybackSound.bank,
                                             program: program,
                                             bankMSB: bankMSB,
                                             bankLSB: PlaybackSound.bankLSB)
    }

    func forget() {
        stop()
        teardown()
        timeline = .empty
        loadedKey = nil
    }

    private func teardown() {
        sequencer = nil
        clickTrack = nil
        for sampler in samplers { engine.detach(sampler) }
        samplers = []
        if let click { engine.detach(click) }
        click = nil
        if engine.isRunning { engine.stop() }
    }

    // MARK: - Transport

    var canPlay: Bool { sequencer != nil && !timeline.isEmpty }

    func play() {
        guard let sequencer else { return }
        do {
            // .playback, so a practice aid still sounds with the ring switch
            // silenced. An iPad on a music stand is muted more often than not.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning { try engine.start() }
            sequencer.prepareToPlay()
            try sequencer.start()
            isPlaying = true
            unavailable = nil
            startFollowing()
        } catch {
            unavailable = error.localizedDescription
            isPlaying = false
        }
    }

    func stop() {
        follower?.cancel()
        follower = nil
        sequencer?.stop()
        isPlaying = false
        soundingBar = nil
    }

    func toggle() { isPlaying ? stop() : play() }

    /// Start from a bar the reader picked, which is the FIRST time that bar is
    /// played -- see `PlaybackTimeline.firstBeat(ofBar:)`.
    func seek(toBar measure: Int) {
        guard let start = timeline.firstBeat(ofBar: measure) else { return }
        seek(toBeat: start)
    }

    func seek(toBeat target: Double) {
        guard let sequencer else { return }
        sequencer.currentPositionInBeats = target
        beat = target
        soundingBar = timeline.bar(atBeat: target)
    }

    func rewind() { seek(toBeat: 0) }

    // MARK: - Muting

    /// The parts the reader has switched off, and the metronome.
    ///
    /// Everything off is not a broken state: it is the practice case, and it
    /// leaves the click sounding alone. That is the whole reason the click is
    /// a track like any other -- silencing it is the same operation as
    /// silencing a viola.
    private func applyMutes() {
        guard let sequencer else { return }
        let muted = voices.mutedTracks(in: timeline.parts)
        for (index, track) in sequencer.tracks.enumerated()
        where index < timeline.parts.count {
            track.isMuted = muted.contains(index)
        }
        clickTrack?.isMuted = !metronome
    }

    // MARK: - The play head

    private func startFollowing() {
        follower?.cancel()
        follower = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard let self, let sequencer = self.sequencer else { return }
                let now = sequencer.currentPositionInBeats
                self.beat = now
                // Only on a CHANGE. This publishes into a view that redraws the
                // score, and republishing the same bar twenty times a second is
                // how a scrolling strip starts dropping frames.
                let bar = self.timeline.bar(atBeat: now)
                if bar != self.soundingBar { self.soundingBar = bar }
                if PlaybackSound.hasFinished(beat: now, end: self.timeline.beats) {
                    self.stop()
                    self.seek(toBeat: 0)
                    return
                }
            }
        }
    }
}
