import SwiftUI
import UIKit

/// The action bar's label widths, MEASURED in the font that draws them at the
/// text size in force (REDESIGN_BRIEF_0.8 §7.3: "the same measured discipline
/// as §14"). Nothing here is a number read off a screenshot.
enum LibraryActionBarMetrics {

    static func textWidth(_ text: String, font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }

    static func labels(count: Int, kind: LibrarySelectionKind,
                       size: DynamicTypeSize) -> LibraryActionBarLayout.Labels {
        let control = Theme.controlUIFont(for: size)
        let data = Theme.dataUIFont(for: size)
        var full: [LibraryAction: CGFloat] = [:]
        var short: [LibraryAction: CGFloat] = [:]
        for action in LibraryAction.allCases {
            full[action] = textWidth(action.title(count: count, kind: kind), font: control)
            short[action] = textWidth(action.shortTitle(count: count, kind: kind), font: control)
        }
        return LibraryActionBarLayout.Labels(
            readout: textWidth("\(count) selected", font: data),
            full: full, short: short,
            deleteCounted: textWidth(LibraryAction.delete.deleteTitle(count: count, kind: kind, counted: true), font: control),
            deleteBare: textWidth(LibraryAction.delete.deleteTitle(count: count, kind: kind, counted: false), font: control),
            buttonPadding: Theme.Metric.s12 * 2,
            gap: Theme.Metric.s8,
            sidePadding: Theme.Metric.s16 * 2)
    }
}
