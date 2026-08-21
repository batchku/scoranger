import CoreGraphics
import Foundation

/// Joins page geometry to musical semantics and produces the hit-test model.
///
/// Pure over strings on purpose: it takes SVG pages and MEI text, so it is
/// testable headlessly against fixtures with no Verovio, no engine and no view.
/// Wiring it to the live toolkit belongs to Phase B, which is also when the
/// display list starts feeding the drawing path.
enum ScoreModelBuilder {

    /// Classes Verovio puts on groups that we index. Structural wrappers
    /// (`layer`, `staff`, `system`) are skipped: they bound half a page and
    /// would swallow every lasso.
    static let indexedClasses: Set<String> = [
        "note", "chord", "rest", "mRest", "measure", "harm", "clef", "accid",
        "slur", "tie", "dynam", "fermata", "artic"
    ]

    /// - Parameters:
    ///   - svgPages: page SVG in page order, as Verovio renders them.
    ///   - mei: the same document's MEI, from `getMEI()`.
    static func build(svgPages: [String], mei: String) throws -> ScoreGeometry {
        let addresses = try MEISemanticsParser.parse(mei)
        var pages: [ScorePage] = []
        for (index, svg) in svgPages.enumerated() {
            let parsed = try SVGGeometryParser.parse(svg)
            var elements: [ScoreElement] = []
            for group in parsed.groups {
                // a class attribute can carry modifiers, e.g. "ledgerLines below"
                let primary = group.svgClass.split(separator: " ").first.map(String.init) ?? ""
                guard indexedClasses.contains(primary),
                      let kind = ScoreElementKind(meiTag: primary) else { continue }
                elements.append(ScoreElement(sessionID: group.id,
                                             kind: kind,
                                             address: addresses[group.id],
                                             pageIndex: index,
                                             frame: group.frame))
            }
            pages.append(ScorePage(index: index, size: parsed.size, elements: elements))
        }
        return ScoreGeometry(pages: pages)
    }
}

/// A selection of score elements, and the description of it that chat receives.
///
/// Held by durable address rather than by session id, so it survives the
/// re-render that every engine op triggers.
struct ScoreSelection: Equatable {
    var addresses: [ScoreAddress]

    init(_ elements: [ScoreElement]) {
        addresses = elements.compactMap(\.address)
    }

    init(addresses: [ScoreAddress]) { self.addresses = addresses }

    var isEmpty: Bool { addresses.isEmpty }

    var bars: [Int] { Set(addresses.map(\.measure)).sorted() }
    var staves: [Int] { Set(addresses.map(\.staff)).sorted() }

    /// What the chat agent is told, in the terms it already understands:
    /// parts and bar numbers, not pixels. Replaces the linear "≈ bars" estimate
    /// the old drag-select produced.
    var chatDescription: String? {
        guard !isEmpty else { return nil }
        let bars = self.bars
        let staves = self.staves
        let range = bars.count == 1
            ? "bar \(bars[0])"
            : "bars \(bars[0])–\(bars[bars.count - 1])"
        let staffPart = staves.count == 1 ? "staff \(staves[0])" : "staves \(staves.map(String.init).joined(separator: ", "))"
        let kinds = Set(addresses.map(\.kind.rawValue)).sorted().joined(separator: ", ")
        return "A selection is ACTIVE: \(addresses.count) element(s) (\(kinds)) "
            + "in \(range) of \(staffPart). Apply operations only there unless "
            + "told otherwise."
    }
}
