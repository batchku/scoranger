import SwiftUI

// MARK: - Band header (§7.3)

/// The silkscreen label: a full-width `band` strip with hard rules top and
/// bottom and a tracked-out caps label. Used for sidebar sections, sheet
/// sections and card headers, with an optional trailing action.
struct BandHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Theme.Metric.s8) {
            Text(title.uppercased())
                .typeRole(.label)
                .foregroundStyle(Theme.Accent.clayStrong)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, Theme.Metric.panelPadding)
        .padding(.top, 5)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Surface.band)
        .overlay(alignment: .top) { hairline }
        .overlay(alignment: .bottom) { hairline }
    }

    private var hairline: some View {
        Rectangle().fill(Theme.Line.line2).frame(height: 1)
    }
}

extension BandHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

// MARK: - Numeral (§7.5)

/// `#N`, the app's identity element. Space Grotesk 700, clay, tabular, with a
/// reserved width so #1 through #99 stay left-aligned down a column.
struct NumeralBadge: View {
    let number: Int
    var role: Theme.Role = .numeralL

    var body: some View {
        Text("#\(number)")
            .typeRole(role)
            .monospacedDigit()
            .foregroundStyle(Theme.Accent.clay)
            .frame(minWidth: role == .numeralL ? 36 : 28, alignment: .leading)
            .accessibilityLabel("Arrangement number \(number)")
    }
}

// MARK: - LED (§7.14)

/// A drawn circle with a halo, never a symbol, and never the only carrier of
/// its meaning: it sits beside a mono word.
struct LED: View {
    let isOn: Bool
    var showsLabel = true

    var body: some View {
        HStack(spacing: Theme.Metric.s6) {
            Circle()
                .fill(colour)
                .frame(width: 9, height: 9)
                .overlay {
                    Circle().stroke(colour.opacity(0.22), lineWidth: 3)
                }
            if showsLabel {
                Text(isOn ? "on-device" : "unreachable")
                    .typeRole(.data)
                    .foregroundStyle(Theme.Ink.ink2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOn ? "Engine connected" : "Engine unreachable")
    }

    private var colour: Color { isOn ? Theme.Status.ok : Theme.Status.danger }
}

// MARK: - Buttons (§7.11)

/// 13pt/600 label, 2pt radius, hard border. `primary` and `destructive` carry a
/// fill and a white label; the default sits on `panel`.
struct PanelButton: View {
    enum Kind { case normal, primary, destructive }

    let title: String
    var kind: Kind = .normal
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .typeRole(.control)
                .foregroundStyle(labelColour)
                .padding(.vertical, Theme.Metric.s8)
                .padding(.horizontal, Theme.Metric.s12)
                .frame(minHeight: 34)
                .background(fill)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(kind == .normal ? Theme.Line.line2 : .clear, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.42)
    }

    private var fill: Color {
        switch kind {
        case .normal:      return Theme.Surface.panel
        case .primary:     return Theme.Accent.clayPress
        case .destructive: return Theme.Status.danger
        }
    }

    private var labelColour: Color {
        kind == .normal ? Theme.Ink.ink : .white
    }
}

/// 34pt square icon button with the same border language. Always given a 44pt
/// hit area even though it draws smaller (§3).
struct PanelIconButton: View {
    let systemName: String
    let label: String
    var tint: Color = Theme.Ink.ink2
    var bordered = true
    var size: CGFloat = 34
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Theme.Surface.panel.opacity(bordered ? 1 : 0))
                .overlay {
                    if bordered {
                        RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                            .stroke(Theme.Line.line2, lineWidth: 1)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
                .frame(width: Theme.Metric.hitTarget, height: Theme.Metric.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Row (§7.4)

/// Selection is a `clayTint` fill *plus* an inset clay outline: on a warm
/// ground the fill alone is too quiet (§1 rule 2).
struct RowSelectionBackground: View {
    let isSelected: Bool

    var body: some View {
        if isSelected {
            Theme.Accent.clayTint
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(Theme.Accent.clay, lineWidth: 1)
                        .padding(1)
                }
        } else {
            Color.clear
        }
    }
}

// MARK: - Overlay panel (§7.2)

enum OverlayEdge { case leading, trailing }

/// A full-height opaque panel that slides over the score, with a hard edge on
/// the score side. The score is the ground; these are the things above it.
struct OverlayPanel<Content: View>: View {
    let edge: OverlayEdge
    let width: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(width: width)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.Surface.panel)
            .overlay(alignment: edge == .leading ? .trailing : .leading) {
                Rectangle().fill(Theme.Line.line2).frame(width: 1)
            }
            .modifier(PanelShadow())
    }
}

private struct PanelShadow: ViewModifier {
    func body(content: Content) -> some View {
        Theme.Elevation.panel(content)
    }
}

/// Header line inside an overlay: subject on the left, state on the right, and a
/// bordered dismiss button at the far end.
struct OverlayHeader<Subject: View, Trailing: View>: View {
    @ViewBuilder var subject: () -> Subject
    @ViewBuilder var trailing: () -> Trailing
    let onDismiss: () -> Void
    let dismissLabel: String

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Metric.s8) {
            subject()
            Spacer(minLength: Theme.Metric.s8)
            trailing()
            PanelIconButton(systemName: "xmark", label: dismissLabel,
                            size: 30, action: onDismiss)
        }
        .padding(.horizontal, Theme.Metric.panelPadding)
        .padding(.vertical, Theme.Metric.s8)
        .background(Theme.Surface.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Line.line2).frame(height: 1)
        }
    }
}

// MARK: - State view (§7.17)

/// Centred glyph, title, a body no wider than it needs, and at most one button.
/// Failure states name the cause in mono and the fix in prose.
struct StateView: View {
    let systemImage: String
    let title: String
    /// Named `message`, not `body`: a stored property called body collides with
    /// the View requirement.
    var message: String?
    var mono: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Metric.s12) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.Ink.ink3)
            Text(title)
                .typeRole(.title)
                .foregroundStyle(Theme.Ink.ink)
            if let mono {
                Text(mono)
                    .typeRole(.data)
                    .foregroundStyle(Theme.Ink.ink2)
                    .padding(.vertical, Theme.Metric.s4)
                    .padding(.horizontal, Theme.Metric.s8)
                    .background(Theme.Surface.well)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
            }
            if let message {
                Text(message)
                    .typeRole(.body)
                    .foregroundStyle(Theme.Ink.ink2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            if let actionTitle, let action {
                PanelButton(title: actionTitle, action: action)
                    .padding(.top, Theme.Metric.s4)
            }
        }
        .padding(Theme.Metric.s24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
