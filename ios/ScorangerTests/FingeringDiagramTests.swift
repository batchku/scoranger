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
        let out = try XCTUnwrap(FingeringDiagrams.meiWithFingeringsAbove(mei, rows: 6),
                               "a fingering column should be moved")
        XCTAssertEqual(out.components(separatedBy: "place=\"above\"").count - 1, 6)
    }

    /// Fingerings written before the tag existed have to move too, or Ali's
    /// score keeps them below the staff for ever.
    func testAnUntaggedColumnIsAlsoMovedAbove() throws {
        let mei = "<music>" + meiNote(["X", "X", "X", "X", "X", "O"], label: "1") + "</music>"
        let out = try XCTUnwrap(FingeringDiagrams.meiWithFingeringsAbove(mei, rows: 6))
        XCTAssertEqual(out.components(separatedBy: "place=\"above\"").count - 1, 6)
    }

    /// A fingered note inside a chord hangs its verses off the <chord>, which is
    /// most of a piano or accordion part — scanning only <note> missed them all.
    func testVersesOnAChordAreMovedToo() throws {
        let mei = "<music>" + meiNote(["X", "X", "X", "O", "O", "O"], element: "chord")
            + "</music>"
        let out = try XCTUnwrap(FingeringDiagrams.meiWithFingeringsAbove(mei, rows: 6))
        XCTAssertEqual(out.components(separatedBy: "place=\"above\"").count - 1, 6)
    }

    func testTheOctaveMarkTravelsWithItsColumn() throws {
        let mei = "<music>" + meiNote(["X", "X", "X", "X", "X", "X", "+"]) + "</music>"
        let out = try XCTUnwrap(FingeringDiagrams.meiWithFingeringsAbove(mei, rows: 6))
        XCTAssertEqual(out.components(separatedBy: "place=\"above\"").count - 1, 7,
                       "the + belongs to the column and moves with it")
    }

    // MARK: the band, packed (0.13.0)
    //
    // Ali: "too much space above penny whistle tablatures, so scores that have
    // it end up fitting very few lines on a page." Verovio reserves a lyric
    // line per verse and the column is drawn in half that height, so the
    // default now hands Verovio four lines for the six holes -- the tightest
    // the drawn column fits inside without reaching toward the system above.
    // The placement tests above pin rows: 6, the layout they were written for.

    func testTheDefaultPacksSixHolesIntoFourRows() throws {
        let mei = "<music>" + meiNote(["X", "X", "X", "O", "O", "O"]) + "</music>"
        let out = try XCTUnwrap(FingeringDiagrams.meiWithFingeringsAbove(mei))
        XCTAssertEqual(out.components(separatedBy: "<verse").count - 1, 4,
                       "four lines reserved, not six")
        XCTAssertEqual(out.components(separatedBy: "place=\"above\"").count - 1, 4)
        XCTAssertTrue(out.contains("label=\"wf|XXXOOO\""),
                      "the whole column rides in the first verse's label")
    }

    /// The octave keeps its own line below the holes, as six-or-seven always
    /// did, so every column's last hole stays on one baseline.
    func testTheOctaveMarkKeepsItsOwnRowWhenPacked() throws {
        let mei = "<music>" + meiNote(["X", "X", "X", "X", "X", "X", "+"]) + "</music>"
        let out = try XCTUnwrap(FingeringDiagrams.meiWithFingeringsAbove(mei))
        XCTAssertEqual(out.components(separatedBy: "<verse").count - 1, 5)
        XCTAssertTrue(out.contains("label=\"wf|XXXXXX+\""))
    }

    /// Six rows is the old layout exactly: nothing packed, nothing relabelled.
    func testSixRowsIsTheLayoutEveryEarlierBuildDrew() throws {
        let mei = "<music>" + meiNote(["X", "X", "X", "O", "O", "O"]) + "</music>"
        let out = try XCTUnwrap(FingeringDiagrams.meiWithFingeringsAbove(mei, rows: 6))
        XCTAssertEqual(out.components(separatedBy: "<verse").count - 1, 6)
        XCTAssertFalse(out.contains(FingeringDiagrams.packedPrefix))
    }

    /// A sung word is never packed, whatever the rows.
    func testWordsAreNeverPacked() {
        let mei = "<music>" + meiNote(["la", "la", "la", "la", "la", "la"]) + "</music>"
        XCTAssertNil(FingeringDiagrams.meiWithFingeringsAbove(mei))
    }

    /// The two renderers must draw the same circles from the same page. The
    /// page is a real Verovio engraving with packed columns and the circles are
    /// what render.py drew from it -- both cut by check_staff_spacing.py
    /// --write. A change made in one renderer and not the other fails here.
    func testDrawsThePackedColumnsExactlyAsThePDFDoes() throws {
        let bundle = Bundle(for: Self.self)
        let input = try XCTUnwrap(bundle.url(forResource: "fingering-packed-input",
                                             withExtension: "svg", subdirectory: "Fixtures"))
        let golden = try XCTUnwrap(bundle.url(forResource: "fingering-packed-golden",
                                              withExtension: "txt", subdirectory: "Fixtures"))
        let page = try String(contentsOf: input, encoding: .utf8)
        XCTAssertTrue(page.contains(FingeringDiagrams.packedPrefix),
                      "the golden page must carry packed columns")
        let expected = try String(contentsOf: golden, encoding: .utf8)
            .split(separator: "\n").map { $0.split(separator: "|").map(String.init) }
        let drawn = FingeringDiagrams.draw(in: page)
        let re = try NSRegularExpression(
            pattern: "<path d=\"M (-?[\\d.]+) (-?[\\d.]+) A ([\\d.]+) [\\d.]+ 0 1 0 [^\"]*\"[^>]*fill=\"(currentColor|none)\"")
        let ns = drawn as NSString
        let got = re.matches(in: drawn, range: NSRange(location: 0, length: ns.length)).map { m in
            (1...4).map { ns.substring(with: m.range(at: $0)) }
        }
        XCTAssertEqual(got.count, expected.count, "a different number of holes")
        for (index, (have, want)) in zip(got, expected).enumerated() {
            for axis in 0..<3 {
                XCTAssertEqual(Double(have[axis])!, Double(want[axis])!, accuracy: 0.01,
                               "hole \(index), \(["x", "y", "radius"][axis])")
            }
            XCTAssertEqual(have[3], want[3], "hole \(index) fill")
        }
        XCTAssertFalse(drawn.range(of: ">[XO/]</tspan>", options: .regularExpression) != nil,
                       "a hole was left on the page as a letter")
    }

    func testASungLyricIsNotMoved() {
        let mei = "<music>" + meiNote(["Glo"], label: "1") + "</music>"
        XCTAssertNil(FingeringDiagrams.meiWithFingeringsAbove(mei, rows: 6))
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

    // MARK: - Where the column lands

    /// Ali's screenshot: a wide gap between the staff and the diagrams under
    /// it. The column is about half as tall as the space Verovio laid out, so
    /// which end stays put decides where the saved height goes. Held at the
    /// TOP, every row below rises and the lowest hole floats. Held at the
    /// BOTTOM, the diagrams stay against their staff and the space comes off
    /// the top -- away from the system above, which is the safe direction.
    ///
    /// Mirrors engine/scoranger_engine/render.py; engine/scripts/check_render.py
    /// asserts the same thing off a real engraving.
    func testTheColumnHangsFromItsBottomRow() {
        let top: CGFloat = 1000
        let column = (1...6)
            .map { verse($0, "X", y: Int(top) + ($0 - 1) * Int(verovioPitch)) }
            .joined()
        let out = FingeringDiagrams.draw(in: column)
        let cys = matches(of: "M [-0-9.]+ ([-0-9.]+) A", in: out).sorted()
        XCTAssertEqual(cys.count, 6, "every hole should be drawn: \(out)")

        let (pitch, radius) = FingeringDiagrams.holeGeometry(rowPitch: verovioPitch)
        let lastVerseY = top + 5 * verovioPitch
        let expectedBottom = lastVerseY - FingeringDiagrams.centreYVsRadius * radius
        XCTAssertEqual(cys.last ?? 0, expectedBottom, accuracy: 1,
                       "the bottom hole must stay where its verse was, against the staff")
        XCTAssertEqual((cys.last ?? 0) - (cys.first ?? 0), 5 * pitch, accuracy: 1)
        // and the column only ever got shorter, so the top moved DOWN
        XCTAssertGreaterThan(cys.first ?? 0,
                             top - FingeringDiagrams.centreYVsRadius * radius,
                             "the column grew upward, toward the system above")
    }

    /// A hole becomes a circle whose centre is offset from the verse's text
    /// anchor, so a "+" left at that anchor hangs to one side of the circles it
    /// belongs to. Worse, Verovio centres each verse on its OWN glyph width, so
    /// the "+" is not even at the holes' x: on a real page two notes came out a
    /// third of a hole further off. The column has one axis and every row is
    /// drawn on it.
    func testTheOctaveMarkIsCentredOnItsColumn() {
        let holeX = 2670
        let column = (1...6)
            .map { verse($0, "X", x: holeX, y: 1000 + ($0 - 1) * Int(verovioPitch)) }
            .joined()
            // Verovio's own placement for the "+" glyph: near, but not equal
            + verse(7, "+", x: holeX + 37, y: 1000 + 6 * Int(verovioPitch))
        let out = FingeringDiagrams.draw(in: column)

        let cxs = Set(matches(of: "M ([-0-9.]+) [-0-9.]+ A", in: out)
            .map { $0 + (radius(of: out) ?? 0) }.map { round($0) })
        XCTAssertEqual(cxs.count, 1, "the holes should share one axis: \(cxs)")

        // (?s) so "." reaches across the newlines inside a <text> block
        let plusX = matches(of: "(?s)<text[^>]*?x=\"([-0-9.]+)\"[^>]*>(?:(?!</text>).)*?>\\+<",
                            in: out)
        XCTAssertEqual(plusX.count, 1, "the octave mark should still be there: \(out)")
        let (_, r) = FingeringDiagrams.holeGeometry(rowPitch: verovioPitch)
        XCTAssertEqual(plusX.first ?? 0, cxs.first ?? 0, accuracy: r / 4,
                       "the octave mark is not under the circles it belongs to")
        XCTAssertTrue(out.contains("text-anchor=\"middle\""),
                      "without it the glyph's own width pushes it off again")
    }

    /// #43: within one row above the staff, some diagrams sat higher and some
    /// lower. A column is anchored on its bottom row, and a column's bottom
    /// row is the octave "+" when it has one -- so every fingered-octave note
    /// hung a whole lyric pitch below the notes either side of it.
    func testAColumnWithAnOctaveMarkSitsOnTheSameBaselineAsOneWithout() {
        let top = 1000
        let plain = (1...6).map {
            verse($0, "X", x: 2670, y: top + ($0 - 1) * Int(verovioPitch))
        }.joined()
        let octaved = (1...6).map {
            verse($0 + 10, "X", x: 3400, y: top + ($0 - 1) * Int(verovioPitch))
        }.joined()
            + verse(17, "+", x: 3400, y: top + 6 * Int(verovioPitch))

        let out = FingeringDiagrams.draw(in: plain + octaved)
        var columns: [CGFloat: [CGFloat]] = [:]
        for (x, y) in circleCentres(in: out) {
            columns[round(x), default: []].append(y)
        }
        XCTAssertEqual(columns.count, 2, "expected two columns: \(columns.keys)")
        let bottoms = columns.values.map { $0.max() ?? 0 }.sorted()
        XCTAssertEqual(bottoms.first ?? 0, bottoms.last ?? 0, accuracy: 1,
                       "the two columns' lowest holes are \(bottoms) -- a "
                       + "diagram carrying a '+' dropped below its neighbour")
    }

    /// ...and the "+" still hangs BELOW that shared baseline, where it belongs.
    func testTheOctaveMarkHangsBelowTheSharedBaseline() {
        let top = 1000
        let column = (1...6).map {
            verse($0, "X", x: 2670, y: top + ($0 - 1) * Int(verovioPitch))
        }.joined() + verse(7, "+", x: 2670, y: top + 6 * Int(verovioPitch))
        let out = FingeringDiagrams.draw(in: column)
        let lowestHole = circleCentres(in: out).map(\.1).max() ?? 0
        let plusY = matches(of: "(?s)<text[^>]*y=\"([-0-9.]+)\"[^>]*>(?:(?!</text>).)*?>\\+<",
                            in: out).first ?? 0
        XCTAssertGreaterThan(plusY, lowestHole,
                             "the octave mark should sit under the holes, not among them")
    }

    private func circleCentres(in svg: String) -> [(CGFloat, CGFloat)] {
        guard let re = try? NSRegularExpression(
                pattern: "M ([-0-9.]+) ([-0-9.]+) A ([0-9.]+)") else { return [] }
        let ns = svg as NSString
        return re.matches(in: svg, range: NSRange(location: 0, length: ns.length))
            .compactMap { m in
                guard m.numberOfRanges > 3,
                      let x = Double(ns.substring(with: m.range(at: 1))),
                      let y = Double(ns.substring(with: m.range(at: 2))),
                      let r = Double(ns.substring(with: m.range(at: 3))) else { return nil }
                return (CGFloat(x + r), CGFloat(y))   // path starts at the left edge
            }
    }

    private func matches(of pattern: String, in text: String) -> [CGFloat] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { m in
                m.numberOfRanges > 1 ? CGFloat(Double(ns.substring(with: m.range(at: 1))) ?? 0) : nil
            }
    }

    // MARK: - How big the diagram is, and how tightly it is stacked

    /// Ali asked for the column to lose about half its footprint while each
    /// hole got BIGGER -- just under a notehead. Those pull against each other,
    /// which is why circle size and row spacing are now decided separately
    /// instead of both coming from the verse's font size.
    ///
    /// Mirrors engine/scoranger_engine/render.py; engine/scripts/check_render.py
    /// measures the same numbers off a real engraving.

    /// The pitch Verovio lays verses out at, measured on a real page.
    private let verovioPitch: CGFloat = 400
    /// A notehead on that same page.
    private let notehead: CGFloat = 217
    /// What a hole used to be drawn at.
    private let oldDiameter: CGFloat = 111

    func testTheColumnLosesAboutHalfItsFootprint() {
        let (pitch, _) = FingeringDiagrams.holeGeometry(rowPitch: verovioPitch)
        let shrunk = pitch / verovioPitch
        XCTAssertGreaterThanOrEqual(shrunk, 0.40)
        XCTAssertLessThanOrEqual(shrunk, 0.50, "the column was asked to be 40-50%")
    }

    func testAHoleIsALittleSmallerThanANotehead() {
        let (_, radius) = FingeringDiagrams.holeGeometry(rowPitch: verovioPitch)
        let fraction = radius * 2 / notehead
        XCTAssertGreaterThan(fraction, 0.65, "too small to read at speed")
        XCTAssertLessThan(fraction, 1.0, "a hole must not be as big as a note")
    }

    /// The half of the request that is easy to lose while shrinking the column.
    func testTheHolesGotBiggerNotSmaller() {
        let (_, radius) = FingeringDiagrams.holeGeometry(rowPitch: verovioPitch)
        XCTAssertGreaterThan(radius * 2, oldDiameter)
    }

    func testTheHolesDoNotTouchOnceTheRowsAreTightened() {
        let (pitch, radius) = FingeringDiagrams.holeGeometry(rowPitch: verovioPitch)
        XCTAssertGreaterThan(pitch, radius * 2,
                             "a stack of touching circles reads as a bar, not as holes")
    }

    func testEverythingScalesWithTheStaff() {
        let (small, r1) = FingeringDiagrams.holeGeometry(rowPitch: 200)
        let (large, r2) = FingeringDiagrams.holeGeometry(rowPitch: 800)
        XCTAssertEqual(large / small, 4, accuracy: 0.001)
        XCTAssertEqual(r2 / r1, 4, accuracy: 0.001)
    }

    // MARK: - Reading the row pitch off a column

    /// The octave "+" hangs further below than the holes are apart, so
    /// averaging across the whole column stretched the pitch -- and with it the
    /// circles, which came out half again too big on any column carrying one.
    func testThePitchIgnoresTheOctaveMarkHangingBelow() {
        let holes: [CGFloat] = [100, 500, 900, 1300, 1700, 2100]
        let withPlus = holes + [3000]
        XCTAssertEqual(FingeringDiagrams.rowPitch(of: withPlus), 400,
                       "the '+' row stretched the measured pitch")
    }

    func testAnEvenColumnGivesItsOwnSpacing() {
        XCTAssertEqual(FingeringDiagrams.rowPitch(of: [0, 400, 800, 1200]), 400)
    }

    func testNothingToMeasureGivesZeroRatherThanAGuess() {
        XCTAssertEqual(FingeringDiagrams.rowPitch(of: []), 0)
        XCTAssertEqual(FingeringDiagrams.rowPitch(of: [100]), 0)
    }
}
