import CoreGraphics
import Foundation

/// What the Edit-mode action bar shows at a given width, and the order in
/// which it yields when there is not enough of it (REDESIGN_BRIEF_0.8 §7.3).
///
/// At 393pt the bar has 353. With "5 selected · New arrangement · New set
/// list · Delete 5 pieces" it wants 469. So it yields, by measurement, in a
/// stated order, and stops at the first rung that fits:
///
///   0  everything
///   1  the "N selected" readout goes -- it is a readout, and every selected
///      row already carries a checked box
///   2  short verb labels: Arrangement, Set list; VoiceOver keeps the sentence
///   3  Delete loses its count, last, because the count is the safety on the
///      destructive verb
///   4  two rows, constructive above destructive -- IPHONE_0.6.14 §6.3 rule
///      4 arriving one control early
///
/// A pure function of the width and MEASURED label widths, as
/// `LibraryBarLayout` is for the row above the list, so it can be checked for
/// every width and text size without a screen.
enum LibraryActionBarLayout {

    enum Rung: Int, CaseIterable, Equatable, Comparable {
        case full, noReadout, shortVerbs, deleteUncounted, twoRows
        static func < (a: Rung, b: Rung) -> Bool { a.rawValue < b.rawValue }

        var showsReadout: Bool { self == .full }
        var usesShortLabels: Bool { self >= .shortVerbs }
        var deleteIsCounted: Bool { self < .deleteUncounted }
    }

    /// The drawn width of every label the bar can show, at the text size in
    /// force. `LibraryActionBarMetrics` measures them; tests may supply their
    /// own.
    struct Labels: Equatable {
        var readout: CGFloat
        var full: [LibraryAction: CGFloat]
        var short: [LibraryAction: CGFloat]
        var deleteCounted: CGFloat
        var deleteBare: CGFloat
        /// A capsule's own horizontal padding, both sides together.
        var buttonPadding: CGFloat
        /// Between capsules, and between the readout and the first capsule.
        var gap: CGFloat
        /// The bar's own horizontal padding, both sides together.
        var sidePadding: CGFloat
    }

    /// The width of one capsule at a rung.
    static func button(_ action: LibraryAction, at rung: Rung, labels: Labels) -> CGFloat {
        let text: CGFloat
        if action == .delete {
            text = rung.deleteIsCounted ? labels.deleteCounted : labels.deleteBare
        } else {
            text = (rung.usesShortLabels ? labels.short[action] : labels.full[action])
                ?? labels.full[action] ?? 0
        }
        return text + labels.buttonPadding
    }

    /// What a rung needs, in points, for these actions on one line.
    static func width(of rung: Rung, actions: [LibraryAction], labels: Labels) -> CGFloat {
        var total = labels.sidePadding
        if rung.showsReadout { total += labels.readout + labels.gap }
        total += actions.map { button($0, at: rung, labels: labels) }.reduce(0, +)
        total += labels.gap * CGFloat(max(actions.count - 1, 0))
        return total
    }

    /// The first rung that fits; `.twoRows` when none does on one line.
    static func rung(width: CGFloat, actions: [LibraryAction], labels: Labels) -> Rung {
        // Unmeasured: show everything rather than flashing a stripped bar on
        // the first frame.
        guard width > 0 else { return .full }
        for rung in [Rung.full, .noReadout, .shortVerbs, .deleteUncounted]
        where Self.width(of: rung, actions: actions, labels: labels) <= width {
            return rung
        }
        return .twoRows
    }
}
