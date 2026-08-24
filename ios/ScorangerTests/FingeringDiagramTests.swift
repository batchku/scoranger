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
        // scaled in our own pass now: Verovio's text size stays at its default
        // so chord symbols keep their size, and the diagram is shrunk here
        XCTAssertEqual(r, 405 * 0.28 * FingeringDiagrams.diagramScale, accuracy: 1)
    }

    func testDiagramScalesWithTheEngraving() throws {
        let small = try XCTUnwrap(radius(of: FingeringDiagrams.draw(in: verse(1, "X", size: 200))))
        let large = try XCTUnwrap(radius(of: FingeringDiagrams.draw(in: verse(1, "X", size: 800))))
        XCTAssertEqual(large / small, 4, accuracy: 0.01)
    }

    // MARK: - Above the staff (build 128)

    private func meiNote(_ syls: [String], label: String = "wf",
                         element: String = "note") -> String {
        let verses = syls.enumerated().map { index, syl in
            "<verse xml:id=\"v\(index)\" label=\"\(label)\" n=\"\(index + 1)\">"
                + "<syl xml:id=\"s\(index)\">\(syl)</syl></verse>"
        }.joined()
        return "<\(element) xml:id=\"n1\" dur=\"4\" oct=\"4\" pname=\"d\">"
            + verses + "</\(element)>"
    }

    func testFingeringVersesAreMovedAboveTheStaff() throws {
        let mei = "<music>" + meiNote(["X", "X", "X", "O", "O", "O"]) + "</music>"
        let out = try XCTUnwrap(FingeringDiagrams.meiWithFingeringsAbove(mei),
                               "a fingering column should be moved")
        XCTAssertEqual(out.components(separatedBy: "place=\"above\"").count - 1, 6)
    }

    /// Fingerings written before the tag existed have to move too, or Ali's
    /// score keeps them below the staff for ever.
    func testAnUntaggedColumnIsAlsoMovedAbove() throws {
        let mei = "<music>" + meiNote(["X", "X", "X", "X", "X", "O"], label: "1") + "</music>"
        let out = try XCTUnwrap(FingeringDiagrams.meiWithFingeringsAbove(mei))
        XCTAssertEqual(out.components(separatedBy: "place=\"above\"").count - 1, 6)
    }

    /// A fingered note inside a chord hangs its verses off the <chord>, which is
    /// most of a piano or accordion part — scanning only <note> missed them all.
    func testVersesOnAChordAreMovedToo() throws {
        let mei = "<music>" + meiNote(["X", "X", "X", "O", "O", "O"], element: "chord")
            + "</music>"
        let out = try XCTUnwrap(FingeringDiagrams.meiWithFingeringsAbove(mei))
        XCTAssertEqual(out.components(separatedBy: "place=\"above\"").count - 1, 6)
    }

    func testTheOctaveMarkTravelsWithItsColumn() throws {
        let mei = "<music>" + meiNote(["X", "X", "X", "X", "X", "X", "+"]) + "</music>"
        let out = try XCTUnwrap(FingeringDiagrams.meiWithFingeringsAbove(mei))
        XCTAssertEqual(out.components(separatedBy: "place=\"above\"").count - 1, 7,
                       "the + belongs to the column and moves with it")
    }

    func testASungLyricIsNotMoved() {
        let mei = "<music>" + meiNote(["Glo"], label: "1") + "</music>"
        XCTAssertNil(FingeringDiagrams.meiWithFingeringsAbove(mei))
    }

    func testAScoreWithNoVersesIsLeftAlone() {
        XCTAssertNil(FingeringDiagrams.meiWithFingeringsAbove("<music><note pname=\"d\"/></music>"))
    }

    func testTheDiagramSizeIsHalfTheTextItReplaces() {
        // Ali asked for about half the height. It used to come from halving
        // Verovio's shared text size, which also halved every chord name; the
        // scale lives in our own drawing pass now and the text size does not move.
        XCTAssertEqual(FingeringDiagrams.defaultLyricSize, 4.5,
                       "the engraving's text size stays at Verovio's default")
        XCTAssertLessThan(FingeringDiagrams.diagramScale, 1 / 1.9,
                          "Ali asked for about half the height")
    }

    // MARK: - What it leaves alone

    func testALoneUntaggedLyricIsNeverTouched() {
        // a song whose lyric is the word "O" must stay a word
        let lyric = verse(1, "O", tag: "1")
        XCTAssertEqual(FingeringDiagrams.draw(in: lyric), lyric)
    }

    /// Ali's build-126 report: fingerings written by build 125 carry no tag,
    /// because the tag did not exist yet. A renderer that only understands its
    /// own new output leaves those as letters forever, so a full column of
    /// holes counts even untagged.
    func testAnUntaggedColumnFromAnEarlierBuildIsStillDrawn() {
        // six verses on one note, all single holes, numbered rather than tagged
        let column = (1...6).map { verse($0, $0 <= 4 ? "X" : "O", tag: "\($0)") }
            .joined()
        let out = FingeringDiagrams.draw(in: column)
        XCTAssertEqual(out.components(separatedBy: "<path").count - 1, 6,
                       "a 125-era fingering column should draw: \(out)")
        XCTAssertFalse(out.contains("<text"), "no letters should survive")
    }

    /// A second-octave note carries seven verses: six holes and a "+". The
    /// first attempt at the untagged rule required every verse in a run to be a
    /// hole, which rejected every overblown note in the score — 564 letters
    /// left on Ali's page after the rest had become circles.
    func testAnUntaggedColumnWithAnOctaveMarkStillDraws() {
        var column = (1...6).map { verse($0, "X", tag: "\($0)") }
        column.append(verse(7, "+", tag: "7"))
        let out = FingeringDiagrams.draw(in: column.joined())
        XCTAssertEqual(out.components(separatedBy: "<path").count - 1, 6,
                       "six holes should draw: \(out)")
        XCTAssertTrue(out.contains(">+</tspan>"),
                      "the octave mark stays as text, every font has a plus")
    }

    func testAShortUntaggedRunIsLeftAsWords() {
        // four verses is a hymn, not a whistle: below the column threshold
        let hymn = (1...4).map { verse($0, "O", tag: "\($0)") }.joined()
        XCTAssertEqual(FingeringDiagrams.draw(in: hymn), hymn,
                       "four verses is not a fingering column")
    }

    func testColumnsAreSeparatedByTheirNotePosition() {
        // two notes, six holes each: twelve shapes, and neither run bleeds
        let first = (1...6).map { verse($0, "X", tag: "\($0)", x: 2670) }.joined()
        let second = (1...6).map { verse($0, "O", tag: "\($0)", x: 3360) }.joined()
        let out = FingeringDiagrams.draw(in: first + second)
        XCTAssertEqual(out.components(separatedBy: "<path").count - 1, 12)
    }

    func testAMixedRunOfWordsAndHolesIsNotAColumn() {
        // five verses on one note but one of them is a word
        let mixed = (1...5).map { i -> String in
            verse(i, i == 3 ? "la" : "X", tag: "\(i)")
        }.joined()
        XCTAssertEqual(FingeringDiagrams.draw(in: mixed), mixed)
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

    // MARK: - The diagram is scaled here, not by Verovio's shared text size

    /// Build 128 shrank the diagrams by halving Verovio's `lyricSize`, which is
    /// the same option that sizes chord symbols -- so every chord name on a
    /// fingered score rendered at less than half size. The scale belongs here.
    func testTheDiagramIsAboutHalfTheGlyphItReplaces() {
        XCTAssertGreaterThan(FingeringDiagrams.diagramScale, 0.4)
        XCTAssertLessThan(FingeringDiagrams.diagramScale, 0.6)
    }

    func testTheDiagramSizeIsUnchangedFromWhatShipped() {
        // what a hole measured when the option was 2.2 and the proportion 0.28
        let asShipped = 198 * 0.28
        let now = try? XCTUnwrap(radius(of: FingeringDiagrams.draw(in: verse(1, "X", size: 405))))
        XCTAssertEqual(now ?? 0, asShipped, accuracy: 1.5,
                       "the diagrams must look the same size as they did at lyricSize 2.2")
    }

    /// The octave "+" stays text, so it would render at the engraving's full
    /// text size while the circles beside it are scaled -- twice the height of
    /// its own column. It is scaled with them.
    func testTheOctaveMarkScalesWithTheCircles() {
        let column = (1...6).map { verse($0, "X", size: 405) }.joined()
            + verse(7, "+", size: 405)
        let out = FingeringDiagrams.draw(in: column)
        let plus = try? XCTUnwrap(
            out.range(of: "font-size=\"[0-9.]+px\">\\+", options: .regularExpression))
        XCTAssertNotNil(plus, "the octave mark should still be text: \(out)")
        let sizes = matches(of: "font-size=\"([0-9.]+)px\">\\+", in: out)
        XCTAssertEqual(sizes.first ?? 0, 405 * FingeringDiagrams.diagramScale, accuracy: 1,
                       "the octave mark did not scale with its holes")
    }

    private func matches(of pattern: String, in text: String) -> [CGFloat] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { m in
                m.numberOfRanges > 1 ? CGFloat(Double(ns.substring(with: m.range(at: 1))) ?? 0) : nil
            }
    }
}
