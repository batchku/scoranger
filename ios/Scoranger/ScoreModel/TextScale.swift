import SwiftUI
import UIKit

/// How big the reader's text is, as a number a layout can multiply by.
///
/// One definition, because two would drift and the drift is invisible: a
/// layout that scales its strips by one factor while its labels are drawn at
/// another is a layout that clips at some sizes and not others.
///
/// Every value here is MEASURED through `UIFontMetrics` rather than taken from
/// a table. §6.3 rule 3 and MIXER_WINDOW §12 both say the same thing about
/// this in different words: a constant taken at the default text size is a
/// layout that mis-fits at every other one.
enum TextScale {

    /// SwiftUI's size to UIKit's category. Spelled out rather than bridged,
    /// because the bridge is not public and a wrong guess here would put every
    /// measurement below back to being a literal.
    static func category(for size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall:         return .extraSmall
        case .small:          return .small
        case .medium:         return .medium
        case .large:          return .large
        case .xLarge:         return .extraLarge
        case .xxLarge:        return .extraExtraLarge
        case .xxxLarge:       return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default:     return .large
        }
    }

    static func traits(for size: DynamicTypeSize) -> UITraitCollection {
        UITraitCollection(preferredContentSizeCategory: category(for: size))
    }

    /// A point value scaled to this text size.
    static func scaled(_ points: CGFloat, size: DynamicTypeSize) -> CGFloat {
        UIFontMetrics(forTextStyle: .footnote)
            .scaledValue(for: points, compatibleWith: traits(for: size))
    }

    /// The factor itself: 1.0 at Large, more above it, less below.
    ///
    /// Measured over 100 points rather than 1, so the rounding inside
    /// `scaledValue` does not dominate the answer.
    static func factor(_ size: DynamicTypeSize) -> CGFloat {
        scaled(100, size: size) / 100
    }
}
