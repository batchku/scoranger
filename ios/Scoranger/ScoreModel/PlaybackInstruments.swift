import Foundation

/// Which sound each channel is played with, and where that sound came from.
///
/// **This is playback, not notation.** `change-instrument` in the engine
/// rewrites the score -- it transposes written pitch, picks a new clef, moves
/// the line into the new instrument's range and makes a new version. Nothing
/// here does any of that. An arranger who wants to hear every voice as a piano
/// is asking a question about the speaker, not about the page, and answering
/// it by editing the notation would be answering a different question and
/// leaving a version behind as a receipt.
///
/// So a choice made here changes one sampler's loaded patch and nothing else.
/// It is not a version, it never reaches MusicXML, and clearing it restores
/// the guess without an undo step.
///
/// Three sources, in order, and the first that answers wins:
///
///   1. **the reader's choice**, if they made one for that channel
///   2. **the engine's program**, where the part names an instrument music21
///      recognised
///   3. **the staff's name**, read by `InstrumentGuess`
///
/// and the piano fallback under all three, for a staff called nothing useful.
struct PlaybackInstruments: Equatable, Codable {

    /// One reader's choice, and the staff it was made on.
    ///
    /// The name is stored ALONGSIDE the index, and this is the whole reason
    /// the type is not just `[Int: UInt8]`. Channels are keyed on index --
    /// `PlaybackVoices` explains why -- and an op that removes a part
    /// renumbers every part after it, so a trumpet patch put on the viola
    /// would come back on the cello.
    ///
    /// The mutes handle that by refusing to carry across a changed part list
    /// (`PlaybackChannels.canCarry`). These cannot use the same rule, because
    /// they are read back off disk on a relaunch where there is no previous
    /// part list to compare with. So each choice carries the name it was made
    /// against and is ignored when the staff at that index is no longer that
    /// staff -- which covers the relaunch and the renumbering with one fact.
    struct Choice: Equatable, Codable {
        let part: String
        let program: UInt8
        var bank: GeneralMIDI.Bank = .melodic

        init(part: String, program: UInt8, bank: GeneralMIDI.Bank = .melodic) {
            self.part = part
            self.program = program
            self.bank = bank
        }

        private enum CodingKeys: String, CodingKey { case part, program, bank }

        // Written out for the same reason `PlaybackTimeline.Part` writes its
        // decoder out: a `var` with a default is still REQUIRED by the
        // synthesised one, so a file saved before `bank` existed would fail
        // the whole decode and take every other channel's choice with it.
        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            part = try box.decode(String.self, forKey: .part)
            program = try box.decode(UInt8.self, forKey: .program)
            bank = try box.decodeIfPresent(GeneralMIDI.Bank.self, forKey: .bank)
                ?? .melodic
        }
    }

    /// Only what the reader has actually chosen. Absent means "whatever the
    /// staff suggests", which keeps "never touched" and "set back to the
    /// guess" the same state -- the same rule the faders follow.
    private(set) var chosen: [Int: Choice] = [:]

    init(chosen: [Int: Choice] = [:]) { self.chosen = chosen }

    var isEmpty: Bool { chosen.isEmpty }

    /// What the reader picked for this channel, if the staff still matches.
    func choice(for part: PlaybackTimeline.Part) -> Choice? {
        guard let choice = chosen[part.index], choice.part == part.name else {
            return nil
        }
        return choice
    }

    mutating func choose(program: UInt8, bank: GeneralMIDI.Bank = .melodic,
                         for part: PlaybackTimeline.Part) {
        chosen[part.index] = Choice(part: part.name, program: program, bank: bank)
    }

    /// Back to the guess. Removing the entry rather than storing the guessed
    /// program, so a later engine that reads the staff better is allowed to
    /// change its mind about a channel nobody has an opinion on.
    mutating func clear(_ part: PlaybackTimeline.Part) {
        chosen.removeValue(forKey: part.index)
    }

    /// Every channel on one sound: the arranger's "just let me hear it all as
    /// a piano". One call, because doing it a strip at a time is eight taps
    /// and the reason they asked for the feature.
    mutating func chooseAll(program: UInt8, bank: GeneralMIDI.Bank = .melodic,
                            parts: [PlaybackTimeline.Part]) {
        for part in parts { choose(program: program, bank: bank, for: part) }
    }

    mutating func clearAll() { chosen = [:] }

    /// The sound this channel will actually be loaded with.
    func resolved(for part: PlaybackTimeline.Part)
        -> (program: UInt8, bank: GeneralMIDI.Bank) {
        if let choice = choice(for: part) {
            return (choice.program, choice.bank)
        }
        return (PlaybackInstruments.guessed(for: part), .melodic)
    }

    /// The sound a channel gets when the reader has not chosen one: the
    /// engine's program where music21 named an instrument, otherwise the staff
    /// label read by `InstrumentGuess`, otherwise the plain piano.
    ///
    /// The engine goes FIRST because it read the part's own MIDI instrument
    /// out of the notation, which beats reading its caption. The name is the
    /// fallback for the case that made this feature necessary: a scanned score
    /// whose staves say "Violin I" and carry no program at all.
    static func guessed(for part: PlaybackTimeline.Part) -> UInt8 {
        if let program = part.program, (0...127).contains(program) {
            return UInt8(program)
        }
        if let named = part.instrument, let guess = InstrumentGuess.program(for: named) {
            return guess
        }
        return InstrumentGuess.program(for: part.name) ?? PlaybackSound.fallbackProgram
    }
}

