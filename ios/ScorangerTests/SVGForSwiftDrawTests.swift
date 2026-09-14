import SwiftDraw
import XCTest

/// The rewrite that turns Verovio's SVG into what SwiftDraw can draw.
///
/// A real score reached the app as "Render failed — Verovio rendered an empty
/// page 1". Verovio had drawn the page perfectly; SwiftDraw parsed Verovio's
/// own output without complaint. THIS rewrite is what made it unparseable, and
/// the error named the wrong culprit, so four theories were chased before the
/// right one.
///
/// The fixture is synthetic: the repository is public, so no committed fixture
/// may carry copyrighted music. It reproduces the shape, not the score.
final class SVGForSwiftDrawTests: XCTestCase {
    private func count(_ s: String, _ needle: String) -> Int {
        s.components(separatedBy: needle).count - 1
    }

    /// A page holding what OMR output holds: a `<text>` with no closing tag,
    /// drawing elements after it, and a normal nested-tspan label later on.
    /// A page holding what OMR output holds: a `<text>` with no closing tag,
    /// drawing elements after it, and a normal nested-tspan label later on.
    ///
    /// `<use>` carries an href because SwiftDraw rejects one without it — the
    /// first version of this fixture had bare `<use x y/>` and failed to parse
    /// before the flattener ever touched it, which proved nothing.
    private func pageWithAnUnclosedText() -> String {
        """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 1000 1000" width="100px" height="100px">
        <defs><g id="note"><path d="M0 0 L4 4" /></g></defs>
        <g class="page-margin">
        <text x="10" y="20" font-size="0px">
        <g class="staff"><path d="M0 0 L100 0" /><use xlink:href="#note" x="5" y="5" /></g>
        <g class="staff"><path d="M0 40 L100 40" /><use xlink:href="#note" x="5" y="45" /></g>
        <g class="chord"><path d="M0 80 L100 80" /><use xlink:href="#note" x="5" y="85" /></g>
        <g id="label" class="label">
        <text x="200" y="300" text-anchor="end" font-size="0px">
        <tspan class="text"><tspan font-size="405px">Voice</tspan></tspan>
        </text>
        </g>
        </g>
        </svg>
        """
    }

    /// The bug: an unclosed `<text>` let the block pattern run to the NEXT
    /// block's `</text>`, and everything in between was dropped by the rewrite.
    func testFlatteningNeverRemovesDrawingElements() {
        let page = pageWithAnUnclosedText()
        let out = SVGForSwiftDraw.flattenTextElements(page)
        XCTAssertEqual(count(out, "<path"), count(page, "<path"),
                       "the rewrite deleted drawing paths")
        XCTAssertEqual(count(out, "<use"), count(page, "<use"),
                       "the rewrite deleted glyph references")
        XCTAssertEqual(count(out, "<g "), count(page, "<g "),
                       "the rewrite deleted groups")
    }

    /// The count that was actually wrong. On the score that exposed this,
    /// 77 `<use>`, 127 `<path>` and 282 `<g>` were deleted -- 43KB of drawing --
    /// because the block pattern ran from an unclosed `<text>` to the next
    /// block's `</text>` and the rewrite discarded everything between.
    ///
    /// The parse-level proof is not here: it was made against a real Verovio
    /// engraving of the score that failed, where the rewritten page went from
    /// unparseable to parseable with every drawing element preserved. This
    /// pins the invariant that made it so, on a fixture that carries no music.
    func testAnUnclosedTextDoesNotSwallowTheRestOfThePage() {
        let page = pageWithAnUnclosedText()
        let out = SVGForSwiftDraw.flattenTextElements(page)
        XCTAssertGreaterThanOrEqual(out.count, Int(Double(page.count) * 0.8),
                                    "the rewrite deleted a large part of the page")
        XCTAssertEqual(out.components(separatedBy: "#note").count - 1, 3,
                       "glyph references between the text blocks were dropped")
    }

    /// And it still does its job: nested tspans become flat positioned text.
    func testItStillFlattensNestedTspans() {
        let out = SVGForSwiftDraw.flattenTextElements(pageWithAnUnclosedText())
        XCTAssertEqual(count(out, "<tspan"), 0, "tspans should be flattened away")
        XCTAssertTrue(out.contains("Voice"), "the label's text must survive")
        XCTAssertTrue(out.contains("405px"),
                      "the size from the inner tspan must be carried onto the text")
    }

