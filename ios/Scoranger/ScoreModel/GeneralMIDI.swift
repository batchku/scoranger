import Foundation

/// The sounds the sampler can actually make, named and grouped.
///
/// This is a catalogue, not a guess: every entry below was READ OUT of
/// `gs_instruments.dls` -- the bank `PlaybackSound` loads -- by walking its
/// RIFF chunks and collecting each `insh` header's bank and program. Worth
/// saying because the obvious alternative is to paste the General MIDI list
/// from a specification and hope the file agrees with it. What the file holds:
///
///   - the melodic bank carries **all 128 programs**, none missing
///   - the percussion bank carries **nine kits**, at programs 0, 8, 16, 24,
///     25, 32, 40, 48 and 56 -- and NOT at the other 119, so a picker offering
///     128 drum programs would be offering 119 silences
///   - there are also variation banks (MSB 1-32) with a few dozen programs
///     between them. They are not exposed: `AVAudioUnitSampler` addresses the
///     main bank at the sampler's own melodic MSB, the variations are Roland
///     extensions rather than General MIDI, and most of them are empty
///
/// The names here are the standard General MIDI ones rather than the labels in
/// the file, which are Roland's abbreviations ("Nylon-str.Gt", "Clav.",
/// "Melo. Tom 1") and read as noise to a musician. `short` is the same
/// instrument at the width a 64pt channel strip has for it.
enum GeneralMIDI {

    /// Which bank a sound comes from. Two, because they are addressed
    /// differently and hold different things -- not a detail the picker can
    /// paper over, since a drum kit responds to key numbers and not pitches.
    enum Bank: String, Codable, Equatable, Hashable {
        case melodic, percussion

        /// The MSB `AVAudioUnitSampler.loadSoundBankInstrument` wants.
        var msb: UInt8 {
            switch self {
            case .melodic: return PlaybackSound.melodicBankMSB
            case .percussion: return PlaybackSound.percussionBankMSB
            }
        }
    }

    /// One choosable sound.
    struct Instrument: Identifiable, Equatable, Hashable {
        let program: UInt8
        let bank: Bank
        /// The General MIDI name, for the picker and for VoiceOver.
        let name: String
        /// The same instrument in the room a channel strip has: the strip is
        /// 64pt wide and its caption is already the staff's name, so this is
        /// the second line of a very narrow column.
        let short: String

        var id: String { "\(bank.rawValue)-\(program)" }

        var family: Family {
            bank == .percussion ? .percussion : Family(melodicProgram: program)
        }
    }

    /// General MIDI's sixteen families, in program order, plus the drum kits.
    ///
    /// The families are not a taxonomy someone invented here: GM defines them
    /// as consecutive blocks of eight, so `program / 8` IS the family and the
    /// grouping cannot drift out of step with the programs it groups.
    /// Percussion is appended because the kits are a bank rather than a block,
    /// and a reader looking for a drum kit looks in a list of families.
    enum Family: Int, CaseIterable, Identifiable, Hashable {
        case piano, chromaticPercussion, organ, guitar
        case bass, strings, ensemble, brass
        case reed, pipe, synthLead, synthPad
        case synthEffects, ethnic, percussive, soundEffects
        case percussion

        var id: Int { rawValue }

        /// The family a melodic program belongs to. Total: every program 0-127
        /// lands in one of the sixteen blocks, so there is no default case to
        /// get wrong.
        init(melodicProgram program: UInt8) {
            self = Family(rawValue: Int(program) / 8) ?? .piano
        }

        var name: String {
            switch self {
            case .piano: return "Piano"
            case .chromaticPercussion: return "Chromatic Percussion"
            case .organ: return "Organ"
            case .guitar: return "Guitar"
            case .bass: return "Bass"
            case .strings: return "Strings"
            case .ensemble: return "Ensemble"
            case .brass: return "Brass"
            case .reed: return "Reed"
            case .pipe: return "Pipe"
            case .synthLead: return "Synth Lead"
            case .synthPad: return "Synth Pad"
            case .synthEffects: return "Synth Effects"
            case .ethnic: return "Ethnic"
            case .percussive: return "Percussive"
            case .soundEffects: return "Sound Effects"
            case .percussion: return "Drum Kits"
            }
        }
    }

    // MARK: - The melodic bank

    /// All 128, in program order. The index IS the program number, which is
    /// what `instrument(program:)` relies on.
    static let melodic: [Instrument] = melodicNames.enumerated().map { pair in
        Instrument(program: UInt8(pair.offset), bank: .melodic,
                   name: pair.element.0, short: pair.element.1)
    }