/// Reading a staff's name as an instrument.
///
/// The product ask, in the arranger's words: *"I expect the instrument to be
/// auto-set based on staff name."* The engine already emits a program where
/// music21 recognised the part's instrument; this covers the case it cannot --
/// a scanned score, where every staff carries a caption and nothing else.
///
/// The table is ORDERED and the first match wins, because the needles overlap
/// and the overlaps are exactly where the wrong answers live. "Bass Clarinet"
/// is a clarinet; "Bass Trombone" is a trombone; "Bassoon" is neither, and all
/// three contain "bass". So the specific rows come first and the bare family
/// words come last, and each of those orderings has a test.
enum InstrumentGuess {

    /// The General MIDI program a staff label suggests, or nil when the label
    /// says nothing an instrument can be read out of.
    ///
    /// Nil rather than a default, so the caller decides. `PlaybackInstruments`
    /// turns it into the plain piano, which is a deliberate choice made once
    /// where it can be seen rather than buried in this table as row 200.
    static func program(for name: String) -> UInt8? {
        let needle = normalise(name)
        guard !needle.isEmpty else { return nil }
        for (word, program) in table where needle.contains(word) {
            return program
        }
        return nil
    }

    /// Lowercased, with punctuation flattened to spaces and runs of space
    /// collapsed. "Vln. I", "VIOLIN 1" and "violin-i" are one staff to a
    /// reader and must be one staff here. The trailing/leading spaces are kept
    /// on purpose -- a padded needle is how a row can ask for a whole word.
    static func normalise(_ name: String) -> String {
        let flattened = name.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        let words = String(flattened).split(separator: " ")
        guard !words.isEmpty else { return "" }
        return " " + words.joined(separator: " ") + " "
    }

