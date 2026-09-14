import XCTest

/// The reader's nudges, on their way to the page.
///
/// `adjust-element` writes a size and an offset into the MusicXML, and Verovio
/// drops all three on the way to MEI. Every one of them therefore reaches the
/// page only because this file puts it back, and until 0.8.2 it put back the
/// chord symbols alone: a dynamic, a text mark, a fermata and an articulation
/// were adjusted correctly in the file and drawn exactly where they had always
/// been.
///
/// The fixtures are real Verovio artifacts -- the MusicXML, the MEI and the
/// SVG of one engraved page with every mark nudged +8 tenths right, +12 tenths
/// UP and sized to 18pt against the 12pt default -- written by
/// `engine/scripts/make_marks_fixture.py`. This bundle has no Verovio in it,
/// so the artifacts come in as files.
final class ElementAdjustmentsTests: XCTestCase {
    /// What the fixture was nudged by, in MusicXML tenths and points.
    private let dx: CGFloat = 8
    private let dy: CGFloat = 12
    private let size: CGFloat = 18

    private func fixture(_ name: String, _ ext: String) throws -> String {
        guard let url = Bundle(for: Self.self).url(forResource: name,
                                                   withExtension: ext,
                                                   subdirectory: "Fixtures") else {
            XCTFail("missing fixture \(name).\(ext)")
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func attribute(_ name: String, of tag: String) -> Double? {
        guard let r = tag.range(of: "\(name)=\"[-0-9.]+\"", options: .regularExpression)
        else { return nil }
        return Double(tag[r].drop(while: { $0 != "\"" }).dropFirst().dropLast())
    }

    /// The open tag of the nth element of one MEI kind.
    private func meiTag(_ tag: String, _ ordinal: Int, in mei: String) -> String? {
        let matches = mei.ranges(of: "<\(tag) ")
        guard ordinal < matches.count else { return nil }
        let start = matches[ordinal].lowerBound
        guard let end = mei[start...].firstIndex(of: ">") else { return nil }
        return String(mei[start...end])
    }

    // MARK: - Reading the notation

    func testEveryAdjustableKindIsReadOutOfTheMusicXML() throws {
        let xml = try fixture("marks-adjusted", "musicxml")
        let byKind = ChordAdjustments.allAdjustments(inMusicXML: xml)
        for kind in [ChordAdjustments.Kind.dynamic, .text, .fermata, .articulation] {
            let found = try XCTUnwrap(byKind[kind], "\(kind) was not read at all")
            let adjusted = found.filter { !$0.isEmpty }
            XCTAssertEqual(adjusted.count, 1,
                           "\(kind): expected one adjusted element, read \(found)")
            XCTAssertEqual(adjusted.first?.dx, dx, "\(kind) lost its relative-x")
            XCTAssertEqual(adjusted.first?.dy, dy, "\(kind) lost its relative-y")
            XCTAssertEqual(adjusted.first?.size, size, "\(kind) lost its font-size")
        }
    }

    /// A chord diagram rides in a `<words>` too, and `ChordDiagrams` carries
    /// its numbers -- reading it here would place it twice.
    func testAChordDiagramIsNotReadAsATextMark() {
        let xml = """
        <direction><direction-type><words relative-y="40">[x,3,2,0,1,0]</words>
        </direction-type></direction>
        <direction><direction-type><words relative-y="-20">dolce</words>
        </direction-type></direction>
        """
        let text = ChordAdjustments.adjustments(inMusicXML: xml, kind: .text)
        XCTAssertEqual(text.count, 1, "the diagram's <words> was counted as a text mark")
        XCTAssertEqual(text.first?.dy, -20)
    }

    // MARK: - Position, into the MEI

    func testEveryKindsOffsetReachesTheMEI() throws {
        let xml = try fixture("marks-adjusted", "musicxml")
        let mei = try fixture("marks-adjusted", "mei")
        let placed = try XCTUnwrap(
            ChordAdjustments.meiWithAdjustments(
                mei, byKind: ChordAdjustments.allAdjustments(inMusicXML: xml)),
            "nothing was placed at all")

        for (kind, tag) in [(ChordAdjustments.Kind.dynamic, "dynam"),
                            (.text, "dir"), (.fermata, "fermata"),
                            (.articulation, "artic")] {
            let element = try XCTUnwrap(meiTag(tag, 0, in: placed),
                                        "no <\(tag)> in the placed MEI")
            XCTAssertEqual(attribute("ho", of: element),
                           Double(dx * ChordAdjustments.tenthsToHalfSpaces),
                           "\(kind): @ho is \(element)")
            XCTAssertEqual(attribute("vo", of: element),
                           Double(dy * ChordAdjustments.tenthsToHalfSpaces),
                           "\(kind): @vo is \(element)")
        }
    }

    /// The sign, on its own, because getting it wrong is silent: the mark moves,
    /// so a test that only asks whether it moved passes. MusicXML's relative-y
    /// measures UP and so does MEI's @vo -- measured against the engraver, and
    /// asserted here and in check_adjust.py. This file used to negate it, and
    /// the adjust row's "up" arrow moved a chord symbol down the page.
    func testUpIsUp() {
        let xml = """
        <harmony relative-y="15"><root><root-step>C</root-step></root></harmony>
        """
        let placed = ChordAdjustments.meiWithAdjustments(
            "<harm staff=\"1\" tstamp=\"1\">C</harm>",
            byKind: ChordAdjustments.allAdjustments(inMusicXML: xml))
        let mei = try? XCTUnwrap(placed)
        XCTAssertNotNil(mei)
        XCTAssertTrue(mei?.contains("vo=\"3.0\"") ?? false,
                      "a relative-y of +15 tenths must be a POSITIVE @vo of 3.0 "
                      + "half-spaces: \(mei ?? "nothing")")
    }

    /// The diagram markers stay where `ChordDiagrams` will find them.
    func testADiagramMarkerIsNotMovedTwice() {
        let xml = """
        <words relative-y="40">[x,3,2,0,1,0]</words>
        <words relative-y="-20">dolce</words>
        """
        let mei = "<dir staff=\"1\">[x,3,2,0,1,0]</dir><dir staff=\"1\">dolce</dir>"
        let placed = ChordAdjustments.meiWithAdjustments(
            mei, byKind: ChordAdjustments.allAdjustments(inMusicXML: xml)) ?? ""
        let parts = placed.components(separatedBy: "<dir")
        XCTAssertFalse(parts[1].contains("vo="),
                       "the diagram marker was moved here as well as by "
                       + "ChordDiagrams: \(placed)")
        XCTAssertTrue(parts[2].contains("vo=\"-4.0\""),
                      "the text mark beside it was not moved: \(placed)")
    }

    // MARK: - Size, into the drawn page

    func testATextMarksSizeReachesTheDrawnPage() throws {
        let xml = try fixture("marks-adjusted", "musicxml")
        let svg = try fixture("marks-adjusted", "svg")
        let sized = ChordAdjustments.applySizes(
            svg, byKind: ChordAdjustments.allAdjustments(inMusicXML: xml))
        // "dolce" is engraved at 405px; 18pt of the 12pt default is half again
        XCTAssertTrue(sized.contains("607.5"),
                      "the adjusted text mark was not resized")
    }

    /// A dynamic, a fermata and an articulation are GLYPHS: Verovio draws them
    /// as a `<use>` with a scale in its transform, and there is no other handle
    /// on their size at all.
    func testAGlyphsSizeReachesTheDrawnPage() {
        let xml = """
        <direction><direction-type><dynamics font-size="18"><mf/></dynamics>
        </direction-type></direction>
        """
        let svg = """
        <g class="dynam"><use xlink:href="#E52D" transform="translate(4117, 2830) scale(0.72, 0.72)" /></g>
        <g class="staff"><use xlink:href="#E0A4" transform="translate(9, 9) scale(0.72, 0.72)" /></g>
        """
        let sized = ChordAdjustments.applySizes(
            svg, byKind: ChordAdjustments.allAdjustments(inMusicXML: xml))
        XCTAssertTrue(sized.contains("translate(4117, 2830) scale(1.08, 1.08)"),
                      "the dynamic was not scaled by 18/12: \(sized)")
        XCTAssertTrue(sized.contains("translate(9, 9) scale(0.72, 0.72)"),
                      "resizing the dynamic scaled the notehead beside it, "
                      + "which means the block ran past its own </g>: \(sized)")
    }

    /// The anchor is what a resized glyph must not move: a fermata that grew
    /// away from its note is worse than one that did not grow.
    func testAResizedGlyphKeepsItsAnchor() {
        let xml = """
        <notations><articulations><accent font-size="24"/></articulations></notations>
        """
        let svg = "<g class=\"artic\"><use xlink:href=\"#E4A1\" "
            + "transform=\"translate(4106, 2298) scale(0.72, 0.72)\" /></g>"
        let sized = ChordAdjustments.applySizes(
            svg, byKind: ChordAdjustments.allAdjustments(inMusicXML: xml))
        XCTAssertTrue(sized.contains("translate(4106, 2298)"),
                      "the glyph's anchor moved when it was resized: \(sized)")
        XCTAssertTrue(sized.contains("scale(1.44, 1.44)"),
                      "24pt of the 12pt default is double: \(sized)")
    }
}
