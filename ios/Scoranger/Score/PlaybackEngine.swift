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
///     and whether `AVAudioSequencer.tracks` includes that conductor track
///     DEPENDS ON THE FILE: omitted for quartet-playback.mid, present for
///     imate-li-vino.mid. `PlaybackGraph` measures the offset at load and
///     applies it wherever a track is looked up.
///   - A track appended AFTER loading lands after the parts, so the click is
///     always last and the part indices stay put.
///   - `currentPositionInBeats` is in quarter notes and runs through the tempo
///     map, so a mid-score tempo change needs no handling here at all.
///   - Seeking while playing works, which is what a tap on a bar does.
@MainActor
final class PlaybackEngine: ObservableObject {

    /// Playing or not: the transport's state and nothing else's.
    @Published private(set) var isPlaying = false
    /// The bar sounding right now, or nil when the play head is off the map.
    ///
    /// COMPUTED from `beat` rather than maintained beside it. It used to be a
    /// second stored property updated in the same tick, and the two drifted on
    /// screen: a screenshot caught the playhead correctly inside bar 3 while
    /// the transport still read "bar 1". One fact with two sources is the
    /// drift the design doc warns about, and the cure is that there is now
    /// only one -- the readout and the cursor cannot disagree because they are
    /// the same query.
    var soundingBar: Int? { timeline.bar(atBeat: beat) }
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
    /// Round again at the end, rather than stopping. Kept across scores like
    /// the mutes: a person practising loops everything they open.
    @Published var loop = false

    /// Which SOUND each part is played with.
    ///
    /// Read-only from outside, because every change has to reach the sampler
    /// as well as the struct and a settable property would let a caller move
    /// one without the other. Deliberately NOT kept across scores the way the
    /// mutes are: these are filed per arrangement and read back off disk on
    /// load, so opening a score restores what the reader chose FOR IT.
    @Published private(set) var instruments = PlaybackInstruments()

    /// The arrangement the choices above belong to.
    private(set) var loadedSlug: String?

    /// Injectable so the suite can point it somewhere disposable.
    private let instrumentStore: PlaybackInstrumentStore

    init(instrumentStore: PlaybackInstrumentStore = .shared) {
        self.instrumentStore = instrumentStore
    }

    /// The audio itself. Extracted so the RMS assertions can render it
    /// offline: what a listener would hear is measured in `PlaybackAudioTests`
    /// against THIS object, not against a copy of its wiring.
    private let graph = PlaybackGraph()
    private var sequencer: AVAudioSequencer? { graph.sequencer }
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
    func load(midi: URL, timeline: PlaybackTimeline, key: String,
              slug: String? = nil) throws {
        stop()
        // The reader's instrument choices are filed per ARRANGEMENT, so they
        // are read back for the slug rather than carried from whatever was
        // loaded before. A choice made on one score has nothing to say about
        // another, and a new VERSION of the same score keeps them -- which is
        // the point: transposing a bar must not reset every strip.
        if let slug {
            instruments = instrumentStore.instruments(for: slug)
            loadedSlug = slug
        }
        // Channels are keyed on INDEX, so a reader's mutes only survive into a
        // performance whose staves did not move. An op that removes a part
        // renumbers the rest, and carrying a mute across that silences an
        // instrument nobody chose. `canCarry` is the whole rule.
        if !PlaybackChannels.canCarry(from: self.timeline.parts, to: timeline.parts) {
            voices = PlaybackVoices()
        }
        self.timeline = timeline
        try activateSession()
        try graph.load(midi: midi, timeline: timeline, instruments: instruments)
        loadedKey = key
        unavailable = nil
        applyMutes()
        // A new graph means a new sequencer at rate 1. The reader's tempo has
        // to be put back on it, or every arrangement they open snaps to the
        // written tempo while the slider still says 60.
        applyTempo()
    }

