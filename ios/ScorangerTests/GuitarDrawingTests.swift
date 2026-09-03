import Foundation
import SwiftDraw
import XCTest

// No import of the app module: this bundle compiles the ScoreModel sources in.

/// What the guitar work draws has to survive the trip to the page.
///
/// The whistle's circles are drawn as paths because the rasteriser's fallback
/// font has no filled circle and engraved empty boxes; the grid, the dots and
/// the barre are drawn for the same reason. The fret numbers and the "5 fr."
/// label are the exception -- they are digits -- and this is where that claim
/// is tested rather than assumed: the page is put through the same rewrite the
/// renderer uses and then through SwiftDraw itself, which is what actually
/// draws it on the iPad.
final class GuitarDrawingTests: XCTestCase {

    /// A page carrying one reserved chord-diagram block and one tab column, in
    /// the shape Verovio emits them.
    private func page() -> String {
        let diagram = """
        <g id="d1" class="dir"><title class="labelAttr">[x,3,2,0,1,0]</title>\
        <text x="638" y="1443" font-size="0px">\
        <tspan class="text" x="638" y="1443"> </tspan>\
        <tspan class="text" x="638" y="1833"> </tspan>\
        <tspan class="text" x="638" y="2223"> </tspan></text></g>
        """
        let tab = ["0", "-", "-", "2", "-", "-"].enumerated().map { row, text in
            """
            <g class="verse"><title class="labelAttr">gt</title><g class="syl">\
            <text x="638" y="\(3000 + row * 390)"><tspan class="text">\
            <tspan font-size="405px">\(text)</tspan></tspan></text></g></g>
            """
        }.joined()
        return """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" \
        width="800px" height="500px">
        <svg class="definition-scale" viewBox="0 0 8000 5000">
        <g class="page-margin"><g class="staff"><path d="M0 2600 L8000 2600" /></g>
        \(diagram)\(tab)</g></svg></svg>
        """
    }

    func testTheDrawingReachesTheDeviceRenderer() throws {
        let prepared = SVGForSwiftDraw.prepare(page())
        // the grid and the tab staff are shapes by now, not text
        XCTAssertTrue(prepared.contains("chord-diagram"))
        XCTAssertTrue(prepared.contains("verse tab"))
        XCTAssertFalse(prepared.contains("labelAttr"),
                       "the markers themselves must not reach the page")
        // ...and the numbers are still text, which is the one thing the
        // fallback font is trusted with
        XCTAssertTrue(prepared.contains(">3</"), "a fret number in the diagram")
        XCTAssertTrue(prepared.contains(">2</"), "a fret number in the tab")

        // the fixture has to be parseable BEFORE the rewrite, or this proves
        // nothing about the rewrite
        XCTAssertNotNil(SVG(data: Data(page().utf8)), "the fixture itself must parse")
        // SwiftDraw is what draws this on the iPad. A <circle> came out of it
        // as nothing at all once, which is why everything here is paths.
        let parsed = try XCTUnwrap(SVG(data: Data(prepared.utf8)),
                                   "SwiftDraw could not parse the drawn page")
        let pdf = try parsed.pdfData()
        XCTAssertGreaterThan(pdf.count, 0)
    }

    func testAPageWithNeitherIsLeftAlone() {
        let plain = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">\
        <g class="staff"><path d="M0 0 L100 0" /></g></svg>
        """
        let prepared = SVGForSwiftDraw.prepare(plain)
        XCTAssertFalse(prepared.contains("chord-diagram"))
        XCTAssertFalse(prepared.contains("verse tab"))
        XCTAssertTrue(prepared.contains("<path"))
    }
}
