import CoreGraphics
import Foundation

/// How the score is laid out on the canvas: one page, a spread, or continuous.
///
/// ONE property with three values, not two booleans. Spread and continuous are
/// two answers to the same question, and as separate flags they can both be
/// true -- a state with no meaning that every reader of them would have to
/// resolve, differently. `twoPageSpread` survives as a derived value so the
/// rest of the app keeps working, but it can no longer be set into a state the
/// layout cannot represent.
enum ScoreLayout: String, CaseIterable, Codable {
    /// One page fitted to the canvas.
    case page
    /// Two pages side by side.
    case spread
    /// Every system in one line, running left to right with no page breaks.
    /// For arranging and composing, where seeing what comes next matters more
    /// than seeing a page.
    case continuous

    /// How many pages of the engraving a single unit shows.
    var pagesPerUnit: Int { self == .spread ? 2 : 1 }

    var isContinuous: Bool { self == .continuous }

    /// A spread is meaningless on a phone -- two portrait pages across 390pt
    /// is two thumbnails -- and that bar has no room for a third cell.
    static func available(isCompact: Bool) -> [ScoreLayout] {
        isCompact ? [.page, .continuous] : allCases
    }

    /// The control is one adjustable element to a screen reader, so it needs
    /// an order to step through rather than three buttons to hunt for.
    func stepped(by delta: Int, isCompact: Bool) -> ScoreLayout {
        let options = Self.available(isCompact: isCompact)
        guard let here = options.firstIndex(of: self) else { return options[0] }
        let next = min(max(here + delta, 0), options.count - 1)
        return options[next]
    }

    var glyph: String {
        switch self {
        case .page:       return "doc"
        case .spread:     return "book.pages"
        case .continuous: return "arrow.left.and.right"
        }
    }

    var label: String {
        switch self {
        case .page:       return "One page"
        case .spread:     return "Two pages"
        case .continuous: return "Continuous"
        }
    }

    /// What the "…" screen shows as the current value.
    var summary: String {
        switch self {
        case .page:       return "one page"
        case .spread:     return "two pages"
        case .continuous: return "continuous"
        }
    }

    /// Ink is keyed to a PAGE, and continuous mode has no pages -- one surface
    /// the length of the score. Rather than key strokes to something that does
    /// not exist, annotation is unavailable here and the mode says so.
    var allowsAnnotation: Bool { self != .continuous }

    /// A page counter is meaningless with no pages; the bar number is not.
    var showsPageCounter: Bool { self != .continuous }
}
