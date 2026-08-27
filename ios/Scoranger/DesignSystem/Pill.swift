import SwiftUI

// The canvas pill is gone. Its duties moved to the score top bar
// (NAVIGATION_SYSTEM.md §8), and its two floating Menus were the last of the
// score view's popovers (NAV_MODAL_FREE_0.4.2 §2). What remains here are the
// small pieces other chrome still uses.

private struct PillShadow: ViewModifier {
    func body(content: Content) -> some View { Theme.Elevation.pill(content) }
}

/// A 38pt round button in the pill. Active buttons take a `clayTint` circle and
/// a `clayStrong` glyph, so state is never carried by colour alone — the glyph
/// changes too where it can.
struct PillToggle: View {
    let systemName: String
    let label: String
    var identifier: String?
    let isActive: Bool
    var activeTint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isActive ? (activeTint ?? Theme.Accent.clayStrong)
                                          : Theme.Ink.ink2)
                .frame(width: Theme.Metric.pillButton, height: Theme.Metric.pillButton)
                .background {
                    if isActive {
                        Circle().fill(Theme.Accent.clayTint)
                    }
                }
                .frame(width: Theme.Metric.hitTarget, height: Theme.Metric.hitTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier ?? label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
