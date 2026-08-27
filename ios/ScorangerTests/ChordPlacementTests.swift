import Foundation
import XCTest

/// Where a chord symbol sits, decided by the notation rather than the renderer.
///
/// The Swift half of the rule `engine/scripts/check_chord_placement.py` asserts
/// for the PDF path. Both read the same attributes off the same `<harmony>`
/// tags, because until they did the same file drew its chord names on the staff
/// in the export and above it in the app — and a nudge would have meant two
/// different things.
final class ChordPlacementTests: XCTestCase {

    private let plain = """
    <measure number="1"><harmony><root><root-step>F</root-step></root></harmony></measure>
    """
    private let charted = """
    <measure number="1"><harmony default-y="-25" placement="below">\
    <root><root-step>F</root-step></root></harmony></measure>
    """

    // MARK: - Reading the intent out of the notation

    func testAnUntouchedSymbolDoesNotAskForTheStaff() {
        XCTAssertEqual(ChordPlacement.onStaffFlags(inMusicXML: plain), [false])
    }

    func testAChartedSymbolAsksForTheStaff() {
        XCTAssertEqual(ChordPlacement.onStaffFlags(inMusicXML: charted), [true])
    }

    /// Both attributes, not either: `placement` alone is how a plain score says
    /// "above" or "below" the staff, and treating that as a chart would drag
    /// ordinary lead sheets into the Real Book treatment.
    func testPlacementAloneIsNotAChart() {
        let placementOnly = "<harmony placement=\"below\"><root/></harmony>"
        XCTAssertEqual(ChordPlacement.onStaffFlags(inMusicXML: placementOnly), [false])
    }

    func testEachSymbolAnswersForItself() {
        XCTAssertEqual(ChordPlacement.onStaffFlags(inMusicXML: plain + charted + plain),
                       [false, true, false])
    }

    func testNoChordSymbolsMeansNoFlags() {
        XCTAssertTrue(ChordPlacement.onStaffFlags(inMusicXML: "<note/>").isEmpty)
    }

    // MARK: - Centring

    /// Verovio counts `tstamp` from 1, so 4/4 centres at 2.5. Counting from 0
    /// puts every chord name a beat early.
    func testAFourFourBarCentresAtTwoAndAHalf() {
        XCTAssertEqual(ChordPlacement.centredTimestamp(beatsPerBar: 4), 2.5, accuracy: 0.0001)
    }

    func testAThreeFourBarCentresAtTwo() {
        XCTAssertEqual(ChordPlacement.centredTimestamp(beatsPerBar: 3), 2.0, accuracy: 0.0001)
    }

    func testTheMeterIsReadFromEitherSpelling() {
        XCTAssertEqual(ChordPlacement.beatsPerBar(in: "<meterSig count=\"6\" unit=\"8\"/>"), 6)
        XCTAssertEqual(ChordPlacement.beatsPerBar(in: "<staffDef meter.count=\"3\"/>"), 3)
        XCTAssertNil(ChordPlacement.beatsPerBar(in: "<staffDef/>"))
    }

    // MARK: - What reaches the MEI

    private let mei = """
    <staffDef meter.count="4"/>\
    <harm staff="1" tstamp="1">Fm</harm>\
    <harm staff="1" tstamp="1">C7</harm>
    """

    func testNothingAsksSoNothingIsRewritten() {
        XCTAssertNil(ChordPlacement.meiWithChartStyling(mei, onStaff: [false, false]))
    }

    func testAskingPutsTheSymbolOnTheStaff() {
        let out = ChordPlacement.meiWithChartStyling(mei, onStaff: [true, true])
        XCTAssertNotNil(out)
        XCTAssertEqual(out?.components(separatedBy: "place=\"within\"").count, 3,
                       "both symbols should be placed within: \(out ?? "nil")")
    }

    func testAskingCentresItInTheBar() {
        let out = ChordPlacement.meiWithChartStyling(mei, onStaff: [true, true]) ?? ""
        XCTAssertTrue(out.contains("tstamp=\"2.5\""), out)
        XCTAssertFalse(out.contains("tstamp=\"1\""), "a stamp was left on the downbeat: \(out)")
    }

    /// The one that matters for a mixed score: a symbol that did not ask keeps
    /// its own placement and its own beat.
    func testAnUnaskedNeighbourIsLeftAlone() {
        let out = ChordPlacement.meiWithChartStyling(mei, onStaff: [true, false]) ?? ""
        XCTAssertEqual(out.components(separatedBy: "place=\"within\"").count, 2,
                       "only the first symbol asked: \(out)")
        XCTAssertTrue(out.contains("tstamp=\"1\""), "the second kept its beat: \(out)")
        XCTAssertTrue(out.contains("tstamp=\"2.5\""), "the first was centred: \(out)")
    }

    /// Without a meter there is nothing to centre in, so the stamp is left
    /// alone rather than guessed at.
    func testNoMeterLeavesTheBeatAlone() {
        let meterless = "<harm staff=\"1\" tstamp=\"1\">Fm</harm>"
        let out = ChordPlacement.meiWithChartStyling(meterless, onStaff: [true]) ?? ""
        XCTAssertTrue(out.contains("place=\"within\""), out)
        XCTAssertTrue(out.contains("tstamp=\"1\""), out)
    }

    /// An existing `place` is replaced, not appended: two of them is invalid
    /// MEI and Verovio takes whichever it sees first.
    func testAnExistingPlacementIsReplacedNotDoubled() {
        let already = "<staffDef meter.count=\"4\"/><harm place=\"above\" tstamp=\"1\">Fm</harm>"
        let out = ChordPlacement.meiWithChartStyling(already, onStaff: [true]) ?? ""
        XCTAssertEqual(out.components(separatedBy: "place=").count, 2, out)
        XCTAssertTrue(out.contains("place=\"within\""), out)
    }
}
