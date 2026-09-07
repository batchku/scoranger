import CoreGraphics
import Foundation

/// One element of an engraved page: what it is, where it is, and how to refer
/// to it both now (`sessionID`) and later (`address`).
struct ScoreElement: Identifiable, Hashable {
    /// Verovio's SVG id. Valid only for the currently loaded document — see
    /// ScoreAddress for why it must not be persisted.
    let sessionID: String
    let kind: ScoreElementKind
    /// nil when the MEI carried no semantics for this id, which happens for
    /// purely visual groups. Such elements are still hit-testable, just not
    /// addressable.
    let address: ScoreAddress?
    let pageIndex: Int
    /// In page (SVG user) coordinates, y down, matching the page's viewBox.
    let frame: CGRect

    var id: String { sessionID }
}

/// One page of elements with a uniform-grid spatial index over them.
///
/// A page holds on the order of 800 drawable primitives and a few hundred
/// addressable groups, so the grid is not strictly necessary for correctness —
/// it keeps lasso queries from being O(elements) per point as scores grow.
struct ScorePage {
    let index: Int
    /// Page size in user units, from the SVG viewBox.
    let size: CGSize
    let elements: [ScoreElement]

    private let cellSize: CGSize
    private let columns: Int
    private let rows: Int
    /// Grid cell -> indices into `elements`.
    private let buckets: [[Int]]

    init(index: Int, size: CGSize, elements: [ScoreElement]) {
        self.index = index
        self.size = size
        self.elements = elements

        // ~32 columns is a reasonable bucket density for a page of music: a
        // cell then holds a note or two rather than a whole system.
        let columns = max(1, 32)
        let cell = CGSize(width: max(size.width / CGFloat(columns), 1),
                          height: max(size.width / CGFloat(columns), 1))
        let rows = max(1, Int((size.height / cell.height).rounded(.up)))
        self.cellSize = cell
        self.columns = columns
        self.rows = rows

        var buckets = [[Int]](repeating: [], count: columns * rows)
        for (i, element) in elements.enumerated() {
            for cellIndex in Self.cells(for: element.frame, cell: cell,
                                        columns: columns, rows: rows) {
                buckets[cellIndex].append(i)
            }
        }
        self.buckets = buckets
    }

    private static func cells(for rect: CGRect, cell: CGSize,
                              columns: Int, rows: Int) -> [Int] {
        guard rect.width.isFinite, rect.height.isFinite else { return [] }
        let minCol = max(0, min(columns - 1, Int(rect.minX / cell.width)))
        let maxCol = max(0, min(columns - 1, Int(rect.maxX / cell.width)))
        let minRow = max(0, min(rows - 1, Int(rect.minY / cell.height)))
        let maxRow = max(0, min(rows - 1, Int(rect.maxY / cell.height)))
        guard minCol <= maxCol, minRow <= maxRow else { return [] }
        var out: [Int] = []
        for row in minRow...maxRow {
            for col in minCol...maxCol { out.append(row * columns + col) }
        }
        return out
    }

    /// Candidate indices whose cells overlap `rect`. A superset: callers must
    /// still test precisely.
    private func candidates(in rect: CGRect) -> [Int] {
        var seen = Set<Int>()
        for cellIndex in Self.cells(for: rect, cell: cellSize,
                                    columns: columns, rows: rows) {
            for i in buckets[cellIndex] { seen.insert(i) }
        }
        return Array(seen)
    }

    // MARK: hit-testing

    /// Topmost element containing `point`, preferring the smallest frame so a
    /// notehead wins over the measure that encloses it.
    func element(at point: CGPoint, kinds: Set<ScoreElementKind>? = nil) -> ScoreElement? {
        let probe = CGRect(x: point.x, y: point.y, width: 0.01, height: 0.01)
        return candidates(in: probe)
            .map { elements[$0] }
            .filter { $0.frame.contains(point) && Self.matches($0, kinds) }
            .min { $0.frame.area < $1.frame.area }
    }

    /// Elements whose frame intersects `rect`.
    func elements(in rect: CGRect, kinds: Set<ScoreElementKind>? = nil) -> [ScoreElement] {
        candidates(in: rect)
            .map { elements[$0] }
            .filter { $0.frame.intersects(rect) && Self.matches($0, kinds) }
            .sorted { $0.sessionID < $1.sessionID }
    }

