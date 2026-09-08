import Foundation

/// Which channels sound, and how loudly.
///
/// Keyed on the part's INDEX, not on its name. Names are what the page calls
/// the staves and they are allowed to repeat -- optical recognition labels
/// every unlabeled staff "Voice", so a scanned quartet is four parts with one
/// name between them. A name-keyed mute made that a single switch that
/// silenced the whole score. The index is unique by construction and is also
/// the sequencer track number, so it is the one identifier that is true of
/// exactly one channel.
///
/// The cost, stated plainly: an op that REMOVES a part renumbers everything
/// after it, so a mute can end up on a different instrument than the one it was
/// put on. That is why `PlaybackEngine` clears the mutes when the score being
/// listened to changes rather than carrying them across.
///
/// Switching everything off is a real state and not an error: it is how the
/// reader gets the metronome on its own, and with the metronome off too it is
/// silence -- allowed, because the playhead still shows where the music is.
struct PlaybackVoices: Equatable, Codable {

    /// The channels the reader has switched OFF. Off rather than on, so a part
    /// that appears later starts sounding rather than starting silently for no
    /// stated reason.
    private(set) var silenced: Set<Int> = []

    /// Fader positions, 0-10. Absent means the default; storing only what has
    /// been moved keeps "untouched" and "set back to 7" the same state.
    private(set) var faders: [Int: Int] = [:]

    init(silenced: Set<Int> = [], faders: [Int: Int] = [:]) {
        self.silenced = silenced
        self.faders = faders
    }

    func isOn(_ channel: Int) -> Bool { !silenced.contains(channel) }

    mutating func toggle(_ channel: Int) {
        if silenced.contains(channel) { silenced.remove(channel) }
        else { silenced.insert(channel) }
    }

    mutating func setAll(on: Bool, parts: [PlaybackTimeline.Part]) {
        silenced = on ? [] : Set(parts.map(\.index))
    }

    /// Where a channel's fader is sitting.
    func fader(_ channel: Int) -> Int {
        faders[channel] ?? PlaybackGain.defaultFader
    }

    mutating func setFader(_ value: Int, channel: Int) {
        faders[channel] = min(max(value, PlaybackGain.minimumFader),
                              PlaybackGain.maximumFader)
    }

    /// What the audio graph is actually given for this channel.
    ///
    /// Mute and fader are ONE number here on purpose. They are two controls to
    /// a reader, but the graph has a single volume per node, and deciding
    /// between them at the call site is how one of them ends up quietly
    /// winning. A muted channel is zero whatever its fader says, and the fader
    /// keeps its position so unmuting returns it to where it was.
    func amplitude(_ channel: Int) -> Double {
        isOn(channel) ? PlaybackGain.amplitude(for: fader(channel)) : 0
    }

    /// The sequencer tracks to mute. The index IS the track index: music21
    /// writes one track per part in score order and `AVAudioSequencer.tracks`
    /// omits the conductor track, so nothing is offset between them.
    func mutedTracks(in parts: [PlaybackTimeline.Part]) -> Set<Int> {
        Set(parts.map(\.index).filter { silenced.contains($0) })
    }

    /// Every channel off, so only the metronome is left -- or silence, if that
    /// is off too. Asked of the PARTS the timeline has, because `silenced` can
    /// hold indices from a longer arrangement.
    func everythingOff(in parts: [PlaybackTimeline.Part]) -> Bool {
        !parts.isEmpty && parts.allSatisfy { silenced.contains($0.index) }
    }

    func countOn(in parts: [PlaybackTimeline.Part]) -> Int {
        parts.count { !silenced.contains($0.index) }
    }

    /// What the transport says about the state, in the reader's terms.
    ///
    /// The metronome is part of the answer because the question the label
    /// answers is "what will I hear". Every voice off with the click off is
    /// not "metronome only"; it is silence, and a reader told otherwise goes
    /// looking for a broken speaker.
    func summary(in parts: [PlaybackTimeline.Part], metronome: Bool) -> String {
        guard !parts.isEmpty else { return "no parts" }
        let on = countOn(in: parts)
        if on == parts.count { return "all voices" }
        if on == 0 { return metronome ? "metronome only" : "silent" }
        return "\(on) of \(parts.count) voices"
    }