    /// The nine kits the percussion bank actually holds. A tenth would be
    /// silence; see the note at the top.
    static let kits: [Instrument] = [
        (0, "Standard Kit", "Std Kit"),
        (8, "Room Kit", "Room"),
        (16, "Power Kit", "Power"),
        (24, "Electronic Kit", "Electro"),
        (25, "TR-808 Kit", "TR-808"),
        (32, "Jazz Kit", "Jazz"),
        (40, "Brush Kit", "Brush"),
        (48, "Orchestra Kit", "Orch"),
        (56, "Sound FX Kit", "SFX"),
    ].map { Instrument(program: UInt8($0.0), bank: .percussion,
                       name: $0.1, short: $0.2) }

    /// Everything a reader may choose.
    static var all: [Instrument] { melodic + kits }

    /// The sounds in one family, in program order.
    static func instruments(in family: Family) -> [Instrument] {
        guard family != .percussion else { return kits }
        let start = family.rawValue * 8
        return Array(melodic[start..<(start + 8)])
    }

    /// The catalogue entry for a program, or nil where there is none.
    ///
    /// Nil rather than a substitute: a percussion program the bank does not
    /// hold is a silent channel, and the caller deciding what to do about that
    /// is better than this pretending it found something.
    static func instrument(program: UInt8, bank: Bank = .melodic) -> Instrument? {
        switch bank {
        case .melodic:
            return program < melodic.count ? melodic[Int(program)] : nil
        case .percussion:
            return kits.first { $0.program == program }
        }
    }

    /// What to call a program on screen. Falls back to the number, which is
    /// still more use to a reader than an empty caption.
    static func name(program: UInt8, bank: Bank = .melodic) -> String {
        instrument(program: program, bank: bank)?.name ?? "Program \(program)"
    }

    static func short(program: UInt8, bank: Bank = .melodic) -> String {
        instrument(program: program, bank: bank)?.short ?? "\(program)"
    }

