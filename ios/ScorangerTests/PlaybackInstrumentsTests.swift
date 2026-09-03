import XCTest

/// Which sound a channel is played with: the reader's choice over the
/// engine's program over the staff's name, and what survives a relaunch.
final class PlaybackInstrumentsTests: XCTestCase {

    private func part(_ index: Int, _ name: String,
                      instrument: String? = nil,
                      program: Int? = nil) -> PlaybackTimeline.Part {
        .init(index: index, name: name, instrument: instrument, program: program)
    }

    // MARK: - The three sources, in order

    /// The engine read the part's own MIDI instrument out of the notation.
    /// That beats reading its caption, so it goes first.
    func testTheEnginesProgramIsUsedWhereTheNotationHadOne() {
        XCTAssertEqual(PlaybackInstruments.guessed(
            for: part(0, "Violin I", program: 68)), 68)
    }

    /// The case this feature exists for: a scanned score whose staves carry a
    /// caption and no program at all.
    func testAStaffWithNoProgramIsReadFromItsName() {
        XCTAssertEqual(PlaybackInstruments.guessed(for: part(0, "Violin I")), 40)
        XCTAssertEqual(PlaybackInstruments.guessed(for: part(1, "Viola")), 41)
        XCTAssertEqual(PlaybackInstruments.guessed(for: part(2, "Trumpet")), 56)
    }

    /// The instrument field is a better name than the staff label when the
    /// engine emitted one but no program with it.
    func testTheNamedInstrumentIsPreferredToTheStaffLabel() {
        XCTAssertEqual(PlaybackInstruments.guessed(
            for: part(0, "Staff 2", instrument: "Clarinet")), 71)
    }

    /// Every unlabeled staff comes out of optical recognition as "Voice", and
    /// the plain piano is the app's already-written answer to that.
    func testANameThatSaysNothingFallsBackToThePlainPiano() {
        XCTAssertEqual(PlaybackInstruments.guessed(for: part(0, "Voice")),
                       PlaybackSound.fallbackProgram)
        XCTAssertEqual(PlaybackInstruments.guessed(for: part(1, "Staff 3")),
                       PlaybackSound.fallbackProgram)
    }

    /// The value crosses a JSON boundary, so an impossible program is not
    /// trusted -- the same rule `PlaybackSound.program(for:)` already applies.
    func testAProgramOutsideGeneralMIDIIsIgnoredAndTheNameIsReadInstead() {
        XCTAssertEqual(PlaybackInstruments.guessed(
            for: part(0, "Flute", program: 200)), 73)
        XCTAssertEqual(PlaybackInstruments.guessed(
            for: part(0, "Flute", program: -1)), 73)
    }

    // MARK: - The reader's choice

    func testAChoiceBeatsBothTheProgramAndTheName() {
        let violin = part(0, "Violin I", program: 40)
        var instruments = PlaybackInstruments()
        XCTAssertEqual(instruments.resolved(for: violin).program, 40)
        instruments.choose(program: 0, for: violin)
        XCTAssertEqual(instruments.resolved(for: violin).program, 0)
        XCTAssertEqual(instruments.resolved(for: violin).bank, .melodic)
    }

    /// The ask, in the arranger's words: "just want to hear every voice on a
    /// piano sound". One call, because a strip at a time is the reason they
    /// asked.
    func testEveryVoiceCanBeSetToOneSoundAtOnce() {
        let parts = [part(0, "Violin I"), part(1, "Viola"), part(2, "Cello")]
        var instruments = PlaybackInstruments()
        instruments.chooseAll(program: 0, parts: parts)
        for one in parts {
            XCTAssertEqual(instruments.resolved(for: one).program, 0)
        }
    }

    /// Clearing REMOVES the entry rather than storing the guess, so "never
    /// touched" and "put back" stay the same state -- the faders' rule.
    func testClearingAChoiceGoesBackToTheGuessAndNotToAStoredCopyOfIt() {
        let viola = part(0, "Viola")
        var instruments = PlaybackInstruments()
        instruments.choose(program: 0, for: viola)
        instruments.clear(viola)
        XCTAssertTrue(instruments.isEmpty)
        XCTAssertEqual(instruments.resolved(for: viola).program, 41)
    }

    func testClearingEverythingEmptiesIt() {
        let parts = [part(0, "Violin I"), part(1, "Viola")]
        var instruments = PlaybackInstruments()
        instruments.chooseAll(program: 0, parts: parts)
        XCTAssertFalse(instruments.isEmpty)
        instruments.clearAll()
        XCTAssertTrue(instruments.isEmpty)
    }

    /// A drum kit is a different bank, and the choice has to carry which.
    func testAKitCarriesItsBankThroughTheChoice() {
        let drums = part(0, "Drums")
        var instruments = PlaybackInstruments()
        instruments.choose(program: 32, bank: .percussion, for: drums)
        let resolved = instruments.resolved(for: drums)
        XCTAssertEqual(resolved.program, 32)
        XCTAssertEqual(resolved.bank, .percussion)
    }

    // MARK: - The index/name guard

