import XCTest

/// A text mark is addressable, and a chord DIAGRAM is not.
///
/// Both are `<dir>` in Verovio's MEI. The engine counts only the first kind --
/// `ops._elements_in_measure("text")` excludes a diagram-shaped TextExpression
/// and a rehearsal mark -- so if the app counted both, every text mark after a
/// diagram would be addressed by an ordinal one too high and the adjust row
/// would resize the wrong thing. That is why the parser reads a `<dir>`'s
/// BODY before it decides.
final class TextMarkAddressTests: XCTestCase {

    private func fixture(_ name: String, _ ext: String) throws -> String {
        guard let url = Bundle(for: Self.self).url(forResource: name,
                                                   withExtension: ext,
                                                   subdirectory: "Fixtures") else {
            XCTFail("missing fixture \(name).\(ext)")
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Real Verovio output: one dynamic, two text marks, one fermata, one
    /// articulation, written by engine/scripts/make_marks_fixture.py.
    func testTheFixturesTextMarksAreAddressed() throws {
        let addresses = try MEISemanticsParser.parse(try fixture("marks-adjusted", "mei"))
        let text = addresses.values.filter { $0.kind == .text }
        XCTAssertEqual(text.count, 2, "both <dir>s are text marks here")
        XCTAssertEqual(Set(text.map(\.ordinal)), [0],
                       "they are in different bars, so each is #0 in its own")
    }

    /// Every kind the adjust row reaches comes back with an address.
    func testEveryAdjustableKindInTheFixtureIsAddressed() throws {
        let addresses = try MEISemanticsParser.parse(try fixture("marks-adjusted", "mei"))
        for kind in [ScoreElementKind.dynam, .text, .fermata, .articulation] {
            XCTAssertFalse(addresses.values.filter { $0.kind == kind }.isEmpty,
                           "\(kind) got no address at all")
        }
    }

    // MARK: - The diagram, which is a <dir> too

    private func mei(_ dirs: String) -> String {
        """
        <music><body><mdiv><score><scoreDef/><section>
        <measure n="1">
        <staff n="1"><layer n="1"><note xml:id="n1"/></layer></staff>
        \(dirs)
        </measure>
        </section></score></mdiv></body></music>
        """
    }

    func testAChordDiagramGetsNoAddress() throws {
        let addresses = try MEISemanticsParser.parse(mei(
            "<dir xml:id=\"d1\" staff=\"1\">[x,3,2,0,1,0]</dir>"))
        XCTAssertNil(addresses["d1"],
                     "a diagram is drawn by us and is not a text mark")
    }

    /// The count that matters: a text mark after a diagram must be #0, the way
    /// the engine counts it, not #1.
    func testADiagramDoesNotShiftTheTextMarksOrdinal() throws {
        let addresses = try MEISemanticsParser.parse(mei(
            "<dir xml:id=\"d1\" staff=\"1\">[x,3,2,0,1,0]</dir>"
            + "<dir xml:id=\"t1\" staff=\"1\">dolce</dir>"
            + "<dir xml:id=\"t2\" staff=\"1\">rit.</dir>"))
        XCTAssertNil(addresses["d1"])
        XCTAssertEqual(addresses["t1"]?.ordinal, 0)
        XCTAssertEqual(addresses["t2"]?.ordinal, 1)
    }

    func testATextMarkKnowsItsBarAndStaff() throws {
        let addresses = try MEISemanticsParser.parse(mei(
            "<dir xml:id=\"t1\" staff=\"1\">dolce</dir>"))
        let address = try XCTUnwrap(addresses["t1"])
        XCTAssertEqual(address.kind, .text)
        XCTAssertEqual(address.measure, 1)
        XCTAssertEqual(address.staff, 1)
    }

    /// Nothing else lost its address when `<dir>` gained one.
    func testTheNoteBesideItIsUntouched() throws {
        let addresses = try MEISemanticsParser.parse(mei(
            "<dir xml:id=\"t1\" staff=\"1\">dolce</dir>"))
        XCTAssertEqual(addresses["n1"]?.kind, .note)
    }
}
