import XCTest

/// The catalogue of sounds the sampler can make.
///
/// The counts here are not folklore: they were read out of
/// `gs_instruments.dls` by walking its RIFF chunks. The melodic bank holds all
/// 128 programs; the percussion bank holds nine kits and nothing at the other
/// 119 programs. A picker offering what the bank does not hold offers silence.
final class GeneralMIDITests: XCTestCase {

    func testTheMelodicBankIsAllOneHundredAndTwentyEightPrograms() {
        XCTAssertEqual(GeneralMIDI.melodic.count, 128)
    }

    /// The index IS the program, which is what the O(1) lookup relies on.
    func testEveryEntrySitsAtItsOwnProgramNumber() {
        for (index, instrument) in GeneralMIDI.melodic.enumerated() {
            XCTAssertEqual(instrument.program, UInt8(index))
            XCTAssertEqual(instrument.bank, .melodic)
        }
    }

    func testEveryInstrumentIsNamedInBothLengths() {
        for instrument in GeneralMIDI.all {
            XCTAssertFalse(instrument.name.isEmpty, "program \(instrument.program)")
            XCTAssertFalse(instrument.short.isEmpty, "program \(instrument.program)")
        }
    }

    /// The strip is 64pt wide and its caption is already the staff's name. A
    /// short label longer than this is a truncation with no information in it.
    func testTheShortLabelFitsAChannelStrip() {
        for instrument in GeneralMIDI.all {
            XCTAssertLessThanOrEqual(instrument.short.count, 10,
                                     "\(instrument.name) -> \(instrument.short)")
        }
    }

    /// General MIDI defines its families as consecutive blocks of eight, so
    /// the grouping cannot drift out of step with the programs it groups.
    func testTheSixteenMelodicFamiliesAreEightProgramsEach() {
        let melodicFamilies = GeneralMIDI.Family.allCases.filter { $0 != .percussion }
        XCTAssertEqual(melodicFamilies.count, 16)
        for family in melodicFamilies {
            XCTAssertEqual(GeneralMIDI.instruments(in: family).count, 8,
                           family.name)
        }
    }

    /// Grouped by family, the list still accounts for every program exactly
    /// once -- a picker cannot hide one or offer it twice.
    func testTheFamiliesPartitionTheWholeBank() {
        let grouped = GeneralMIDI.Family.allCases
            .filter { $0 != .percussion }
            .flatMap { GeneralMIDI.instruments(in: $0) }
        XCTAssertEqual(grouped.map(\.program), (0...127).map { UInt8($0) })
    }

    func testAProgramKnowsWhichFamilyItIsIn() {
        XCTAssertEqual(GeneralMIDI.Family(melodicProgram: 0), .piano)
        XCTAssertEqual(GeneralMIDI.Family(melodicProgram: 40), .strings)
        XCTAssertEqual(GeneralMIDI.Family(melodicProgram: 56), .brass)
        XCTAssertEqual(GeneralMIDI.Family(melodicProgram: 73), .pipe)
        XCTAssertEqual(GeneralMIDI.Family(melodicProgram: 127), .soundEffects)
    }

    /// Read out of the file, not out of a specification: these nine programs
    /// are the only ones in the percussion bank.
    func testThePercussionBankIsTheNineKitsTheFileActuallyHolds() {
        XCTAssertEqual(GeneralMIDI.kits.map(\.program),
                       [0, 8, 16, 24, 25, 32, 40, 48, 56])
        for kit in GeneralMIDI.kits { XCTAssertEqual(kit.bank, .percussion) }
    }

    /// The families group the kits too, or a reader looking for a drum kit in
    /// a list of families does not find one.
    func testTheKitsAreTheirOwnFamily() {
        XCTAssertEqual(GeneralMIDI.instruments(in: .percussion).count, 9)
        XCTAssertEqual(GeneralMIDI.kits[0].family, .percussion)
    }

    /// A program the bank does not hold is silence, and the caller has to be
    /// able to tell. This is the whole reason the lookup is optional.
    func testAProgramThePercussionBankDoesNotHoldIsNotInvented() {
        XCTAssertNil(GeneralMIDI.instrument(program: 1, bank: .percussion))
        XCTAssertNotNil(GeneralMIDI.instrument(program: 1, bank: .melodic))
        XCTAssertNotNil(GeneralMIDI.instrument(program: 25, bank: .percussion))
    }

    func testTheTwoBanksAddressDifferentPlaces() {
        XCTAssertEqual(GeneralMIDI.Bank.melodic.msb, PlaybackSound.melodicBankMSB)
        XCTAssertEqual(GeneralMIDI.Bank.percussion.msb,
                       PlaybackSound.percussionBankMSB)
    }

    /// The names are the standard General MIDI ones. The file's own labels are
    /// Roland abbreviations ("Nylon-str.Gt", "Melo. Tom 1") and read as noise.
    func testTheNamesAreTheOnesAMusicianWouldRecognise() {
        XCTAssertEqual(GeneralMIDI.name(program: 0), "Acoustic Grand Piano")
        XCTAssertEqual(GeneralMIDI.name(program: 40), "Violin")
        XCTAssertEqual(GeneralMIDI.name(program: 42), "Cello")
        XCTAssertEqual(GeneralMIDI.name(program: 71), "Clarinet")
        XCTAssertEqual(GeneralMIDI.name(program: 73), "Flute")
    }
}