    /// Needle to program. Ordered; first containment wins.
    ///
    /// Needles are padded with spaces where the word must stand alone: " harp "
    /// must not catch "harpsichord", and unpadded it would.
    private static let table: [(String, UInt8)] = [
        // --- woodwind, before every "bass" row -------------------------------
        ("piccolo", 72),
        ("pan flute", 75), ("panpipe", 75),
        ("flute", 73),                      // alto and bass flute included
        ("recorder", 74),
        ("oboe", 68),
        ("english horn", 69), ("cor anglais", 69),
        ("bassoon", 70),                    // and contrabassoon
        ("clarinet", 71),                   // and bass clarinet, E-flat clarinet
        ("soprano sax", 64),
        ("alto sax", 65),
        ("tenor sax", 66),
        ("baritone sax", 67), ("bari sax", 67),
        ("sax", 65),                        // an unqualified sax is an alto
        // --- brass ------------------------------------------------------------
        ("trumpet", 56), ("cornet", 56), ("flugel", 56),
        ("trombone", 57),                   // and bass trombone
        ("euphonium", 58), ("baritone horn", 58),
        (" tuba", 58),                      // padded: "Tubular Bells" is not a tuba
        ("french horn", 60),
        ("horn", 60),                       // after english horn and baritone horn
        // --- strings ----------------------------------------------------------
        ("violoncello", 42),
        ("violin", 40),
        ("viola", 41),
        ("cello", 42),
        ("contrabass", 43), ("double bass", 43), ("string bass", 43),
        ("upright bass", 43),
        (" vln", 40), (" vla", 41), (" vc ", 42), (" vcl", 42), (" cb ", 43),
        ("pizzicato", 45),
        ("harpsichord", 6),                 // before " harp "
        ("harmonica", 22),
        (" harp ", 46),
        ("timpani", 47),
        ("strings", 48), ("string ensemble", 48),
        // --- voice ------------------------------------------------------------
        //
        // "Voice" is NOT here, and that is a decision this file inherits rather
        // than makes: optical recognition labels every unlabeled staff "Voice",
        // so it is the app's word for "no instrument named", and a scanned
        // quartet would come up as four choirs. `PlaybackSound.fallbackProgram`
        // explains why plain piano is the right sound for that.
        //
        // Bare "Alto", "Tenor" and "Bass" are absent for the same reason from
        // the other side: they name a range, not an instrument, and "Bass" on
        // its own is a bass guitar far more often than it is a singer.
        ("choir", 52), ("chorus", 52), ("soprano", 52),
        // --- keyboard and free reed -------------------------------------------
        ("church organ", 19), ("pipe organ", 19),
        ("organ", 16),
        ("accordion", 21), ("concertina", 21), ("bandoneon", 23),
        (" acc ", 21),                      // "Acc. Bass", "Acc. Chords"
        ("piano", 0), ("keyboard", 0), (" keys ", 0),
        ("celesta", 8), ("glockenspiel", 9), ("vibraphone", 11), ("vibes", 11),
        ("marimba", 12), ("xylophone", 13), ("tubular", 14),
        ("clavinet", 7), ("clavichord", 7), (" clav ", 7),
        // --- fretted ----------------------------------------------------------
        ("bass guitar", 33), ("electric bass", 33),
        ("electric guitar", 27), ("classical guitar", 24),
        ("nylon", 24), ("steel str", 25), ("steel guitar", 25),
        ("acoustic guitar", 25),
        ("guitar", 24), (" gtr", 24), (" gt ", 24),
        ("ukulele", 24), ("mandolin", 25), ("banjo", 105),
        ("sitar", 104), ("shamisen", 106), ("koto", 107), ("kalimba", 108),
        // --- pipes and whistles -----------------------------------------------
        //
        // The whistle earns its row: this app engraves penny-whistle
        // fingerings, so "Penny Whistle" and "Tin Whistle" are staff names it
        // creates itself.
        ("whistle", 78), ("ocarina", 79), ("bagpipe", 109), ("shakuhachi", 77),
        ("fiddle", 110),
        // --- percussion, as a melodic stand-in --------------------------------
        //
        // A drum staff is a KIT and kits live in the other bank, which is a
        // choice with consequences a guess should not make on the reader's
        // behalf. These are the tuned ones only.
        ("steel drum", 114), ("taiko", 116), ("woodblock", 115), ("agogo", 113),
        // --- last resort ------------------------------------------------------
        (" bass ", 33),
    ]
}