    /// .playback, so a practice aid still sounds with the ring switch
    /// silenced. An iPad on a music stand is muted more often than not.
    ///
    /// Called from `load` as well as `play`: the graph starts its engine while
    /// loading, so a session that is neither playback nor active throws there
    /// -- three screens from the button, which is how the voice list once came
    /// up empty with nothing said.
    private func activateSession() throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
    }

    /// Why there is no sound, put where the reader will see it. The transport
    /// shows this in place of its controls.
    func report(unavailable reason: String?) { unavailable = reason }

    func forget() {
        stop()
        teardown()
        voices = PlaybackVoices()
        instruments = PlaybackInstruments()
        timeline = .empty
        loadedKey = nil
        loadedSlug = nil
    }

    private func teardown() { graph.teardown() }

    // MARK: - Transport

    var canPlay: Bool { sequencer != nil && !timeline.isEmpty }

    func play() {
        guard let sequencer else { return }
        do {
            try activateSession()
            if !graph.engine.isRunning { try graph.engine.start() }
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
        // The beat is LEFT where it stopped, so the readout keeps saying which
        // bar the reader stopped in rather than blanking to a dash.
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
        graph.apply(voices, parts: timeline.parts, metronome: metronome)
    }

    /// Move one channel's fader, 0-10.
    func setFader(_ value: Int, channel: Int) {
        voices.setFader(value, channel: channel)   // didSet re-applies the mixer
    }

    // MARK: - Instruments

    /// The sound a channel will be played with, chosen or guessed.
    func instrument(for part: PlaybackTimeline.Part)
        -> (program: UInt8, bank: GeneralMIDI.Bank) {
        instruments.resolved(for: part)
    }

    /// Whether the reader has an opinion about this channel, as opposed to
    /// taking the guess. The strip shows the difference.
    func hasChosenInstrument(for part: PlaybackTimeline.Part) -> Bool {
        instruments.choice(for: part) != nil
    }

    /// Put a sound on one channel.
    ///
    /// This is PLAYBACK and not notation: no version is made, no pitch moves,
    /// no clef changes. `change-instrument` in the engine is the other thing,
    /// and it is still the way to actually rewrite a part.
    ///
    /// It takes effect on the running graph -- `loadSoundBankInstrument` is
    /// per-node and each part has its own sampler -- so the transport is not
    /// restarted and the play head does not move.
    func setInstrument(program: UInt8, bank: GeneralMIDI.Bank = .melodic,
                       for part: PlaybackTimeline.Part) {
        instruments.choose(program: program, bank: bank, for: part)
        graph.setInstrument(program: program, bank: bank, channel: part.index)
        saveInstruments()
    }

    /// Back to the guess for one channel.
    func clearInstrument(for part: PlaybackTimeline.Part) {
        instruments.clear(part)
        let sound = instruments.resolved(for: part)
        graph.setInstrument(program: sound.program, bank: sound.bank,
                            channel: part.index)
        saveInstruments()
    }

    /// The whole score on one sound: "I just want to hear every voice on a
    /// piano." One pass over the samplers rather than n round trips.
    func setInstrumentEverywhere(program: UInt8,
                                 bank: GeneralMIDI.Bank = .melodic) {
        instruments.chooseAll(program: program, bank: bank, parts: timeline.parts)
        graph.applyInstruments(instruments, parts: timeline.parts)
        saveInstruments()
    }

    /// Back to the guess on every channel.
    func clearInstruments() {
        instruments.clearAll()
        graph.applyInstruments(instruments, parts: timeline.parts)
        saveInstruments()
    }

    /// Which channels could not load the sound they were given. They still
    /// play, on the sampler's own default -- refusing an arrangement because
    /// one staff is unusual is the wrong trade for a practice aid.
    var soundFailures: [Int] { graph.bankFailures }

    private func saveInstruments() {
        guard let loadedSlug else { return }
        instrumentStore.save(instruments, for: loadedSlug)
    }

    // MARK: - Tempo

    /// The tempo the reader chose, or nil to play the arrangement's own.
    ///
    /// Kept across scores, like the mutes and for the same reason: someone
    /// practising at 60 is practising at 60, and re-setting it on every
    /// arrangement they open is work the app is making for them.
    @Published private(set) var tempoOverride: Double?

    /// The tempo in force. The mixer's slider sits here and the transport
    /// prints it -- ONE value, so they cannot disagree.
    var tempoBPM: Double {
        PlaybackTempo.effective(override: tempoOverride,
                                opening: timeline.openingTempo)
    }

    /// `AVAudioSequencer` has no tempo of its own: it plays the file's tempo
    /// map scaled by `rate`, so a mid-score accelerando survives being slowed
    /// down for practice.
    func setTempo(_ bpm: Double) {
        tempoOverride = PlaybackTempo.clamp(bpm)
        applyTempo()
    }

    /// Back to whatever the arrangement says.
    func clearTempo() {
        tempoOverride = nil
        applyTempo()
    }

    private func applyTempo() {
        sequencer?.rate = Float(PlaybackTempo.rate(target: tempoBPM,
                                                   opening: timeline.openingTempo))
    }

    /// The channel captions, which are the staff labels with a display-only
    /// ordinal where a label repeats.
    var channelLabels: [String] { PlaybackChannels.labels(for: timeline.parts) }

    // MARK: - The play head

    private func startFollowing() {
        follower?.cancel()
        follower = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard let self, let sequencer = self.sequencer else { return }
                let now = sequencer.currentPositionInBeats
                // The ONE published fact. `soundingBar` is derived from it, so
                // nothing has to be kept in step with anything.
                self.beat = now
                if PlaybackSound.hasFinished(beat: now, end: self.timeline.beats) {
                    switch PlaybackSound.atEnd(loop: self.loop) {
                    case .rewind:
                        // The sequencer keeps running; only its position moves.
                        self.seek(toBeat: 0)
                    case .stop:
                        self.stop()
                        self.seek(toBeat: 0)
                        return
                    }
                }
            }
        }
    }
}