    /// The line under the voice list: how to reach the practice case, or what
    /// is wrong with the state the reader has just built.
    func advice(in parts: [PlaybackTimeline.Part], metronome: Bool) -> String {
        guard everythingOff(in: parts) else {
            return "turn every voice off to play along to the click"
        }
        return metronome ? "the metronome plays alone"
                         : "nothing will sound: switch the metronome on"
    }
}

/// What a channel strip is CALLED.
///
/// Exactly what the staff is called on the page -- decision of record: a strip
/// named something the staff is not cannot be matched to a staff. But four
/// strips reading "Voice" cannot be told apart either, so where a label
/// repeats, and only there, a display-only ordinal is appended.
///
/// Display-only is the whole point: nothing is keyed on this string. The
/// channel is its index, the mute is its index, the track is its index. This
/// is a caption.
enum PlaybackChannels {

    /// What each strip is CALLED, given that two staves can share a name.
    ///
    /// A grand staff is one MusicXML part; music21 splits it into two staves
    /// and both answer "Piano". The engine reports the name exactly as the
    /// page spells it, duplicates and all, on purpose -- a strip that calls
    /// itself something the page does not is a strip nobody can match to a
    /// staff. So the disambiguation happens here, in the display.
    ///
    /// By CLEF where the clefs differ, because that is what the reader sees:
    /// "Piano · treble" and "Piano · bass" name the two halves of a grand
    /// staff the way a musician would. By ordinal only where they do not --
    /// two "Voice" staves both in treble are genuinely alike, and 1 and 2 at
    /// least say which is higher up the page.
    ///
    /// The NAME is untouched either way: `canCarry` and every op still compare
    /// what the engine reported.
    static func labels(for parts: [PlaybackTimeline.Part]) -> [String] {
        var total: [String: Int] = [:]
        for part in parts { total[part.name, default: 0] += 1 }

        // Within one repeated name, is the clef enough to tell them apart?
        var clefsFor: [String: [String?]] = [:]
        for part in parts { clefsFor[part.name, default: []].append(part.clef) }
        var clefDistinguishes: [String: Bool] = [:]
        for (name, clefs) in clefsFor {
            let named = clefs.compactMap { $0 }
            clefDistinguishes[name] = named.count == clefs.count
                && Set(named).count == clefs.count
        }

        var seen: [String: Int] = [:]
        return parts.map { part in
            guard (total[part.name] ?? 0) > 1 else { return part.name }
            seen[part.name, default: 0] += 1
            if clefDistinguishes[part.name] == true, let clef = part.clef {
                return "\(part.name) · \(clef)"
            }
            return "\(part.name) \(seen[part.name]!)"
        }
    }

    /// Whether a reader's mutes and faders may be carried from one
    /// performance to the next.
    ///
    /// This is the price of keying on index, paid explicitly. An op that
    /// REMOVES a part renumbers every part after it, so a mute put on the
    /// viola would come back on the cello -- and it would do it silently,
    /// which is the worst way for it to be wrong. Carried only when the part
    /// list is structurally identical, which is true of every op that does not
    /// touch the staves (transpose, accidentals, structure marks) and false of
    /// exactly the ones that do (keep-parts, remove-parts, merge, split).
    static func canCarry(from previous: [PlaybackTimeline.Part],
                         to next: [PlaybackTimeline.Part]) -> Bool {
        previous.count == next.count
            && zip(previous, next).allSatisfy { $0.index == $1.index && $0.name == $1.name }
    }

    static func label(at index: Int, in parts: [PlaybackTimeline.Part]) -> String {
        let all = labels(for: parts)
        guard let position = parts.firstIndex(where: { $0.index == index }),
              position < all.count else { return "" }
        return all[position]
    }
}