    /// (name, short) for programs 0-127, in order.
    private static let melodicNames: [(String, String)] = [
        // 0 Piano
        ("Acoustic Grand Piano", "Piano"),
        ("Bright Acoustic Piano", "Bright Pf"),
        ("Electric Grand Piano", "E.Grand"),
        ("Honky-tonk Piano", "Honky-tonk"),
        ("Electric Piano 1", "E.Piano 1"),
        ("Electric Piano 2", "E.Piano 2"),
        ("Harpsichord", "Hpschd"),
        ("Clavinet", "Clavinet"),
        // 8 Chromatic Percussion
        ("Celesta", "Celesta"),
        ("Glockenspiel", "Glocken"),
        ("Music Box", "Music Box"),
        ("Vibraphone", "Vibes"),
        ("Marimba", "Marimba"),
        ("Xylophone", "Xylophone"),
        ("Tubular Bells", "Tub.Bells"),
        ("Dulcimer", "Dulcimer"),
        // 16 Organ
        ("Drawbar Organ", "Organ"),
        ("Percussive Organ", "Perc.Organ"),
        ("Rock Organ", "Rock Org"),
        ("Church Organ", "Church Org"),
        ("Reed Organ", "Reed Org"),
        ("Accordion", "Accordion"),
        ("Harmonica", "Harmonica"),
        ("Tango Accordion", "Bandoneon"),
        // 24 Guitar
        ("Acoustic Guitar (nylon)", "Nylon Gtr"),
        ("Acoustic Guitar (steel)", "Steel Gtr"),
        ("Electric Guitar (jazz)", "Jazz Gtr"),
        ("Electric Guitar (clean)", "Clean Gtr"),
        ("Electric Guitar (muted)", "Muted Gtr"),
        ("Overdriven Guitar", "Overdrive"),
        ("Distortion Guitar", "Distortion"),
        ("Guitar Harmonics", "Gtr Harm"),
        // 32 Bass
        ("Acoustic Bass", "Ac.Bass"),
        ("Electric Bass (finger)", "E.Bass"),
        ("Electric Bass (pick)", "Pick Bass"),
        ("Fretless Bass", "Fretless"),
        ("Slap Bass 1", "Slap 1"),
        ("Slap Bass 2", "Slap 2"),
        ("Synth Bass 1", "Syn.Bass 1"),
        ("Synth Bass 2", "Syn.Bass 2"),
        // 40 Strings
        ("Violin", "Violin"),
        ("Viola", "Viola"),
        ("Cello", "Cello"),
        ("Contrabass", "Contrabass"),
        ("Tremolo Strings", "Tremolo"),
        ("Pizzicato Strings", "Pizzicato"),
        ("Orchestral Harp", "Harp"),
        ("Timpani", "Timpani"),
        // 48 Ensemble
        ("String Ensemble 1", "Strings 1"),
        ("String Ensemble 2", "Strings 2"),
        ("Synth Strings 1", "Syn.Str 1"),
        ("Synth Strings 2", "Syn.Str 2"),
        ("Choir Aahs", "Choir"),
        ("Voice Oohs", "Voice Ooh"),
        ("Synth Voice", "Syn.Voice"),
        ("Orchestra Hit", "Orch Hit"),
        // 56 Brass
        ("Trumpet", "Trumpet"),
        ("Trombone", "Trombone"),
        ("Tuba", "Tuba"),
        ("Muted Trumpet", "Muted Tpt"),
        ("French Horn", "Horn"),
        ("Brass Section", "Brass"),
        ("Synth Brass 1", "Syn.Brass1"),
        ("Synth Brass 2", "Syn.Brass2"),
        // 64 Reed
        ("Soprano Sax", "Sop.Sax"),
        ("Alto Sax", "Alto Sax"),
        ("Tenor Sax", "Tenor Sax"),
        ("Baritone Sax", "Bari Sax"),
        ("Oboe", "Oboe"),
        ("English Horn", "Eng.Horn"),
        ("Bassoon", "Bassoon"),
        ("Clarinet", "Clarinet"),
        // 72 Pipe
        ("Piccolo", "Piccolo"),
        ("Flute", "Flute"),
        ("Recorder", "Recorder"),
        ("Pan Flute", "Pan Flute"),
        ("Blown Bottle", "Bottle"),
        ("Shakuhachi", "Shakuhachi"),
        ("Whistle", "Whistle"),
        ("Ocarina", "Ocarina"),
        // 80 Synth Lead
        ("Lead 1 (square)", "Square"),
        ("Lead 2 (sawtooth)", "Saw"),
        ("Lead 3 (calliope)", "Calliope"),
        ("Lead 4 (chiff)", "Chiff"),
        ("Lead 5 (charang)", "Charang"),
        ("Lead 6 (voice)", "Solo Vox"),
        ("Lead 7 (fifths)", "Fifths"),
        ("Lead 8 (bass + lead)", "Bass+Lead"),
        // 88 Synth Pad
        ("Pad 1 (new age)", "New Age"),
        ("Pad 2 (warm)", "Warm Pad"),
        ("Pad 3 (polysynth)", "Polysynth"),
        ("Pad 4 (choir)", "Choir Pad"),
        ("Pad 5 (bowed)", "Bowed"),
        ("Pad 6 (metallic)", "Metallic"),
        ("Pad 7 (halo)", "Halo"),
        ("Pad 8 (sweep)", "Sweep"),
        // 96 Synth Effects
        ("FX 1 (rain)", "Rain"),
        ("FX 2 (soundtrack)", "Sndtrack"),
        ("FX 3 (crystal)", "Crystal"),
        ("FX 4 (atmosphere)", "Atmos"),
        ("FX 5 (brightness)", "Bright"),
        ("FX 6 (goblins)", "Goblins"),
        ("FX 7 (echoes)", "Echoes"),
        ("FX 8 (sci-fi)", "Sci-Fi"),
        // 104 Ethnic
        ("Sitar", "Sitar"),
        ("Banjo", "Banjo"),
        ("Shamisen", "Shamisen"),
        ("Koto", "Koto"),
        ("Kalimba", "Kalimba"),
        ("Bagpipe", "Bagpipe"),
        ("Fiddle", "Fiddle"),
        ("Shanai", "Shanai"),
        // 112 Percussive
        ("Tinkle Bell", "Tinkle"),
        ("Agogo", "Agogo"),
        ("Steel Drums", "Steel Drum"),
        ("Woodblock", "Woodblock"),
        ("Taiko Drum", "Taiko"),
        ("Melodic Tom", "Melo.Tom"),
        ("Synth Drum", "Syn.Drum"),
        ("Reverse Cymbal", "Rev.Cym"),
        // 120 Sound Effects
        ("Guitar Fret Noise", "Fret"),
        ("Breath Noise", "Breath"),
        ("Seashore", "Seashore"),
        ("Bird Tweet", "Bird"),
        ("Telephone Ring", "Phone"),
        ("Helicopter", "Copter"),
        ("Applause", "Applause"),
        ("Gunshot", "Gunshot"),
    ]
}
