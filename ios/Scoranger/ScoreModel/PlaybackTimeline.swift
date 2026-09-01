import Foundation

/// The map from a play head to the page: which engraved bar is sounding.
///
/// Built by the engine (`ops.playback_timeline`) alongside the MIDI itself, out
/// of one performed score, so the two cannot drift apart. Nothing here parses
/// notation; this is the app's reading of a map it was handed.
///
/// Beats are QUARTER NOTES, which is what `AVAudioSequencer` reports its
/// position in, so no unit conversion stands between the play head and the bar.
///
/// The subtle part, and the reason this is a list of SPANS rather than a
/// dictionary keyed by bar: **a bar can be played more than once.** music21
/// plays repeats out when it writes MIDI, so a score whose first two bars
/// repeat has bar 1 sounding at beat 0 AND at beat 8. A map from bar to beat
/// would have to choose one of them and would be wrong half the time.
struct PlaybackTimeline: Decodable, Equatable {

    /// One stretch of the performance, and the engraved bar it belongs to.
    struct Bar: Decodable, Equatable {
        /// The number printed on the page. Not unique: a repeated bar appears
        /// once per time it is played.
        let measure: Int
        let start: Double
        let end: Double
        /// A short bar at the head of the music, whose beats are the tail of a
        /// full bar's grid.
        var pickup: Bool = false

        init(measure: Int, start: Double, end: Double, pickup: Bool = false) {
            self.measure = measure
            self.start = start
            self.end = end
            self.pickup = pickup
        }

        private enum CodingKeys: String, CodingKey {
            case measure, start, end, pickup
        }

        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            measure = try box.decode(Int.self, forKey: .measure)
            start = try box.decode(Double.self, forKey: .start)
            end = try box.decode(Double.self, forKey: .end)
            pickup = try box.decodeIfPresent(Bool.self, forKey: .pickup) ?? false
        }
    }

    /// One tick of the metronome.
    struct Click: Decodable, Equatable {
        let beat: Double
        /// The first beat of a bar, which is the one that gets the higher
        /// sound. A pickup's clicks are never down: the player's foot would
        /// land in the wrong place for the whole first phrase.
        let down: Bool
    }

    /// One part, in the order its MIDI track appears.
    struct Part: Decodable, Equatable {
        /// The index of the part AND of its sequencer track. music21 writes one
        /// track per part in score order, and `AVAudioSequencer.tracks` omits
        /// the tempo track, so the two line up with nothing in between.
        let index: Int
        let name: String
        let instrument: String?
        /// The General MIDI program, or nil where the part names no instrument
        /// -- every staff optical recognition labels "Voice". Nil is honest:
        /// the player picks its own default rather than the engine guessing.
        let program: Int?

        /// When this staff is making a noise, as MERGED [start, end] pairs in
        /// quarter notes. The mixer's activity LED reads it.
        ///
        /// Merged, not per-note: contiguous notes are one interval, so a part
        /// playing continuously through eight bars costs ONE pair rather than
        /// thirty. Measured on the scanned quartet -- 136 bars, four staves --
        /// the whole set is 2.3 kB and the busiest staff has 61 intervals.
        ///
        /// Defaulted, so a timeline written by an older engine still decodes:
        /// the engine and the app ship separately on iPad, and a missing key
        /// must not take the performance down with it. Empty means tacet, and
        /// a tacet staff never lights.
        var sounding: [[Double]] = []

        init(index: Int, name: String, instrument: String?, program: Int?,
             sounding: [[Double]] = []) {
            self.index = index
            self.name = name
            self.instrument = instrument
            self.program = program
            self.sounding = sounding
        }

        // Written out because a `var` with a default is STILL REQUIRED by the
        // synthesised decoder -- the default applies to the memberwise
        // initialiser and to nothing else. Every "defaulted" field on this
        // type was therefore mandatory, and a timeline missing any one of them
        // failed the whole decode. That is the wrong failure for a field the
        // engine only recently began emitting.
        private enum CodingKeys: String, CodingKey {
            case index, name, instrument, program, sounding
        }

        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            index = try box.decode(Int.self, forKey: .index)
            name = try box.decode(String.self, forKey: .name)
            instrument = try box.decodeIfPresent(String.self, forKey: .instrument)
            program = try box.decodeIfPresent(Int.self, forKey: .program)
            sounding = try box.decodeIfPresent([[Double]].self, forKey: .sounding) ?? []
        }
    }

    struct Tempo: Decodable, Equatable {
        let beat: Double
        let bpm: Double
    }

    let parts: [Part]
    let bars: [Bar]
    let clicks: [Click]
    let tempos: [Tempo]
    /// False when the arrangement names no tempo and 120 is the writer's
    /// default. Worth showing: "120 (default)" is a different thing for a
    /// reader to see than a tempo somebody chose.
    var tempoFromScore: Bool = false
    /// The length of the performance, which is longer than the engraving
    /// wherever there are repeats.
    var beats: Double = 0
    var repeatsExpanded: Bool = false
    var soundingPitch: Bool = false
    var writtenBars: Int = 0
    var performedBars: Int = 0

    static let empty = PlaybackTimeline(parts: [], bars: [], clicks: [], tempos: [])

    init(parts: [Part], bars: [Bar], clicks: [Click], tempos: [Tempo],
         tempoFromScore: Bool = false, beats: Double = 0,
         repeatsExpanded: Bool = false, soundingPitch: Bool = false,
         writtenBars: Int = 0, performedBars: Int = 0) {
        self.parts = parts
        self.bars = bars
        self.clicks = clicks
        self.tempos = tempos
        self.tempoFromScore = tempoFromScore
        self.beats = beats
        self.repeatsExpanded = repeatsExpanded
        self.soundingPitch = soundingPitch
        self.writtenBars = writtenBars
        self.performedBars = performedBars
    }

    // Declared, because writing `init(from:)` by hand suppresses the
    // synthesis that would otherwise generate these.
    private enum CodingKeys: String, CodingKey {
        case parts, bars, clicks, tempos, tempoFromScore, beats
        case repeatsExpanded, soundingPitch, writtenBars, performedBars
    }

    /// Same reason as `Part`: the fields below carry defaults that the
    /// synthesised decoder ignored, so a timeline without them failed
    /// entirely. The four REQUIRED ones stay required -- a performance with no
    /// bar map is not a performance, and quietly defaulting it to empty would
    /// hide the failure behind a play head that never moves.
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        parts = try box.decode([Part].self, forKey: .parts)
        bars = try box.decode([Bar].self, forKey: .bars)
        clicks = try box.decode([Click].self, forKey: .clicks)
        tempos = try box.decode([Tempo].self, forKey: .tempos)
        tempoFromScore = try box.decodeIfPresent(Bool.self, forKey: .tempoFromScore) ?? false
        beats = try box.decodeIfPresent(Double.self, forKey: .beats) ?? 0
        repeatsExpanded = try box.decodeIfPresent(Bool.self, forKey: .repeatsExpanded) ?? false
        soundingPitch = try box.decodeIfPresent(Bool.self, forKey: .soundingPitch) ?? false
        writtenBars = try box.decodeIfPresent(Int.self, forKey: .writtenBars) ?? 0
        performedBars = try box.decodeIfPresent(Int.self, forKey: .performedBars) ?? 0
    }
}

