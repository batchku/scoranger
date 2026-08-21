import CoreGraphics
import XCTest

/// Phase A of the selectable vector score: does the model actually know where
/// every element is, and can it name one durably?
///
/// Fixtures come from engine/scripts/make_test_fixture.py: a synthetic
/// four-staff score with chord symbols and ties, rendered twice from
/// independent Verovio loads. Synthetic because the repository is public and
/// committed fixtures must not carry copyrighted music; a pair because the ids
/// differ between the two, so a test that passes on both cannot be leaning on
/// them.
final class ScoreModelTests: XCTestCase {

    private func fixture(_ name: String, _ ext: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: name, withExtension: ext,
                                   subdirectory: "Fixtures") else {
            XCTFail("missing fixture \(name).\(ext)")
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func geometry(_ tag: String) throws -> ScoreGeometry {
        try ScoreModelBuilder.build(svgPages: [try fixture("fixture-\(tag)", "svg")],
                                    mei: try fixture("fixture-\(tag)", "mei"))
    }

    // MARK: geometry

    func testParsesPageSizeAndElements() throws {
        let model = try geometry("a")
        let page = try XCTUnwrap(model.page(0))
        XCTAssertGreaterThan(page.size.width, 0)
        XCTAssertGreaterThan(page.size.height, 0)
        // exact counts: the fixture is generated, so these are known quantities
        // (4 bars x 4 beats x 4 staves = 64 notes, 4 bars, 4 chord symbols)
        XCTAssertEqual(page.elements.filter { $0.kind == .note }.count, 64)
        XCTAssertEqual(page.elements.filter { $0.kind == .measure }.count, 4)
        XCTAssertEqual(page.elements.filter { $0.kind == .harm }.count, 4)
    }

    func testEveryElementHasFiniteNonEmptyGeometry() throws {
        let page = try XCTUnwrap(try geometry("a").page(0))
        for element in page.elements {
            XCTAssertTrue(element.frame.width.isFinite && element.frame.height.isFinite,
                          "\(element.kind) \(element.sessionID) has non-finite bounds")
            XCTAssertFalse(element.frame.isNull, "\(element.sessionID) has null bounds")
            XCTAssertGreaterThan(element.frame.width * element.frame.height, 0,
                                 "\(element.kind) \(element.sessionID) has zero area")
        }
    }

    func testElementsSitInsideTheirMeasure() throws {
        let page = try XCTUnwrap(try geometry("a").page(0))
        let measures = page.elements.filter { $0.kind == .measure }
        let notes = page.elements.filter { $0.kind == .note }
        XCTAssertFalse(measures.isEmpty)
        XCTAssertFalse(notes.isEmpty)
        // every note should fall within some measure's box, which is the
        // clearest single check that transforms were composed correctly
        let orphans = notes.filter { note in
            !measures.contains { $0.frame.insetBy(dx: -2, dy: -2).contains(note.frame.origin) }
        }
        XCTAssertTrue(orphans.isEmpty,
                      "\(orphans.count) notes fell outside every measure box")
    }

    // MARK: semantics

    func testNotesCarryMusicalAddresses() throws {
        let page = try XCTUnwrap(try geometry("a").page(0))
        let notes = page.elements.filter { $0.kind == .note }
        let addressed = notes.filter { $0.address != nil }
        XCTAssertEqual(addressed.count, notes.count,
                       "every note in the MEI should resolve to an address")
        let address = try XCTUnwrap(addressed.first?.address)
        XCTAssertGreaterThan(address.measure, 0)
        XCTAssertGreaterThan(address.staff, 0)
        XCTAssertEqual(address.kind, .note)
    }

    func testAddressesAreUniquePerElement() throws {
        let model = try geometry("a")
        let addresses = model.pages.flatMap { $0.elements.compactMap(\.address) }
        XCTAssertEqual(Set(addresses).count, addresses.count,
                       "two elements share an address, so ordinal disambiguation is wrong")
    }

    func testAddressRoundTripsThroughLookup() throws {
        let model = try geometry("a")
        let note = try XCTUnwrap(model.pages.first?.elements.first { $0.kind == .note })
        let address = try XCTUnwrap(note.address)
        XCTAssertEqual(model.element(at: address)?.sessionID, note.sessionID)
    }

    // MARK: the durability claim

    /// Verovio regenerates ids on every load. The whole design rests on
    /// addresses surviving that, so prove both halves: ids differ, addresses
    /// do not.
    func testAddressesSurviveAReRenderThatChangesEveryID() throws {
        let a = try geometry("a")
        let b = try geometry("b")

        let idsA = Set(a.pages.flatMap { $0.elements.map(\.sessionID) })
        let idsB = Set(b.pages.flatMap { $0.elements.map(\.sessionID) })
        XCTAssertTrue(idsA.isDisjoint(with: idsB),
                      "fixtures must come from independent loads with distinct ids")

        let addressesA = Set(a.pages.flatMap { $0.elements.compactMap(\.address) })
        let addressesB = Set(b.pages.flatMap { $0.elements.compactMap(\.address) })
        XCTAssertEqual(addressesA, addressesB,
                       "addresses must be identical across renders — this is what "
                       + "makes a selection persistable")

        // and a selection made in one session resolves in the other
        let noteA = try XCTUnwrap(a.pages.first?.elements.first { $0.kind == .note })
        let address = try XCTUnwrap(noteA.address)
        let resolved = try XCTUnwrap(b.element(at: address),
                                     "an address from session A did not resolve in session B")
        XCTAssertNotEqual(resolved.sessionID, noteA.sessionID, "ids should differ")
        XCTAssertEqual(resolved.address, noteA.address)
    }

    func testGeometryIsStableAcrossRenders() throws {
        let a = try XCTUnwrap(try geometry("a").page(0))
        let b = try XCTUnwrap(try geometry("b").page(0))
        XCTAssertEqual(a.size, b.size)
        XCTAssertEqual(a.elements.count, b.elements.count)
    }

    // MARK: hit-testing

    func testPointHitTestPrefersTheSmallestElement() throws {
        let page = try XCTUnwrap(try geometry("a").page(0))
        let note = try XCTUnwrap(page.elements.first { $0.kind == .note })
        let hit = try XCTUnwrap(page.element(at: CGPoint(x: note.frame.midX,
                                                        y: note.frame.midY)))
        // a measure encloses the note, so without the smallest-wins rule this
        // would return the bar
        XCTAssertNotEqual(hit.kind, .measure,
                          "point hit-testing returned the enclosing measure")
    }

    func testKindFilterRestrictsResults() throws {
        let page = try XCTUnwrap(try geometry("a").page(0))
        let whole = CGRect(origin: .zero, size: page.size)
        let onlyNotes = page.elements(in: whole, kinds: ScoreElementKind.noteLike)
        XCTAssertFalse(onlyNotes.isEmpty)
        XCTAssertTrue(onlyNotes.allSatisfy { ScoreElementKind.noteLike.contains($0.kind) })

        let onlyBars = page.elements(in: whole, kinds: ScoreElementKind.barLike)
        XCTAssertFalse(onlyBars.isEmpty)
        XCTAssertTrue(onlyBars.allSatisfy { $0.kind == .measure })
    }

    func testRectQueryFindsAKnownElement() throws {
        let page = try XCTUnwrap(try geometry("a").page(0))
        let note = try XCTUnwrap(page.elements.first { $0.kind == .note })
        let found = page.elements(in: note.frame.insetBy(dx: -1, dy: -1))
        XCTAssertTrue(found.contains { $0.sessionID == note.sessionID })
    }

    func testLassoSelectsWhatItEnclosesAndNothingElse() throws {
        let page = try XCTUnwrap(try geometry("a").page(0))
        let note = try XCTUnwrap(page.elements.first { $0.kind == .note })

        // a loop drawn snugly around one notehead
        let box = note.frame.insetBy(dx: -note.frame.width, dy: -note.frame.height)
        let lasso = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                     CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
        let caught = page.elements(inLasso: lasso, kinds: ScoreElementKind.noteLike)
        XCTAssertTrue(caught.contains { $0.sessionID == note.sessionID },
                      "the lasso missed the note it was drawn around")

        // and a loop off in empty space catches nothing
        let empty = [CGPoint(x: -500, y: -500), CGPoint(x: -400, y: -500),
                     CGPoint(x: -400, y: -400), CGPoint(x: -500, y: -400)]
        XCTAssertTrue(page.elements(inLasso: empty).isEmpty)
    }

    func testDegenerateLassoSelectsNothing() throws {
        let page = try XCTUnwrap(try geometry("a").page(0))
        XCTAssertTrue(page.elements(inLasso: []).isEmpty)
        XCTAssertTrue(page.elements(inLasso: [.zero, CGPoint(x: 10, y: 10)]).isEmpty,
                      "two points are not a polygon")
    }

    // MARK: selection -> chat

    func testSelectionDescribesItselfInBarsAndStaves() throws {
        let page = try XCTUnwrap(try geometry("a").page(0))
        let notes = Array(page.elements.filter { $0.kind == .note }.prefix(6))
        let selection = ScoreSelection(notes)
        XCTAssertFalse(selection.isEmpty)
        XCTAssertFalse(selection.bars.isEmpty)
        let described = try XCTUnwrap(selection.chatDescription)
        XCTAssertTrue(described.contains("bar"), described)
        XCTAssertTrue(described.contains("staff") || described.contains("staves"), described)
        // no pixels, no estimates: this is what replaces "≈ bars 12–15"
        XCTAssertFalse(described.contains("≈"))
    }

    func testEmptySelectionHasNoChatDescription() {
        XCTAssertNil(ScoreSelection([]).chatDescription)
        XCTAssertTrue(ScoreSelection([]).isEmpty)
    }

    // MARK: a harder score

    /// The fixture is four staves with chord symbols and ties: the material
    /// the "other" picker will need, and a real test of transform composition
    /// across staves.
    func testComplexScoreIndexesChordSymbolsAndMultipleStaves() throws {
        let model = try ScoreModelBuilder.build(
            svgPages: [try fixture("fixture-a", "svg")],
            mei: try fixture("fixture-a", "mei"))
        let page = try XCTUnwrap(model.page(0))

        let harm = page.elements.filter { $0.kind == .harm }
        XCTAssertFalse(harm.isEmpty, "chord symbols were not indexed")
        XCTAssertTrue(harm.allSatisfy { $0.address != nil },
                      "chord symbols should carry addresses even though MEI puts "
                      + "them under the measure rather than inside a layer")

        let staves = Set(page.elements.compactMap { $0.address?.staff })
        XCTAssertGreaterThanOrEqual(staves.count, 4,
                                    "a quartet page should span at least four staves, saw \(staves)")

        // bars must come out as real numbers, ascending across the page
        let bars = model.bars(of: page.elements)
        XCTAssertGreaterThan(bars.count, 1)
        XCTAssertEqual(bars, bars.sorted())
        XCTAssertGreaterThan(bars.first ?? 0, 0)
    }

    func testComplexScoreLassoAcrossOneStaffStaysOnThatStaff() throws {
        let model = try ScoreModelBuilder.build(
            svgPages: [try fixture("fixture-a", "svg")],
            mei: try fixture("fixture-a", "mei"))
        let page = try XCTUnwrap(model.page(0))
        let topStaff = try XCTUnwrap(page.elements
            .filter { $0.kind == .note && $0.address?.staff == 1 }
            .min { $0.frame.minY < $1.frame.minY })

        // a wide, shallow loop along that staff only
        let band = CGRect(x: 0, y: topStaff.frame.midY - topStaff.frame.height,
                          width: page.size.width,
                          height: topStaff.frame.height * 2)
        let lasso = [CGPoint(x: band.minX, y: band.minY), CGPoint(x: band.maxX, y: band.minY),
                     CGPoint(x: band.maxX, y: band.maxY), CGPoint(x: band.minX, y: band.maxY)]
        let caught = page.elements(inLasso: lasso, kinds: ScoreElementKind.noteLike)
        XCTAssertFalse(caught.isEmpty, "the band caught nothing")
        let hitStaves = Set(caught.compactMap { $0.address?.staff })
        XCTAssertEqual(hitStaves, [1],
                       "a band over one staff pulled in others: \(hitStaves)")
    }

    // MARK: path bounds, the fiddliest part of the parser

    func testPathBoundsHandlesAbsoluteAndRelativeCommands() throws {
        let absolute = try XCTUnwrap(SVGPathBounds.bounds(of: "M0 0 L100 50 Z"))
        XCTAssertEqual(absolute, CGRect(x: 0, y: 0, width: 100, height: 50))

        let relative = try XCTUnwrap(SVGPathBounds.bounds(of: "m10 10 l20 20 z"))
        XCTAssertEqual(relative, CGRect(x: 10, y: 10, width: 20, height: 20))

        let shorthand = try XCTUnwrap(SVGPathBounds.bounds(of: "M0 0 H50 V25"))
        XCTAssertEqual(shorthand, CGRect(x: 0, y: 0, width: 50, height: 25))

        // control points count toward the box: a superset never misses a hit
        let curve = try XCTUnwrap(SVGPathBounds.bounds(of: "M0 0 C10 -20 30 40 40 0"))
        XCTAssertEqual(curve.minY, -20)
        XCTAssertEqual(curve.maxY, 40)

        XCTAssertNil(SVGPathBounds.bounds(of: ""))
    }

    func testTransformParsingComposesInSVGOrder() {
        // translate then scale: the scale applies in the translated frame
        let t = SVGTransform.parse("translate(10, 20) scale(2, 2)")
        let p = CGPoint(x: 1, y: 1).applying(t)
        XCTAssertEqual(p.x, 12, accuracy: 0.001)
        XCTAssertEqual(p.y, 22, accuracy: 0.001)

        XCTAssertEqual(SVGTransform.parse(nil), .identity)
        XCTAssertEqual(SVGTransform.parse("nonsense"), .identity)
    }
}
