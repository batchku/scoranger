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
}
