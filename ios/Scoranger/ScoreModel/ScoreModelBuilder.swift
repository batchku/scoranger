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

    /// Staff 0 is the parser's "not staff-specific" marker — a `<measure>`
    /// lives outside any `<staff>` — so it is a fact about the model, not a
    /// staff anyone can be told about. A lasso over one staff caught measures
    /// too, and reported "staves 0, 4".
    var staves: [Int] { Set(addresses.map(\.staff)).filter { $0 > 0 }.sorted() }

    /// What is dropped into the chat input when a lasso finishes: short, in the
    /// user's terms, and visibly about what they just drew.
    var chatReference: String {
        guard !isEmpty else { return "" }
        let bars = self.bars
        let range = bars.count == 1 ? "bar \(bars[0])"
                                    : "bars \(bars[0])–\(bars[bars.count - 1])"
        let staves = self.staves
        let where_ = staves.isEmpty ? ""
            : (staves.count == 1 ? ", staff \(staves[0])"
                                 : ", staves \(staves.map(String.init).joined(separator: ", ")))")
        return "[selection: \(addresses.count) element(s) in \(range)\(where_)] "
    }

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
        let kinds = Set(addresses.map(\.kind.rawValue)).sorted().joined(separator: ", ")
        let staffPart = staves.isEmpty ? ""
            : (staves.count == 1 ? " of staff \(staves[0])"
                                 : " of staves \(staves.map(String.init).joined(separator: ", ")))")
        return "A selection is ACTIVE: \(addresses.count) element(s) (\(kinds)) "
            + "in \(range)\(staffPart). Apply operations only there unless "
            + "told otherwise."
    }
}
