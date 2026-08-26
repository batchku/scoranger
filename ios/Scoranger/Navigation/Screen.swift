import SwiftUI

/// A pushed screen's chrome (NAV_MODAL_FREE_0.4.2 §1, §3).
///
/// A nav bar that NAMES where back goes. "‹ My library" rather than a bare
/// chevron: a stack you can trust is one where you never count taps to get out.
struct Screen<Content: View, Trailing: View>: View {
    let title: String
    let backLabel: String
    var subtitle: String?
    var onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Metric.s8) {
                Button(action: onBack) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text(backLabel).typeRole(.control)
                    }
                    .foregroundStyle(Theme.Accent.clayStrong)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("screen-back")
                .accessibilityLabel("Back to \(backLabel)")

                Spacer(minLength: Theme.Metric.s8)
                VStack(spacing: 0) {
                    Text(title).typeRole(.titleS).foregroundStyle(Theme.Ink.ink)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle).typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Theme.Metric.s8)
                trailing()
            }
            .padding(.horizontal, Theme.Metric.s16)
            .frame(height: Theme.Metric.scoreTopBar)
            .background(Theme.Surface.panel)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.Line.line).frame(height: 1)
            }

            ScrollView { content() }
        }
        .background(Theme.Surface.ground)
    }
}

extension Screen where Trailing == EmptyView {
    init(title: String, backLabel: String, subtitle: String? = nil,
         onBack: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, backLabel: backLabel, subtitle: subtitle,
                  onBack: onBack, trailing: { EmptyView() }, content: content)
    }
}

/// A row of a screen: a label, an optional current answer, and a chevron when
/// it leads somewhere.
///
/// The trailing value is what makes these screens read as a summary rather than
/// a menu (§3.2) -- `Move to piece › Cavatina` answers the question before you
/// tap it.
struct ScreenRow: View {
    let title: String
    var value: String?
    var leads: Bool = true
    var isDestructive: Bool = false
    var identifier: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Metric.s8) {
                Text(title).typeRole(.row)
                    .foregroundStyle(isDestructive ? Theme.Status.danger : Theme.Ink.ink)
                Spacer(minLength: Theme.Metric.s8)
                if let value {
                    Text(value).typeRole(.data).foregroundStyle(Theme.Ink.ink3).lineLimit(1)
                }
                if leads {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Ink.ink3)
                }
            }
            .padding(.horizontal, Theme.Metric.s20)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }
}

/// The two-step delete's first step (§5.2).
///
/// The row becomes a strip that states WHAT will go -- which an alert usually
/// does not -- on an error-tinted ground. Nothing floats, nothing dims, and
/// there is nothing to dismiss: `Keep` puts the row back.
struct ConfirmDeleteStrip: View {
    let what: String
    var identifier: String
    var onDelete: () -> Void
    var onKeep: () -> Void

    var body: some View {
        HStack(spacing: Theme.Metric.s8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Status.danger)
            Text(what).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Metric.s8)
            PanelButton(title: "Keep", action: onKeep)
                .accessibilityIdentifier("\(identifier)-keep")
            Button(action: onDelete) {
                Text("Delete").typeRole(.control)
                    .foregroundStyle(Theme.Surface.paper)
                    .padding(.horizontal, Theme.Metric.s12)
                    .padding(.vertical, Theme.Metric.s6)
                    .background(Theme.Status.danger)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
        }
        .padding(.horizontal, Theme.Metric.s20)
        .padding(.vertical, 10)
        .background(Theme.Status.errorFill)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.Status.danger).frame(width: 2)
        }
    }
}

/// Renaming, in the row itself (§5.1). The keyboard is the only thing that
/// overlays, and that is the OS.
struct InlineRenameRow: View {
    @Binding var text: String
    var onSave: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: Theme.Metric.s8) {
            TextField("Name", text: $text)
                .typeRole(.body)
                .foregroundStyle(Theme.Ink.ink)
                .tint(Theme.Accent.clay)
                .textFieldStyle(.plain)
                .padding(.horizontal, Theme.Metric.s8)
                .padding(.vertical, 7)
                .background(Theme.Surface.paper)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(Theme.Accent.clay, lineWidth: 1)
                }
                .accessibilityIdentifier("inline-rename-field")
            PanelButton(title: "Cancel", action: onCancel)
                .accessibilityIdentifier("inline-rename-cancel")
            PanelButton(title: "Save", kind: .primary, action: onSave)
                .accessibilityIdentifier("inline-rename-save")
        }
        .padding(.horizontal, Theme.Metric.s20)
        .padding(.vertical, 8)
        .background(Theme.Surface.well)
    }
}
