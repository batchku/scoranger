import XCTest

/// Reading a staff's name as an instrument.
///
/// A test per row, because the table's failure mode is not "no match" -- it is
/// the WRONG match, from a needle that is a substring of a longer name. Every
/// overlap in the table has a case here, and the overlaps are where the bugs
/// would be: "Bass Clarinet" is a clarinet, "Bass Trombone" is a trombone,
/// "Bassoon" is neither, and all three contain "bass".
final class InstrumentGuessTests: XCTestCase {

    private func guess(_ name: String) -> UInt8? {
        InstrumentGuess.program(for: name)
    }

    // MARK: - The names the product owner listed

    func testTheCommonOrchestralNames() {
        XCTAssertEqual(guess("Violin"), 40)
        XCTAssertEqual(guess("Viola"), 41)
        XCTAssertEqual(guess("Cello"), 42)
        XCTAssertEqual(guess("Flute"), 73)
        XCTAssertEqual(guess("Clarinet"), 71)
        XCTAssertEqual(guess("Trumpet"), 56)
        XCTAssertEqual(guess("Guitar"), 24)
        XCTAssertEqual(guess("Piano"), 0)
    }

    // MARK: - Case, punctuation and numbering

    /// "Vln. I", "VIOLIN 1" and "violin-i" are one staff to a reader.
    func testAStaffNameIsReadThroughItsPunctuationAndCase() {
        XCTAssertEqual(guess("VIOLIN I"), 40)
        XCTAssertEqual(guess("violin-ii"), 40)
        XCTAssertEqual(guess("Violin  1"), 40)
        XCTAssertEqual(guess("Vln. I"), 40)
        XCTAssertEqual(guess("Vla."), 41)
        XCTAssertEqual(guess("Vc."), 42)
    }

    func testNormalisationFlattensToSinglePaddedWords() {
        XCTAssertEqual(InstrumentGuess.normalise("Vln. I"), " vln i ")
        XCTAssertEqual(InstrumentGuess.normalise("  Alto   Sax  "), " alto sax ")
        XCTAssertEqual(InstrumentGuess.normalise(""), "")
        XCTAssertEqual(InstrumentGuess.normalise("..."), "")
    }

    func testANameWithNothingInItIsNotGuessedAt() {
        XCTAssertNil(guess(""))
        XCTAssertNil(guess("   "))
        XCTAssertNil(guess("Staff 3"))
    }

    // MARK: - The overlaps, one by one

    /// Three names containing "bass", none of them a bass.
    func testBassIsNotReadOutOfAnInstrumentThatMerelyContainsTheWord() {
        XCTAssertEqual(guess("Bass Clarinet"), 71)
        XCTAssertEqual(guess("Bass Trombone"), 57)
        XCTAssertEqual(guess("Bassoon"), 70)
        XCTAssertEqual(guess("Contrabassoon"), 70)
        XCTAssertEqual(guess("Bass Flute"), 73)
        XCTAssertEqual(guess("Bass Guitar"), 33)
        // and only then does the bare word mean the instrument
        XCTAssertEqual(guess("Bass"), 33)
    }

    /// "Violoncello" must not be caught by "Viola" or "Violin".
    func testTheStringFamilyDoesNotCatchItsOwnLongerNames() {
        XCTAssertEqual(guess("Violoncello"), 42)
        XCTAssertEqual(guess("Contrabass"), 43)
        XCTAssertEqual(guess("Double Bass"), 43)
        XCTAssertEqual(guess("Violin II"), 40)
    }

    /// "Tubular Bells" is not a tuba.
    func testTubularBellsIsNotATuba() {
        XCTAssertEqual(guess("Tubular Bells"), 14)
        XCTAssertEqual(guess("Tuba"), 58)
        XCTAssertEqual(guess("Bass Tuba"), 58)
    }

    /// "English Horn" and "Baritone Horn" are not French horns.
    func testTheHornsAreToldApart() {
        XCTAssertEqual(guess("English Horn"), 69)
        XCTAssertEqual(guess("Cor Anglais"), 69)
        XCTAssertEqual(guess("Baritone Horn"), 58)
        XCTAssertEqual(guess("French Horn"), 60)
        XCTAssertEqual(guess("Horn in F"), 60)
        XCTAssertEqual(guess("Horns"), 60)
    }

    /// "Harpsichord" and "Harmonica" are not harps.
    func testHarpDoesNotSwallowHarpsichordOrHarmonica() {
        XCTAssertEqual(guess("Harpsichord"), 6)
        XCTAssertEqual(guess("Harmonica"), 22)
        XCTAssertEqual(guess("Harp"), 46)
    }

