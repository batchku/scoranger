import SwiftUI

/// The canvas toolbar, and the app's only persistent chrome: no navigation bar,
/// no title bar, no tab bar (§7.1).
///
/// Left to right: library toggle · `#N` numeral · version chip · divider ·
/// options · pencil · divider · chat toggle. Floats bottom-centre over the
/// score. On iPhone the pencil is dropped, since markup is iPad-only, and the
/// numeral steps down a size.
struct CanvasPill<VersionMenu: View, OptionsMenu: View>: View {
    let number: Int?
    let versionID: String?
    @Binding var libraryOpen: Bool
    @Binding var chatOpen: Bool
    let markupActive: Bool
    let markupInk: Color?
    let showsMarkup: Bool
    let onMarkup: () -> Void
    /// The version chip and the gear open menus in place, which is how the old
    /// toolbar's version picker and score options survive losing the toolbar.
    @ViewBuilder var versionMenu: () -> VersionMenu
    @ViewBuilder var optionsMenu: () -> OptionsMenu

    var body: some View {
        HStack(spacing: Theme.Metric.s6) {
            PillToggle(systemName: "line.3.horizontal", label: "Library",
                       identifier: "pill-library", isActive: libraryOpen) {
                withAnimation(Theme.Motion.pillState) { libraryOpen.toggle() }
            }

            if let number {
                NumeralBadge(number: number, role: .numeralM)
                    .padding(.leading, Theme.Metric.s2)
            }

            if let versionID {
                Menu {
                    versionMenu()
                } label: {
                    Text(versionID)
                        .typeRole(.data)
                        .foregroundStyle(Theme.Ink.ink2)
                        .padding(.vertical, Theme.Metric.s4)
                        .padding(.horizontal, Theme.Metric.s6)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                                .stroke(Theme.Line.line2, lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                        .frame(minHeight: Theme.Metric.hitTarget)
                }
                .accessibilityLabel("Version \(versionID), pick another")
                .accessibilityIdentifier("pill-version")
            }

            divider

            Menu {
                optionsMenu()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.Ink.ink2)
                    .frame(width: Theme.Metric.pillButton, height: Theme.Metric.pillButton)
                    .frame(width: Theme.Metric.hitTarget, height: Theme.Metric.hitTarget)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Score options")
            .accessibilityIdentifier("pill-options")

            if showsMarkup {
                PillToggle(systemName: markupActive ? "pencil.tip" : "pencil.slash",
                           label: markupActive ? "Exit markup" : "Markup",
                           identifier: "pill-markup",
                           isActive: markupActive,
                           activeTint: markupInk,
                           action: onMarkup)
            }

            divider

            PillToggle(systemName: "bubble.left.and.text.bubble.right", label: "Chat",
                       identifier: "pill-chat", isActive: chatOpen) {
                withAnimation(Theme.Motion.pillState) { chatOpen.toggle() }
            }
        }
        .padding(.horizontal, Theme.Metric.s6)
        .padding(.vertical, Theme.Metric.s6)
        .background(Theme.Surface.panel)
        .clipShape(Capsule())
        .overlay { Capsule().stroke(Theme.Line.line2, lineWidth: 1) }
        .modifier(PillShadow())
        .padding(.bottom, Theme.Metric.s20)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.Line.line2)
            .frame(width: 1, height: 22)
            .padding(.horizontal, Theme.Metric.s2)
    }
}

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