    /// The price of keying on index, paid explicitly. An op that removes a
    /// part renumbers everything after it, so a trumpet patch could come back
    /// on the cello. It is ignored when the staff at that index is no longer
    /// the staff the choice was made on.
    func testAChoiceIsDroppedWhenAnotherStaffTakesOverItsIndex() {
        var instruments = PlaybackInstruments()
        instruments.choose(program: 0, for: part(1, "Viola"))
        XCTAssertEqual(instruments.resolved(for: part(1, "Viola")).program, 0)
        // remove-parts renumbered: index 1 is now the cello
        XCTAssertEqual(instruments.resolved(for: part(1, "Cello")).program, 42)
        XCTAssertNil(instruments.choice(for: part(1, "Cello")))
    }

    // MARK: - Across a relaunch

    private func store() throws -> (PlaybackInstrumentStore, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "instruments-\(UUID().uuidString)")
        return (PlaybackInstrumentStore(directory: dir), dir)
    }

    /// A real round trip through the disk, not a struct compared with itself.
    func testAChoiceSurvivesClosingAndReopeningTheScore() throws {
        let (disk, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let violin = part(0, "Violin I", program: 40)

        var instruments = PlaybackInstruments()
        instruments.choose(program: 0, for: violin)
        disk.save(instruments, for: "quartet")

        let reopened = PlaybackInstrumentStore(directory: dir)
            .instruments(for: "quartet")
        XCTAssertEqual(reopened.resolved(for: violin).program, 0)
        XCTAssertEqual(reopened, instruments)
    }

    func testAKitSurvivesTheRoundTripWithItsBank() throws {
        let (disk, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let drums = part(2, "Drum Kit")
        var instruments = PlaybackInstruments()
        instruments.choose(program: 40, bank: .percussion, for: drums)
        disk.save(instruments, for: "band")
        let reopened = disk.instruments(for: "band")
        XCTAssertEqual(reopened.resolved(for: drums).bank, .percussion)
        XCTAssertEqual(reopened.resolved(for: drums).program, 40)
    }

    /// An arrangement nobody has chosen for reads back as nothing chosen, not
    /// as a failure -- the guess underneath is always a usable performance.
    func testAnArrangementWithNothingSavedReadsBackEmpty() throws {
        let (disk, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(disk.instruments(for: "never-touched").isEmpty)
    }

    /// "Back to the guess everywhere" has to survive a relaunch too, and an
    /// empty file left behind would be indistinguishable from one.
    func testClearingEverythingLeavesNoFileBehind() throws {
        let (disk, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        var instruments = PlaybackInstruments()
        instruments.choose(program: 0, for: part(0, "Viola"))
        disk.save(instruments, for: "quartet")
        instruments.clearAll()
        disk.save(instruments, for: "quartet")
        XCTAssertTrue(disk.instruments(for: "quartet").isEmpty)
        let files = try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        XCTAssertTrue(files.isEmpty, "\(files)")
    }

    /// A corrupt file costs the reader their choices, never their playback.
    func testACorruptFileReadsAsNothingChosenRatherThanThrowing() throws {
        let (disk, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("not json".utf8)
            .write(to: dir.appending(path: "quartet.instruments.json"))
        XCTAssertTrue(disk.instruments(for: "quartet").isEmpty)
    }

    /// The engine moves a score's artifacts when its slug changes. State filed
    /// beside them has to move too or it is silently orphaned.
    func testChoicesFollowARenamedArrangement() throws {
        let (disk, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let viola = part(0, "Viola")
        var instruments = PlaybackInstruments()
        instruments.choose(program: 0, for: viola)
        disk.save(instruments, for: "old-slug")
        disk.rename(from: "old-slug", to: "new-slug")
        XCTAssertTrue(disk.instruments(for: "old-slug").isEmpty)
        XCTAssertEqual(disk.instruments(for: "new-slug").resolved(for: viola).program, 0)
    }

    func testDeletingAnArrangementTakesItsChoicesWithIt() throws {
        let (disk, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        var instruments = PlaybackInstruments()
        instruments.choose(program: 0, for: part(0, "Viola"))
        disk.save(instruments, for: "gone")
        disk.clear(slug: "gone")
        XCTAssertTrue(disk.instruments(for: "gone").isEmpty)
    }

    /// A slug is a path component in the workspace. Flattened, so one
    /// arrangement can never write outside the folder it was given.
    func testASlugWithASeparatorInItStaysInsideItsOwnFolder() throws {
        let (disk, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        var instruments = PlaybackInstruments()
        instruments.choose(program: 0, for: part(0, "Viola"))
        disk.save(instruments, for: "../escape")
        let files = try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.lastPathComponent, ".._escape.instruments.json")
    }

    /// A file written before the bank was stored must still decode, or one new
    /// field takes every other channel's choice down with it.
    func testAFileSavedBeforeBanksExistedStillDecodes() throws {
        let (disk, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Swift encodes an Int-keyed dictionary as a keyed container whose
        // keys are the numbers written out, not as an array of pairs.
        let legacy = #"{"chosen":{"0":{"part":"Viola","program":56}}}"#
        try Data(legacy.utf8)
            .write(to: dir.appending(path: "quartet.instruments.json"))
        let read = disk.instruments(for: "quartet")
        let resolved = read.resolved(for: part(0, "Viola"))
        XCTAssertEqual(resolved.program, 56)
        XCTAssertEqual(resolved.bank, .melodic)
    }
}
