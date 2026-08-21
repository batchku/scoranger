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