    /// Elements caught by a freehand lasso.
    ///
    /// An element counts as selected when its centre falls inside the polygon,
    /// which is what feels right when dragging a loop around noteheads: a
    /// stem clipped by the edge of the loop should not drag its note in.
    func elements(inLasso polygon: [CGPoint],
                  kinds: Set<ScoreElementKind>? = nil) -> [ScoreElement] {
        guard polygon.count >= 3 else { return [] }
        let bounds = Self.boundingBox(of: polygon)
        return candidates(in: bounds)
            .map { elements[$0] }
            .filter {
                Self.matches($0, kinds)
                    && bounds.intersects($0.frame)
                    && Self.contains(polygon: polygon, point: CGPoint(x: $0.frame.midX,
                                                                     y: $0.frame.midY))
            }
            .sorted { $0.sessionID < $1.sessionID }
    }

    /// What a drawn path caught, whatever shape the user drew.
    ///
    /// A loop selects what it encloses. A stroke — a path with almost no area,
    /// which is what a quick swipe through a bar produces — selects what its
    /// band covers instead, thickened so a line drawn along a staff still has
    /// height to it. Without this a swipe closes into a zero-area polygon and
    /// selects nothing, which reads as the feature being broken.
    func elements(caughtBy path: [CGPoint],
                  kinds: Set<ScoreElementKind>? = nil) -> [ScoreElement] {
        guard path.count >= 2 else { return [] }
        let bounds = Self.boundingBox(of: path)
        let area = abs(Self.signedArea(of: path))
        let boxArea = bounds.width * bounds.height
        if path.count >= 3, boxArea > 0, area / boxArea > 0.15 {
            return elements(inLasso: path, kinds: kinds)
        }
        // a stroke: give it a band to catch things with, ~1.5% of the page
        let minimum = max(size.height * 0.015, 1)
        let band = bounds.insetBy(dx: bounds.width < minimum ? -(minimum - bounds.width) / 2 : 0,
                                  dy: bounds.height < minimum ? -(minimum - bounds.height) / 2 : 0)
        return elements(in: band, kinds: kinds)
    }

    /// Shoelace: positive or negative by winding, zero for a path that doubles
    /// back on itself.
    static func signedArea(of points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var total: CGFloat = 0
        for i in points.indices {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            total += a.x * b.y - b.x * a.y
        }
        return total / 2
    }

    private static func matches(_ element: ScoreElement,
                                _ kinds: Set<ScoreElementKind>?) -> Bool {
        guard let kinds else { return true }
        return kinds.contains(element.kind)
    }

    static func boundingBox(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var rect = CGRect(origin: first, size: .zero)
        for p in points.dropFirst() {
            rect = rect.union(CGRect(origin: p, size: .zero))
        }
        return rect
    }