    /// A well-formed page must be untouched in the ways that matter.
    func testAWellFormedPageKeepsItsDrawing() {
        let page = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 100 100" width="100" height="100">
        <defs><g id="n"><path d="M0 0 L2 2" /></g></defs>
        <g><path d="M0 0 L10 10" /><use xlink:href="#n" x="1" y="1" /></g>
        <text x="1" y="2" font-size="0px"><tspan font-size="12px">A</tspan></text>
        </svg>
        """
        let out = SVGForSwiftDraw.flattenTextElements(page)
        XCTAssertEqual(count(out, "<path"), count(page, "<path"))
        XCTAssertEqual(count(out, "<use"), count(page, "<use"))
        XCTAssertTrue(out.contains("A"))
    }

    // MARK: - The two faults the vector-renderer comparison found

    /// A real engraving carrying a tempo mark, two directions, a dynamic, a
    /// fingering and measure numbers -- every class Verovio's own stylesheet
    /// styles. Built by `engine/scripts/make_marks_fixture.py`.
    private func marksPage() throws -> String {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: "marks", withExtension: "svg",
                                   subdirectory: "Fixtures") else {
            XCTFail("missing fixture marks.svg")
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Every flattened `<text>` element of a prepared page, as its attributes
    /// plus its content.
    private func texts(in svg: String) -> [(attributes: String, text: String)] {
        var out: [(String, String)] = []
        let ns = svg as NSString
        let re = try! NSRegularExpression(pattern: "<text([^>]*)>([^<]*)</text>")
        for m in re.matches(in: svg, range: NSRange(location: 0, length: ns.length)) {
            out.append((ns.substring(with: m.range(at: 1)),
                        ns.substring(with: m.range(at: 2))))
        }
        return out
    }

    private func text(containing needle: String, in svg: String) throws -> String {
        let found = texts(in: svg).first { $0.text.contains(needle) }
        return try XCTUnwrap(found, "no flattened <text> holds \"\(needle)\"").attributes
    }

    private func fontSize(_ attributes: String) -> Double? {
        guard let r = attributes.range(of: #"font-size="[\d.]+px""#,
                                       options: .regularExpression) else { return nil }
        return Double(attributes[r].dropFirst(11).dropLast(3))
    }

    /// DEFECT 1, live in the shipped build. A tempo mark is one `<text>` of
    /// three runs: a music glyph at 720px, then " = " and the number at 405px.
    /// The flattener took the size of the FIRST run, so `♩. = 138` printed its
    /// digits at 720 -- not far off double what Verovio engraved.
    func testTempoDigitsKeepTheEngravedSizeAndNotTheGlyphs() throws {
        let page = try marksPage()
        // the fault, stated against the raw engraving: the glyph run is first
        // and it is much bigger than the run the digits are in
        XCTAssertTrue(page.contains(#"font-family="Leipzig" font-size="720px""#),
                      "the fixture no longer carries an oversized glyph run")

        let attributes = try text(containing: "138", in: SVGForSwiftDraw.prepare(page))
        let size = try XCTUnwrap(fontSize(attributes),
                                 "the tempo text carries no size at all: \(attributes)")
        XCTAssertEqual(size, 405, accuracy: 0.5,
                       "the tempo digits are drawn at \(size)px; Verovio engraved "
                       + "them at 405px, and 720px is the music glyph's size")
    }

    /// The rule behind it, on a fixture small enough to read: a music-font run
    /// does not decide how the words beside it are sized.
    func testAMusicGlyphDoesNotSizeTheWordsBesideIt() {
        let page = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100">
        <text x="10" y="20" font-size="0px">
        <tspan class="rend"><tspan font-family="Leipzig" font-size="720px">Q</tspan></tspan>
        <tspan class="text"><tspan font-size="405px">60</tspan></tspan>
        </text>
        </svg>
        """
        let attributes = texts(in: SVGForSwiftDraw.flattenTextElements(page))
            .first { $0.text.contains("60") }?.attributes ?? ""
        XCTAssertEqual(fontSize(attributes), 405,
                       "the words took the glyph's size: \(attributes)")
        XCTAssertFalse(attributes.contains("Leipzig"),
                       "and they were asked for in the music font too: \(attributes)")
    }

