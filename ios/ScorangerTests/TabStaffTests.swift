import Foundation
import XCTest

// No import of the app module: this bundle compiles TabStaff.swift in.

/// The on-device half of the tablature contract.
///
/// The golden fragment is cut by engine/scripts/check_guitar_tab.py from what
/// render.py draws for the PDF. Asserting Swift against the same file is what
/// "the two renderers must stay in step" means here.
final class TabStaffTests: XCTestCase {

    private func golden() throws -> [([String], Double, Double, Double, Double, Double, Double, String)] {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: "guitar-tab-golden", withExtension: "txt",
                                   subdirectory: "Fixtures") else {
            XCTFail("the golden fragment is not in the test bundle")
            return []
        }
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map { line in
                let halves = line.split(separator: "\t", maxSplits: 1)
                let head = halves[0].split(separator: "|", omittingEmptySubsequences: false)
                    .map(String.init)
                let texts = head[0].components(separatedBy: ",")
                return (texts, Double(head[1])!, Double(head[2])!, Double(head[3])!,
                        Double(head[4])!, Double(head[5])!, Double(head[6])!,
                        String(halves[1]))
            }
    }

    func testDrawsWhatThePDFDraws() throws {
        let cases = try golden()
        XCTAssertFalse(cases.isEmpty)
        for (texts, x, top, pitch, left, right, scale, expected) in cases {
            let drawn = TabStaff.columnSVG(texts: texts, x: x, topY: top, rowPitch: pitch,
                                           left: left, right: right, scale: scale)
            XCTAssertEqual(drawn, expected, "\(texts) is drawn differently here")
        }
    }

    func testAFretNumberBreaksItsLine() {
        let plain = TabStaff.columnSVG(texts: Array(repeating: "-", count: 6),
                                       x: 500, topY: 0, rowPitch: 100, left: 0, right: 1000)
        let fretted = TabStaff.columnSVG(texts: ["7", "-", "-", "-", "-", "-"],
                                         x: 500, topY: 0, rowPitch: 100, left: 0, right: 1000)
        // six lines plain; the fretted row becomes two segments with the
        // number standing between them
        XCTAssertEqual(plain.components(separatedBy: "<path").count - 1, 6)
        XCTAssertEqual(fretted.components(separatedBy: "<path").count - 1, 7)
        XCTAssertFalse(plain.contains("<text"))
        XCTAssertTrue(fretted.contains(">7</tspan>"))
    }

    func testATwoDigitFretGetsAWiderGap() {
        let one = TabStaff.columnSVG(texts: ["7", "-", "-", "-", "-", "-"],
                                     x: 500, topY: 0, rowPitch: 100, left: 0, right: 1000)
        let two = TabStaff.columnSVG(texts: ["10", "-", "-", "-", "-", "-"],
                                     x: 500, topY: 0, rowPitch: 100, left: 0, right: 1000)
        // the left-hand segment of the broken line stops earlier for "10"
        func firstSegmentEnd(_ svg: String) -> Double? {
            guard let re = try? NSRegularExpression(pattern: "L ([-0-9.]+) 0\""),
                  let m = re.firstMatch(in: svg,
                                        range: NSRange(location: 0, length: (svg as NSString).length))
            else { return nil }
            return Double((svg as NSString).substring(with: m.range(at: 1)))
        }
        XCTAssertLessThan(firstSegmentEnd(two) ?? 0, firstSegmentEnd(one) ?? 0)
    }

    func testTheLabelCarriesTheReadersNudge() {
        XCTAssertEqual(TabStaff.parseLabel("gt")?.scale, nil)
        let adjusted = TabStaff.parseLabel("gt@1.5,15,-20")
        XCTAssertEqual(adjusted?.scale, 1.5)
        XCTAssertEqual(adjusted?.dx, 15)
        XCTAssertEqual(adjusted?.dy, -20)
        // offsets without a size, which is what a plain move writes
        XCTAssertEqual(TabStaff.parseLabel("gt@,15,")?.dx, 15)
        XCTAssertNil(TabStaff.parseLabel("gt@,15,")?.scale)
        // a whistle verse is not a tab verse
        XCTAssertNil(TabStaff.parseLabel("wf"))
        XCTAssertNil(TabStaff.parseLabel("verse"))
    }

    func testDrawingReplacesTheVerses() {
        let svg = verses(["0", "-", "-", "-", "-", "-"], x: 638, top: 2547, pitch: 390)
        let drawn = TabStaff.draw(in: svg)
        XCTAssertTrue(drawn.contains("class=\"verse tab\""))
        XCTAssertFalse(drawn.contains("labelAttr"), "the verses themselves are not drawn")
        XCTAssertTrue(drawn.contains("<path"), "the staff is drawn, not written")
        // a page with no tab comes back untouched
        let plain = "<g class=\"verse\"><title class=\"labelAttr\">1</title>"
            + "<text x=\"1\" y=\"2\"><tspan>la</tspan></text></g></g>"
        XCTAssertEqual(TabStaff.draw(in: plain), plain)
    }

    /// Six tagged verses on one note, as Verovio lays them out.
    private func verses(_ texts: [String], x: Double, top: Double, pitch: Double,
                        label: String = "gt") -> String {
        texts.enumerated().map { row, text in
            "<g class=\"verse\"><title class=\"labelAttr\">\(label)</title>"
                + "<g class=\"syl\"><text x=\"\(x)\" y=\"\(top + Double(row) * pitch)\">"
                + "<tspan class=\"text\"><tspan font-size=\"405px\">\(text)</tspan></tspan>"
                + "</text></g></g></g>"
        }.joined()
    }
}
