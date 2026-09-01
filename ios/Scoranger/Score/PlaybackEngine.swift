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
    func load(midi: URL, timeline: PlaybackTimeline, key: String) throws {
        stop()
        // Channels are keyed on INDEX, so a reader's mutes only survive into a
        // performance whose staves did not move. An op that removes a part
        // renumbers the rest, and carrying a mute across that silences an
        // instrument nobody chose. `canCarry` is the whole rule.
        if !PlaybackChannels.canCarry(from: self.timeline.parts, to: timeline.parts) {
            voices = PlaybackVoices()
        }
        self.timeline = timeline
        try activateSession()
        try graph.load(midi: midi, timeline: timeline)
        loadedKey = key
        unavailable = nil
        applyMutes()
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
        timeline = .empty
        loadedKey = nil
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
        graph.apply(voices, parts: timeline.parts, metronome: metronome)
    }

    /// Move one channel's fader, 0-10.
    func setFader(_ value: Int, channel: Int) {
        voices.setFader(value, channel: channel)   // didSet re-applies the mixer
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
