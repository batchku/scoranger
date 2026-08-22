import CoreGraphics
import XCTest

// No import of the app module: this bundle compiles FingeringDiagrams.swift in.

/// The rewrite that turns engraved fingerings into drawn diagrams. The input is
/// real Verovio markup, copied from a rendered page — including the trap that
/// the enclosing <text> is font-size="0px" while the glyph's true size lives on
/// the inner tspan.
final class FingeringDiagramTests: XCTestCase {

    private func verse(_ number: Int, _ symbol: String, tag: String = "wf",
                       x: Int = 2670, y: Int = 2722, size: Int = 405) -> String {
        """
        <g id="v\(number)" class="verse">
           <title class="labelAttr">\(tag)</title>
           <g id="s\(number)" class="syl">
              <text x="\(x)" y="\(y)" font-size="0px">
                 <tspan id="t\(number)" class="text">
                    <tspan font-size="\(size)px">\(symbol)</tspan>
                 </tspan>
              </text>
           </g>
        </g>
        """
    }

    private func radius(of path: String) -> CGFloat? {
        guard let re = try? NSRegularExpression(pattern: "A ([0-9.]+) "),
              let m = re.firstMatch(in: path,
                                    range: NSRange(location: 0, length: (path as NSString).length))
        else { return nil }
        return CGFloat(Double((path as NSString).substring(with: m.range(at: 1))) ?? 0)
    }

    // MARK: - What it draws

    func testCoveredHoleBecomesAFilledShape() {
        let out = FingeringDiagrams.draw(in: verse(1, "X"))
        XCTAssertTrue(out.contains("fill=\"currentColor\""), out)
        XCTAssertFalse(out.contains("<text"), "the glyph should be gone: \(out)")
    }

    func testOpenHoleBecomesAStrokedRing() {
        let out = FingeringDiagrams.draw(in: verse(2, "O"))
        XCTAssertTrue(out.contains("fill=\"none\""), out)
        XCTAssertTrue(out.contains("stroke=\"currentColor\""), out)
    }

    func testHalfHoleGetsBothARingAndAFill() {
        let out = FingeringDiagrams.draw(in: verse(3, "/"))
        XCTAssertEqual(out.components(separatedBy: "<path").count - 1, 2,
                       "a half hole is a ring plus a filled half: \(out)")
    }

    /// The bug that shipped nothing to the device: the enclosing <text> is
    /// font-size="0px", so reading the wrong element gave radius zero and drew
    /// invisible circles.
    func testRadiusComesFromTheGlyphNotTheZeroSizedTextElement() throws {
        let out = FingeringDiagrams.draw(in: verse(1, "X", size: 405))
        let r = try XCTUnwrap(radius(of: out), "no arc in \(out)")
        XCTAssertGreaterThan(r, 1, "radius must come from the tspan's 405px, not the text's 0px")
        XCTAssertEqual(r, 405 * 0.28, accuracy: 1)
    }

    func testDiagramScalesWithTheEngraving() throws {
        let small = try XCTUnwrap(radius(of: FingeringDiagrams.draw(in: verse(1, "X", size: 200))))
        let large = try XCTUnwrap(radius(of: FingeringDiagrams.draw(in: verse(1, "X", size: 800))))
        XCTAssertEqual(large / small, 4, accuracy: 0.01)
    }

    // MARK: - What it leaves alone

    func testUntaggedVersesAreNeverTouched() {
        // a song whose lyric is the word "O" must stay a word
        let lyric = verse(1, "O", tag: "1")
        XCTAssertEqual(FingeringDiagrams.draw(in: lyric), lyric)
    }

    func testTheOctaveMarkStaysAsText() {
        let out = FingeringDiagrams.draw(in: verse(7, "+"))
        XCTAssertTrue(out.contains("<text"), "the + is text, not a hole: \(out)")
        XCTAssertFalse(out.contains("<path"), out)
    }

    func testAPageWithNoFingeringsIsReturnedUnchanged() {
        let svg = "<svg><g class=\"note\"><use xlink:href=\"#E0A4\" /></g></svg>"
        XCTAssertEqual(FingeringDiagrams.draw(in: svg), svg)
    }

    func testEveryHoleOfAColumnIsDrawn() {
        let column = (1...6).map { verse($0, $0 <= 3 ? "X" : "O") }.joined()
        let out = FingeringDiagrams.draw(in: column)
        XCTAssertEqual(out.components(separatedBy: "<path").count - 1, 6,
                       "all six holes should be drawn")
        XCTAssertFalse(out.contains("<text"), "no glyphs should survive")
    }
}
