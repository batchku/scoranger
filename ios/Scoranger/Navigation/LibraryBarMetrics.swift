import SwiftUI
import UIKit

/// The library row's label widths, MEASURED at the text size in force.
///
/// §14.5's caution, in one file: `ScoreBarLayout`'s constants are widths taken
/// at the default text size, and §6.3 rule 3 flags that as a bar which seats
/// what it cannot draw at every size above Large. Nothing here is a literal
/// taken from a screenshot -- the strings are the ones the buttons actually
/// draw, in the font they actually draw them in, scaled the way every other
/// type role in this app is scaled.
///
/// The one number that is not measured text is the icon-only button, which is
/// a square of the row's own height and scales with it.
enum LibraryBarMetrics {

    /// The row's font: `rowButton` draws its label at 13pt semibold, and
    /// `UIFontMetrics` scales that the way `Theme.Role.font` scales every
    /// other role.
    static func font(for size: DynamicTypeSize) -> UIFont {
        let base = UIFont.systemFont(ofSize: 13, weight: .semibold)
        return UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: base,
                        compatibleWith: UITraitCollection(
                            preferredContentSizeCategory: category(for: size)))
    }

    /// SwiftUI's size to UIKit's category. Spelled out rather than bridged,
    /// because the bridge is not public and a wrong guess here would put the
    /// arithmetic back to being unmeasured.
    static func category(for size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall:            return .extraSmall
        case .small:             return .small
        case .medium:            return .medium
        case .large:             return .large
        case .xLarge:            return .extraLarge
        case .xxLarge:           return .extraExtraLarge
        case .xxxLarge:          return .extraExtraExtraLarge
        case .accessibility1:    return .accessibilityMedium
        case .accessibility2:    return .accessibilityLarge
        case .accessibility3:    return .accessibilityExtraLarge
        case .accessibility4:    return .accessibilityExtraExtraLarge
        case .accessibility5:    return .accessibilityExtraExtraExtraLarge
        @unknown default:        return .large
        }
    }

    /// The icon-only button, square, SCALED.
    ///
    /// It was a flat 32 at every text size. That is §6.3 rule 2's own example
    /// of the thing not to do -- a constant sitting under type -- and it is
    /// wrong in both directions here: the glyph inside grows with the text, so
    /// at an accessibility size a 32pt square clips it, and the row's
    /// arithmetic was told the button never changes width when in fact its
    /// content does.
    static func iconButton(size: DynamicTypeSize) -> CGFloat {
        UIFontMetrics(forTextStyle: .footnote)
            .scaledValue(for: LibraryActionRow.buttonHeight,
                         compatibleWith: UITraitCollection(
                            preferredContentSizeCategory: category(for: size)))
            .rounded(.up)
    }

    /// The glyphs this row draws, at the weight it draws them.
    ///
    /// `rowButton` renders them at 13pt medium, and an SF Symbol is NOT 13pt
    /// wide at 13pt: `arrow.up.arrow.down` and `line.3.horizontal.decrease`
    /// are both wider than they are tall. Assuming the point size was the
    /// width under-reserved the row by 1.7pt on a phone -- small, and still
    /// the difference between fitting and hanging off the edge.
    static let glyphs = ["arrow.down.to.line", "plus", "arrow.up.arrow.down",
                         "line.3.horizontal.decrease", "checkmark.circle"]

    /// The WIDEST glyph in the row, measured. One number rather than five,
    /// and deliberately the widest: over-reserving makes the row yield a step
    /// early, which is invisible. Under-reserving is the bug.
    static func glyphWidth(size: DynamicTypeSize) -> CGFloat {
        let points = UIFontMetrics(forTextStyle: .footnote)
            .scaledValue(for: 13, compatibleWith: UITraitCollection(
                            preferredContentSizeCategory: category(for: size)))
        let config = UIImage.SymbolConfiguration(pointSize: points,
                                                 weight: .medium)
        let widest = glyphs.compactMap {
            UIImage(systemName: $0, withConfiguration: config)?.size.width
        }.max()
        // No symbol available (a runtime that does not carry one): fall back
        // to the square, which is wider than any of them and so still safe.
        return (widest ?? points * 1.6).rounded(.up)
    }

    static func textWidth(_ text: String, size: DynamicTypeSize) -> CGFloat {
        (text as NSString)
            .size(withAttributes: [.font: font(for: size)])
            .width
            .rounded(.up)
    }

    /// The row's labels for one sort and one filter count, measured.
    static func labels(sort: LibrarySort, filters: Int, editing: Bool,
                       size: DynamicTypeSize) -> LibraryBarLayout.Labels {
        let filterText = filters == 0 ? "Filter" : "Filter · \(filters)"
        let icon = iconButton(size: size)
        return .init(
            importText: textWidth("Import", size: size),
            newText: textWidth("New", size: size),
            sortFull: textWidth("Sort: \(sort.buttonLabel)", size: size),
            sortShort: textWidth("Sort: \(sort.shortButtonLabel)", size: size),
            sortBare: textWidth("Sort", size: size),
            filterText: textWidth(filterText, size: size),
            editText: textWidth(editing ? "Done" : "Edit", size: size),
            iconButton: icon,
            glyphAndGap: glyphWidth(size: size) + Theme.Metric.s6,
            buttonPadding: LibraryActionRow.buttonPadding * 2)
    }
}