extension PlaybackTimeline.Part {

    /// Is this staff sounding at this beat?
    ///
    /// Binary search, because it is asked once per strip per tick: a part with
    /// hundreds of intervals must not cost more than one with two. Half-open,
    /// the same rule the bar map follows -- an interval's end belongs to the
    /// silence after it, so a note ending exactly where the next begins reads
    /// as continuous rather than as a flicker.
    func isSounding(at beat: Double) -> Bool {
        var low = 0
        var high = sounding.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let span = sounding[mid]
            guard span.count == 2 else { return false }
            if beat < span[0] { high = mid - 1 }
            else if beat >= span[1] { low = mid + 1 }
            else { return true }
        }
        return false
    }
}

extension PlaybackTimeline {

    var isEmpty: Bool { bars.isEmpty }

    /// The tempo in force at the start, which is what a transport displays
    /// before anything is playing.
    var openingTempo: Double { tempos.first?.bpm ?? 120 }

    /// Which SPAN of the performance the play head is in.
    ///
    /// The span, not the bar: two spans can carry the same bar number, and
    /// telling them apart is what stops a repeat from looking like the play
    /// head standing still.
    ///
    /// A beat that lands exactly on a barline belongs to the bar it OPENS, not
    /// the one it closes -- the same rule `BarPosition` follows for a viewport
    /// resting on a barline.
    func span(atBeat beat: Double) -> Int? {
        guard !bars.isEmpty, beat >= bars[0].start, beat < bars[bars.count - 1].end
        else { return nil }
        var low = 0
        var high = bars.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if beat < bars[mid].start { high = mid - 1 }
            else if beat >= bars[mid].end { low = mid + 1 }
            else { return mid }
        }
        return nil
    }

    /// The engraved bar sounding at this beat: what the reader is looking at.
    func bar(atBeat beat: Double) -> Int? {
        span(atBeat: beat).map { bars[$0].measure }
    }

    /// Which measure is sounding, and how far through it the play head is.
    ///
    /// The pair the cursor is drawn from. Fraction rather than beats, because
    /// the geometry knows a bar's WIDTH and nothing about its meter -- and a
    /// bar of 6/8 following a bar of 4/4 is a different number of beats across
    /// the same kind of space.
    func progress(atBeat beat: Double) -> (measure: Int, fraction: Double)? {
        guard let index = span(atBeat: beat) else { return nil }
        let bar = bars[index]
        let width = bar.end - bar.start
        guard width > 0 else { return (bar.measure, 0) }
        return (bar.measure, (beat - bar.start) / width)
    }

    /// Where a bar is played the FIRST time, for seeking to it from a tap on
    /// the page. The first time and not the last: a reader who taps bar 9
    /// means "start there", and starting inside the second pass of a repeat
    /// would skip the music between.
    func firstBeat(ofBar measure: Int) -> Double? {
        bars.first { $0.measure == measure }?.start
    }

    /// The clicks falling in a half-open beat range, for scheduling the
    /// metronome a window at a time rather than all at once.
    func clicks(from: Double, to: Double) -> [Click] {
        clicks.filter { $0.beat >= from && $0.beat < to }
    }
}
