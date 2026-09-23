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

    // MARK: - Which layout the canvas may draw with

    /// Which ENGRAVING a layout needs. One page and a spread are the same
    /// pages counted out differently -- Verovio is asked for the same
    /// document and the canvas shows one or two of its pages at a time.
    /// Continuous is a different document: one page, no system breaks.
    enum Engraving: String, Equatable {
        case paged
        case continuous
    }

    var engraving: Engraving { isContinuous ? .continuous : .paged }

    /// The layout the canvas may draw the pages it is HOLDING with.
    ///
    /// Changing layout published at once while the pages on screen were still
    /// the old engraving, so for a frame the canvas drew a paged document as a
    /// strip, or a strip squeezed into a page frame -- Ali: "changing between
    /// one page, two pages and scroll shows the WRONG view for a moment".
    ///
    /// The rule is the engraving, not the layout. Page and spread share one,
    /// so switching between them is instant and nothing waits. Continuous
    /// needs its own, so the switch to or from it waits for the pages it
    /// needs: the canvas keeps drawing what it has, in the layout that
    /// engraving was made for, until the new document and this value change
    /// together in one publish.
    ///
    /// `engraved` is nil when no pages are held at all, and then there is
    /// nothing to mismatch.
    ///
    /// **`awaiting` is what stops a frame becoming forever.** Holding the old
    /// engraving is right only while the new one is COMING. With nothing in
    /// flight, the two disagreeing is not a handover in progress, it is a
    /// handover that never finished -- and the reader is left looking at the
    /// continuous strip squeezed into a page frame: one system, every bar of
    /// the tune crushed onto it, the rest of the sheet blank. Ali photographed
    /// exactly that on Whiskey In A Jar, in 1-page mode, and it stayed. It
    /// stayed because ONE PAGE AND A SPREAD SHARE AN ENGRAVING, so his two
    /// obvious recoveries -- toggling 1-page, 2-page -- changed no key and
    /// asked for no new engrave.
    ///
    /// So when nothing is in flight the CHOICE wins. One honest bad frame,
    /// and the caller re-engraves; the alternative is a page that is wrong
    /// until the app is relaunched.
    static func displayed(chosen: ScoreLayout, engraved: ScoreLayout?,
                          awaiting: Bool = true) -> ScoreLayout {
        guard let engraved, engraved.engraving != chosen.engraving else { return chosen }
        return awaiting ? engraved : chosen
    }
}
