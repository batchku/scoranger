import Foundation

/// Which parts are sounding.
///
/// Held by part NAME and never by index, for the same reason a selection is
/// held by address and not by session id: an op that removes a part renumbers
/// every part after it, and a mute keyed on a number then silences the wrong
/// instrument -- silently, which is the worst way for it to be wrong. A name
/// that no longer exists simply stops matching anything.
///
/// Switching everything off is a real state and not an error: it is how the
/// reader gets the metronome on its own, which is the practice case the whole
/// feature exists for.
struct PlaybackVoices: Equatable, Codable {

    /// The parts the reader has switched OFF. Off rather than on, so a part
    /// that appears later -- a staff pulled in from another edition -- starts
    /// sounding rather than starting silently for no stated reason.
    private(set) var silenced: Set<String> = []

    init(silenced: Set<String> = []) { self.silenced = silenced }

    func isOn(_ part: String) -> Bool { !silenced.contains(part) }

    mutating func toggle(_ part: String) {
        if silenced.contains(part) { silenced.remove(part) } else { silenced.insert(part) }
    }

    mutating func setAll(on: Bool, parts: [PlaybackTimeline.Part]) {
        silenced = on ? [] : Set(parts.map(\.name))
    }

    /// The sequencer tracks to mute, given the parts of the timeline now
    /// loaded. The index IS the track index -- music21 writes one track per
    /// part in score order and `AVAudioSequencer.tracks` omits the tempo
    /// track, so nothing is offset between them.
    func mutedTracks(in parts: [PlaybackTimeline.Part]) -> Set<Int> {
        Set(parts.filter { silenced.contains($0.name) }.map(\.index))
    }

    /// Every part off, so only the metronome is left. Asked of the PARTS the
    /// timeline actually has, because `silenced` can hold names from an
    /// earlier version of the arrangement that no longer sound anything.
    func everythingOff(in parts: [PlaybackTimeline.Part]) -> Bool {
        !parts.isEmpty && parts.allSatisfy { silenced.contains($0.name) }
    }

    func countOn(in parts: [PlaybackTimeline.Part]) -> Int {
        parts.count { !silenced.contains($0.name) }
    }

    /// What the transport says about the state, in the reader's terms.
    func summary(in parts: [PlaybackTimeline.Part]) -> String {
        guard !parts.isEmpty else { return "no parts" }
        let on = countOn(in: parts)
        if on == parts.count { return "all voices" }
        if on == 0 { return "metronome only" }
        return "\(on) of \(parts.count) voices"
    }
}
