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

/// Can a finger reach an added mark at all?
///
/// The adjust row is offered to a selection, a selection comes from the
/// geometry, and the geometry is built from the SVG groups Verovio draws. A
/// mark with no group, or with an empty frame, is adjustable in the engine and
/// unreachable on the page -- which is indistinguishable, from the reader's
/// side, from the feature not existing.
final class MarkHitTargetTests: XCTestCase {

    private func fixture(_ name: String, _ ext: String) throws -> String {
        guard let url = Bundle(for: Self.self).url(forResource: name,
                                                   withExtension: ext,
                                                   subdirectory: "Fixtures") else {
            XCTFail("missing fixture \(name).\(ext)")
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func page() throws -> ScorePage {
        let geometry = try ScoreModelBuilder.build(
            svgPages: [try fixture("marks-adjusted", "svg")],
            mei: try fixture("marks-adjusted", "mei"))
        return try XCTUnwrap(geometry.page(0))
    }

    func testEveryAddedMarkIsOnThePageWithAFrame() throws {
        let elements = try page().elements
        for kind in [ScoreElementKind.dynam, .text, .fermata, .articulation] {
            let drawn = elements.filter { $0.kind == kind }
            XCTAssertFalse(drawn.isEmpty, "\(kind) has no drawn group at all")
            for element in drawn {
                XCTAssertGreaterThan(element.frame.width * element.frame.height, 0,
                                     "\(kind) has an empty frame: \(element.frame)")
            }
        }
    }

    /// And a tap in the middle of one finds it, which is the rule
    /// `AppState.addToSelection` uses.
    func testATapInTheMiddleOfAMarkFindsThatMark() throws {
        let page = try page()
        for kind in [ScoreElementKind.dynam, .text, .fermata, .articulation] {
            guard let drawn = page.elements.first(where: { $0.kind == kind })
            else { continue }
            let hit = page.element(at: CGPoint(x: drawn.frame.midX,
                                               y: drawn.frame.midY))
            XCTAssertEqual(hit?.kind, kind,
                           "a tap on the \(kind) found \(hit?.kind.rawValue ?? "nothing")")
        }
    }

    /// Every drawn mark carries an ADDRESS, or the op cannot be told which one
    /// the reader pointed at.
    func testEveryDrawnMarkIsAddressed() throws {
        for element in try page().elements
        where AddedMark.kinds.contains(element.kind) {
            XCTAssertNotNil(element.address,
                            "\(element.kind) \(element.sessionID) has no address")
        }
    }
}