    /// DEFECT 2, live in the shipped build. Verovio's stylesheet sets
    /// `g.dir`, `g.dynam` and `g.mNum` italic and `g.ending`, `g.fing`,
    /// `g.reh`, `g.tempo` bold. SwiftDraw reads neither the stylesheet -- its
    /// selectors stop short of `#id g.dir` -- nor `font-style`, which its DOM
    /// does not have. Every one of them was drawn upright.
    func testTheStylesheetsFacesReachTheText() throws {
        let prepared = SVGForSwiftDraw.prepare(try marksPage())

        let italicFace = try XCTUnwrap(SVGForSwiftDraw.faces["serif-italic"],
                                       "no italic serif face resolves on this platform; "
                                       + "candidates: \(SVGForSwiftDraw.faceCandidates)")
        let boldFace = try XCTUnwrap(SVGForSwiftDraw.faces["serif-bold"],
                                     "no bold serif face resolves on this platform")
        print("MARKS: italic=\(italicFace) bold=\(boldFace)")

        for needle in ["dolce", "rit."] {
            let attributes = try text(containing: needle, in: prepared)
            XCTAssertTrue(attributes.contains(#"font-style="italic""#),
                          "\"\(needle)\" is a direction and is engraved italic: \(attributes)")
            XCTAssertTrue(attributes.contains("font-family=\"\(italicFace)\""),
                          "...and italic has to arrive as a font NAME, because "
                          + "SwiftDraw has no font-style: \(attributes)")
        }

        let tempo = try text(containing: "138", in: prepared)
        XCTAssertTrue(tempo.contains(#"font-weight="bold""#),
                      "a tempo mark is engraved bold: \(tempo)")
        // ...but it is NOT given a font NAME, because it carries two SMuFL
        // metronome glyphs and a named font has no cascade to draw them with.
        // The note beats the weight; see the note in `closeGroup`.
        XCTAssertFalse(tempo.contains(boldFace),
                       "the tempo text was named a real font, which takes the "
                       + "metronome glyph's fallback away: \(tempo)")

        let fingering = try text(containing: "m", in: prepared)
        XCTAssertTrue(fingering.contains("font-family=\"\(boldFace)\""),
                      "a fingering mark is engraved bold: \(fingering)")
    }

    /// Measure numbers are the third italic class, and they are on every bar.
    func testMeasureNumbersAreItalic() throws {
        let prepared = SVGForSwiftDraw.prepare(try marksPage())
        let numbers = texts(in: prepared).filter {
            $0.attributes.contains("font-size=\"324px\"") || $0.text == "5"
        }
        XCTAssertFalse(numbers.isEmpty, "no measure numbers on the page at all")
        let face = try XCTUnwrap(SVGForSwiftDraw.faces["serif-italic"])
        for number in numbers {
            XCTAssertTrue(number.attributes.contains("font-family=\"\(face)\""),
                          "measure number \"\(number.text)\" is upright: \(number.attributes)")
        }
    }

    /// The face is not a string in a file: it has to change what is DRAWN.
    ///
    /// SwiftDraw resolves a font-family through `CTFontCreateWithName` and
    /// silently falls back to plain Times when the name does not resolve -- so
    /// a name that is merely written down proves nothing. These two pages
    /// differ in exactly one attribute, and the pixels have to differ with it.
    func testAnItalicFaceChangesWhatIsDrawn() throws {
        func page(_ family: String, _ word: String) -> String {
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 60" width="200" height="60">
            <text x="10" y="40" font-family="\(family)" font-size="30px">\(word)</text>
            </svg>
            """
        }
        func drawn(_ family: String, _ word: String = "dolce") throws -> Data {
            let svg = try XCTUnwrap(SVG(data: Data(page(family, word).utf8)),
                                    "\(family) would not parse")
            return try XCTUnwrap(svg.rasterize(scale: 2).pngData())
        }
        let upright = try drawn("Times-Roman")
        let italicFace = try XCTUnwrap(SVGForSwiftDraw.faces["serif-italic"])
        let boldFace = try XCTUnwrap(SVGForSwiftDraw.faces["serif-bold"])
        // the control: if THIS does not differ, nothing is drawing text and
        // the comparison below would pass for the wrong reason
        XCTAssertNotEqual(upright, try drawn("Times-Roman", "dolcz"),
                          "two different words drew the same pixels -- "
                          + "no text is reaching the page at all")
        XCTAssertNotEqual(upright, try drawn(italicFace),
                          "\(italicFace) drew the same pixels as upright text: "
                          + "the name did not resolve and SwiftDraw fell back")
        XCTAssertNotEqual(upright, try drawn(boldFace),
                          "\(boldFace) drew the same pixels as upright text")
    }

    /// And the page still parses and still draws after both passes.
    func testThePreparedMarksPageStillDraws() throws {
        let prepared = SVGForSwiftDraw.prepare(try marksPage())
        let parsed = try XCTUnwrap(SVG(data: Data(prepared.utf8)),
                                   "the prepared page would not parse")
        XCTAssertNotNil(try? parsed.pdfData(), "the prepared page would not draw")
    }
}
