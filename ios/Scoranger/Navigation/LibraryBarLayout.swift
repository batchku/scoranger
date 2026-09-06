import CoreGraphics
import Foundation

/// What the library's action row shows at a given width, and in what order its
/// labels yield when there is not enough of it.
///
/// IPHONE_0.6.14 §14. Ali on 0.6.14 b173: the row is clipped at both edges on a
/// phone -- the import icon half off the left, and Sort, Filter and the select
/// tick running off the right. Measured on an iPhone 17 Pro: the row wanted
/// 418pt and had 362, and `.frame(width:)` held the HStack at 362 while its
/// content measured 418, so SwiftUI centred the overflow and spilled it over
/// both edges.
///
/// The cause was not arithmetic -- unlike the score bar, which measured itself
/// wrong -- it was that this row had no yield order at all. Its one concession
/// to width turned five labels into five unlabelled squares, and below that
/// there was nothing left to give.
///
/// So: `Import` and `New` collapse the five quick actions into two verbs with
/// reveal bands (§14.3, in the view), and what remains yields BY MEASUREMENT,
/// in a stated order, exactly as `ScoreBarLayout` does for the score's bar.
///
/// **The labels are measured, never assumed.** `ScoreBarLayout`'s constants are
/// widths taken at the default text size, which §6.3 rule 3 already flags as
/// mis-fitting at every size above Large -- a bar that seats what it cannot
/// draw. §14.5 says in terms not to copy that here, so this takes a `Labels`
/// of real measurements and does arithmetic on those.
enum LibraryBarLayout {

    /// How the Sort button says its answer.
    enum SortStyle: Equatable {
        /// "Sort: recently changed"
        case full
        /// "Sort: recent" -- still the answer, said shortly.
        case short
        /// "Sort" -- the value given up, which is last because that label
        /// being an answer is the reason it is written that way.
        case bare
    }

    /// What the row draws.
    struct Fit: Equatable {
        var importLabelled = true
        var newLabelled = true
        var filterLabelled = true
        var editLabelled = true
        var sort: SortStyle = .full
        /// Nothing left to yield and it still does not fit: the row wraps to
        /// two. The FLOOR, not the fix (§14.4).
        var wraps = false
        /// At AX1 and above a row of more than three controls becomes a
        /// vertical list -- §6.3 rule 4, which this row is subject to like
        /// every other.
        var list = false
    }

    /// The drawn width of every label the row can show, measured at the text
    /// size in force. `LibraryBarMetrics` measures them; the tests supply
    /// their own so the arithmetic can be checked without a screen.
    struct Labels: Equatable {
        var importText: CGFloat
        var newText: CGFloat
        var sortFull: CGFloat
        var sortShort: CGFloat
        var sortBare: CGFloat
        var filterText: CGFloat
        var editText: CGFloat
        /// One icon-only button, square, at the row's own height.
        var iconButton: CGFloat
        /// The glyph inside a labelled button, plus the gap to its text.
        var glyphAndGap: CGFloat
        /// The button's own horizontal padding, both sides.
        var buttonPadding: CGFloat
    }

    /// A labelled button's width: glyph, gap, text, padding.
    static func labelled(_ text: CGFloat, _ labels: Labels) -> CGFloat {
        labels.glyphAndGap + text + labels.buttonPadding
    }

    /// What a fit needs, in points.
    static func width(of fit: Fit, labels: Labels) -> CGFloat {
        var total: CGFloat = 0
        total += fit.importLabelled ? labelled(labels.importText, labels) : labels.iconButton
        total += LibraryActionRow.gap
        total += fit.newLabelled ? labelled(labels.newText, labels) : labels.iconButton
        total += LibraryActionRow.clusterGap
        switch fit.sort {
        case .full:  total += labelled(labels.sortFull, labels)
        case .short: total += labelled(labels.sortShort, labels)
        case .bare:  total += labelled(labels.sortBare, labels)
        }
        total += LibraryActionRow.gap
        total += fit.filterLabelled ? labelled(labels.filterText, labels) : labels.iconButton
        total += LibraryActionRow.gap
        total += fit.editLabelled ? labelled(labels.editText, labels) : labels.iconButton
        return total
    }

    static func fits(_ fit: Fit, in available: CGFloat, labels: Labels) -> Bool {
        width(of: fit, labels: labels) <= available
    }

    /// The yield order, run until it fits (§14.4).
    ///
    /// Each step is one label, and the order is by how much the label is
    /// carrying: Edit and Filter name themselves and their glyphs say the same
    /// thing, so they go first. Import and New follow -- their bands name
    /// their variants in words the moment they open, so an icon costs less
    /// there than it would in a row of five unlabelled squares. Sort is last
    /// twice over: first its long answer becomes a short one, and only then
    /// does it give the answer up.
    ///
    /// NOTHING IS EVER REMOVED. All seven actions stay one tap from their
    /// action at every width; only labels yield.
    static func fit(width: CGFloat, labels: Labels,
                    accessibilitySize: Bool = false) -> Fit {
        // §6.3 rule 4: at an accessibility size a row of more than three
        // controls is a list, whatever it would have measured.
        if accessibilitySize { return Fit(sort: .full, list: true) }
        var fit = Fit()
        // Unmeasured: show everything rather than flashing a stripped row on
        // the first frame and filling it in afterwards.
        guard width > 0 else { return fit }
        if fits(fit, in: width, labels: labels) { return fit }
        let steps: [(inout Fit) -> Void] = [
            { $0.editLabelled = false },
            { $0.filterLabelled = false },
            { $0.newLabelled = false },
            { $0.importLabelled = false },
            { $0.sort = .short },
            { $0.sort = .bare },
        ]
        for step in steps {
            step(&fit)
            if fits(fit, in: width, labels: labels) { return fit }
        }
        // Everything has yielded and it still does not fit. Two rows is what
        // is left, and it is the floor rather than the answer.
        fit.wraps = true
        return fit
    }
}