    /// Even-odd ray casting. Closes the polygon implicitly.
    static func contains(polygon: [CGPoint], point: CGPoint) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y) {
                let t = (point.y - a.y) / (b.y - a.y)
                if point.x < a.x + t * (b.x - a.x) { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}

/// Every page of one loaded score, with lookup by session id and by address.
struct ScoreGeometry {
    let pages: [ScorePage]
    private let bySessionID: [String: ScoreElement]
    private let byAddress: [ScoreAddress: ScoreElement]

    init(pages: [ScorePage]) {
        self.pages = pages
        var bySession: [String: ScoreElement] = [:]
        var byAddress: [ScoreAddress: ScoreElement] = [:]
        for page in pages {
            for element in page.elements {
                bySession[element.sessionID] = element
                if let address = element.address { byAddress[address] = element }
            }
        }
        self.bySessionID = bySession
        self.byAddress = byAddress
    }

    var elementCount: Int { pages.reduce(0) { $0 + $1.elements.count } }
    var addressableCount: Int {
        pages.reduce(0) { $0 + $1.elements.filter { $0.address != nil }.count }
    }

    func element(sessionID: String) -> ScoreElement? { bySessionID[sessionID] }

    /// Re-resolve a persisted selection after a re-render, where every session
    /// id has changed but addresses have not.
    func element(at address: ScoreAddress) -> ScoreElement? { byAddress[address] }

    /// Every addressable element in the document, in no particular order.
    /// Used to expand "this bar" into the elements it holds.
    var addresses: [ScoreAddress] { Array(byAddress.keys) }

    /// Which staff a point falls on, given the elements of one bar.
    ///
    /// Needed because a `<measure>` lives OUTSIDE any `<staff>` in MEI, so the
    /// bar element's own address carries staff 0 -- the parser's
    /// "not staff-specific" marker. Asking it which staff it is on returns a
    /// staff no real element has, which is why a double-tap selected nothing
    /// and only a triple-tap (all staves) ever appeared to work.
    ///
    /// The staff is therefore taken from where the Pencil actually is: the
    /// staff whose elements span the tapped y, or failing that the nearest one,
    /// so a tap in the gap between two staves still resolves to the closer.
    /// Pure, so it can be tested without a page.
    static func staff(at y: CGFloat, among bands: [(staff: Int, span: ClosedRange<CGFloat>)]) -> Int? {
        guard !bands.isEmpty else { return nil }
        if let hit = bands.first(where: { $0.span.contains(y) }) { return hit.staff }
        return bands.min(by: { distance(from: y, to: $0.span) < distance(from: y, to: $1.span) })?.staff
    }

    private static func distance(from y: CGFloat, to span: ClosedRange<CGFloat>) -> CGFloat {
        if span.contains(y) { return 0 }
        return y < span.lowerBound ? span.lowerBound - y : y - span.upperBound
    }

    /// The vertical extent of each staff's elements within one measure, on one
    /// page. Bar-like elements are excluded: their frame spans every staff and
    /// would swallow the distinction this exists to make.
    func staffBands(inMeasure measure: Int,
                    onPage index: Int) -> [(staff: Int, span: ClosedRange<CGFloat>)] {
        guard let page = page(index) else { return [] }
        var extents: [Int: (min: CGFloat, max: CGFloat)] = [:]
        for element in page.elements {
            guard let address = element.address, address.measure == measure,
                  address.staff > 0,
                  !ScoreElementKind.barLike.contains(address.kind) else { continue }
            let current = extents[address.staff]
            extents[address.staff] = (min(current?.min ?? element.frame.minY, element.frame.minY),
                                      max(current?.max ?? element.frame.maxY, element.frame.maxY))
        }
        return extents.map { (staff: $0.key, span: $0.value.min...$0.value.max) }
            .sorted { $0.span.lowerBound < $1.span.lowerBound }
    }

    /// How many selectable addresses each bar-on-a-staff holds.
    ///
    /// What "the whole bar is selected" is measured against (§13,
    /// `SelectionMerge`). Bar-like kinds are excluded for the same reason they
    /// are excluded everywhere else: a `<measure>` is not a member of itself,
    /// and it is not selectable, so counting it would make every bar one short
    /// of complete and nothing would ever merge.
    ///
    /// Computed once per selection rather than per element: it is a walk of
    /// every address in the document, and the highlight is rebuilt on every
    /// zoom step.
    var barPopulations: [SelectionMerge.Key: Int] {
        var counts: [SelectionMerge.Key: Int] = [:]
        for address in byAddress.keys {
            guard address.staff > 0,
                  !ScoreElementKind.barLike.contains(address.kind) else { continue }
            counts[SelectionMerge.Key(measure: address.measure,
                                      staff: address.staff), default: 0] += 1
        }
        return counts
    }

    func page(_ index: Int) -> ScorePage? {
        pages.first { $0.index == index }
    }

    /// Distinct bars touched by a selection, which is what chat wants to hear
    /// about ("the notes you selected are in bars 12-15 of staff 1").
    func bars(of elements: [ScoreElement]) -> [Int] {
        Set(elements.compactMap { $0.address?.measure }).sorted()
    }

    func staves(of elements: [ScoreElement]) -> [Int] {
        Set(elements.compactMap { $0.address?.staff }).sorted()
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}

extension ScoreGeometry {

    /// How many systems each page holds, in page order.
    ///
    /// The observable #4 needs, and the reason it is on the geometry rather
    /// than in a test: a page COUNT cannot tell a collapsed layout from a
    /// short piece that genuinely fits. Ali's screenshot reads "p. 1 / 1" on
    /// a folk tune, where one page may be right and one SYSTEM is not.
    ///
    /// Built from `BarPosition`, so it groups by the rule the playhead
    /// already trusts rather than a second one.
    var systemsPerPage: [Int] {
        pages.map { BarPosition.systems(of: BarPosition.bars(onPage: $0)).count }
    }

    /// The same, as one line a test can read off the screen.
    ///
    /// Test-only scaffolding, surfaced under `-geometryProbe` and by nothing
    /// else -- the same shape as the seed flags. It exists because the app is
    /// the only place the iOS engrave path runs, and the engine's own Verovio
    /// already answers this question in Python: the two counts have to be
    /// compared to know whether a collapse is the renderer or the app.
    var probeDescription: String {
        "pages=\(pages.count) systems=\(systemsPerPage.map(String.init).joined(separator: ","))"
    }
}