    /// "Steel Drums" is a tuned percussion instrument, not a steel-string
    /// guitar.
    func testSteelDrumsAreNotAGuitar() {
        XCTAssertEqual(guess("Steel Drums"), 114)
        XCTAssertEqual(guess("Steel String Guitar"), 25)
    }

    /// The saxophones are four different programs and the bare word is one of
    /// them by decision, not by accident.
    func testTheSaxophonesAreDistinguishedAndTheBareWordIsAnAlto() {
        XCTAssertEqual(guess("Soprano Sax"), 64)
        XCTAssertEqual(guess("Alto Saxophone"), 65)
        XCTAssertEqual(guess("Tenor Sax"), 66)
        XCTAssertEqual(guess("Baritone Sax"), 67)
        XCTAssertEqual(guess("Sax"), 65)
    }

    func testTheGuitarsAreTheirOwnPrograms() {
        XCTAssertEqual(guess("Electric Guitar"), 27)
        XCTAssertEqual(guess("Classical Guitar"), 24)
        XCTAssertEqual(guess("Acoustic Guitar"), 25)
        XCTAssertEqual(guess("Nylon-str. Gt."), 24)
        XCTAssertEqual(guess("Ukulele"), 24)
        XCTAssertEqual(guess("Banjo"), 105)
        XCTAssertEqual(guess("Mandolin"), 25)
    }

    func testTheOrgansAreToldApart() {
        XCTAssertEqual(guess("Church Organ"), 19)
        XCTAssertEqual(guess("Pipe Organ"), 19)
        XCTAssertEqual(guess("Organ"), 16)
    }

    // MARK: - The staff names this app makes itself

    /// `split-bass` produces "Acc. Bass" and "Acc. Chords" from an accordion
    /// part. Both are accordions, and both contain "bass" or nothing at all.
    func testTheAccordionStavesThisAppCreatesAreAccordions() {
        XCTAssertEqual(guess("Accordion"), 21)
        XCTAssertEqual(guess("Accordion L.H."), 21)
        XCTAssertEqual(guess("Acc. Bass"), 21)
        XCTAssertEqual(guess("Acc. Chords"), 21)
        XCTAssertEqual(guess("Bandoneon"), 23)
    }

    /// `whistle-fingerings` engraves for a penny whistle, so those are staff
    /// names this app puts on the page.
    func testThePennyWhistleIsAWhistle() {
        XCTAssertEqual(guess("Penny Whistle"), 78)
        XCTAssertEqual(guess("Tin Whistle"), 78)
        XCTAssertEqual(guess("D Whistle"), 78)
    }

    // MARK: - What is deliberately NOT guessed

    /// Optical recognition labels every unlabeled staff "Voice", so it is this
    /// app's word for "no instrument named". Reading it as a choir would turn
    /// a scanned quartet into four choirs. Nil here becomes the plain piano
    /// one level up, where that decision is already written down.
    func testVoiceIsNotAChoirBecauseItIsWhatAnUnlabelledStaffIsCalled() {
        XCTAssertNil(guess("Voice"))
        XCTAssertNil(guess("Voice 2"))
    }

    /// A bare range word names a range, not an instrument -- and "Bass" alone
    /// is a bass guitar far more often than it is a singer.
    func testABareRangeWordIsNotReadAsASinger() {
        XCTAssertNil(guess("Alto"))
        XCTAssertNil(guess("Tenor"))
        XCTAssertEqual(guess("Bass"), 33)
        // named outright, it is a choir
        XCTAssertEqual(guess("Choir"), 52)
        XCTAssertEqual(guess("Soprano"), 52)
    }

    // MARK: - Every row resolves to a real sound

    /// A guess pointing at a program the bank does not hold would be silence
    /// dressed as a feature.
    func testEveryGuessNamesAProgramTheBankActuallyHolds() {
        let names = ["Violin", "Viola", "Cello", "Contrabass", "Flute",
                     "Piccolo", "Oboe", "Clarinet", "Bassoon", "Alto Sax",
                     "Trumpet", "Trombone", "Tuba", "French Horn", "Piano",
                     "Organ", "Accordion", "Guitar", "Bass", "Harp",
                     "Timpani", "Choir", "Penny Whistle", "Banjo", "Fiddle",
                     "Marimba", "Vibraphone", "Steel Drums", "Harmonica"]
        for name in names {
            guard let program = guess(name) else {
                return XCTFail("no guess for \(name)")
            }
            XCTAssertNotNil(GeneralMIDI.instrument(program: program),
                            "\(name) -> program \(program)")
        }
    }
}
