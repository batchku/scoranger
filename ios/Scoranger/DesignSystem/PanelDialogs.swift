import SwiftUI

// MARK: - Alert (§7.16)

/// 420 wide, panel, radius 3, over a 34% dim, with a `band` footer whose
/// buttons are right-aligned: cancel first, then the verb. The verb names the
/// action — never "OK". Naming alerts put a `paper` field in the body.
struct PanelAlert: View {
    let title: String
    var message: String?
    /// Present a field when the alert is asking for a name.
    var field: Binding<String>?
    var fieldPlaceholder: String = ""
    var cancelTitle: String = "Cancel"
    /// The verb, e.g. Delete / Create / Rename.
    let verb: String
    var isDestructive = false
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Metric.s8) {
                Text(title)
                    .typeRole(.title)
                    .foregroundStyle(Theme.Ink.ink)
                if let message {
                    Text(message)
                        .typeRole(.body)
                        .foregroundStyle(Theme.Ink.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let field {
                    TextField(fieldPlaceholder, text: field)
                        .typeRole(.body)
                        .focused($fieldFocused)
                        .onSubmit(onConfirm)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 10)
                        .background(Theme.Surface.paper)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                                .stroke(fieldFocused ? Theme.Accent.clay : Theme.Line.line2,
                                        lineWidth: 1)
                        }
                        .onAppear { fieldFocused = true }
                }
            }
            .padding(Theme.Metric.panelPadding)

            // footer: band fill, buttons right-aligned, cancel first
            HStack(spacing: Theme.Metric.s8) {
                Spacer()
                PanelButton(title: cancelTitle, action: onCancel)
                PanelButton(title: verb, kind: isDestructive ? .destructive : .primary,
                            action: onConfirm)
            }
            .padding(Theme.Metric.s12)
            .background(Theme.Surface.band)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.Line.line2).frame(height: 1)
            }
        }
        .frame(width: Theme.Metric.alertWidth)
        .background(Theme.Surface.panel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rPanel))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metric.rPanel)
                .stroke(Theme.Line.line2, lineWidth: 1)
        }
        .modifier(SheetShadow())
    }
}

/// A one-button notice, for messages that carry no decision.
struct PanelNotice: View {
    let title: String
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Metric.s8) {
                Text(title).typeRole(.title).foregroundStyle(Theme.Ink.ink)
                Text(message).typeRole(.body).foregroundStyle(Theme.Ink.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Metric.panelPadding)
            HStack {
                Spacer()
                PanelButton(title: "Close", action: onDismiss)
            }
            .padding(Theme.Metric.s12)
            .background(Theme.Surface.band)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.Line.line2).frame(height: 1)
            }
        }
        .frame(width: Theme.Metric.alertWidth)
        .background(Theme.Surface.panel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rPanel))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metric.rPanel)
                .stroke(Theme.Line.line2, lineWidth: 1)
        }
        .modifier(SheetShadow())
    }
}

// MARK: - Sheet (§7.15)

/// 620 wide, inset 64 top and bottom, over a 34% dim. `Done` sits at the
/// trailing edge of the header; destructive actions belong in the body, last.
struct PanelSheet<Content: View>: View {
    let title: String
    var number: Int?
    let onDone: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Metric.s8) {
                if let number { NumeralBadge(number: number) }
                Text(title)
                    .typeRole(.title)
                    .foregroundStyle(Theme.Ink.ink)
                    .lineLimit(1)
                Spacer(minLength: Theme.Metric.s8)
                PanelButton(title: "Done", action: onDone)
            }
            .padding(.horizontal, Theme.Metric.panelPadding)
            .padding(.vertical, Theme.Metric.s8)
            .background(Theme.Surface.panel)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.Line.line2).frame(height: 1)
            }

            ScrollView { content() }
                .background(Theme.Surface.panel)
        }
        .frame(width: Theme.Metric.sheetWidth)
        .padding(.vertical, 64)
        .background {
            RoundedRectangle(cornerRadius: Theme.Metric.rPanel)
                .fill(Theme.Surface.panel)
                .padding(.vertical, 64)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metric.rPanel)
                .stroke(Theme.Line.line2, lineWidth: 1)
                .padding(.vertical, 64)
        }
        .modifier(SheetShadow())
    }
}

/// A label/value row inside a sheet: 40pt, values right-aligned, machine values
/// in mono.
struct SheetRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: () -> Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Metric.s12) {
            Text(label)
                .typeRole(.body)
                .foregroundStyle(Theme.Ink.ink2)
            Spacer(minLength: Theme.Metric.s8)
            value()
        }
        .padding(.horizontal, Theme.Metric.panelPadding)
        .padding(.vertical, Theme.Metric.sheetRowVertical)
        .frame(minHeight: Theme.Metric.sheetRowMinHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Line.line).frame(height: 1)
        }
    }
}

extension SheetRow where Value == AnyView {
    /// `typeRole` returns `some View`, so the convenience form erases.
    init(_ label: String, _ text: String, mono: Bool = false) {
        self.init(label: label) {
            AnyView(
                Text(text)
                    .typeRole(mono ? .data : .body)
                    .foregroundStyle(Theme.Ink.ink)
                    .multilineTextAlignment(.trailing)
            )
        }
    }
}

private struct SheetShadow: ViewModifier {
    func body(content: Content) -> some View { Theme.Elevation.sheet(content) }
}

// MARK: - Presentation

/// The dim behind sheets and alerts, which also dismisses on tap when the
/// presentation is cancellable.
struct DialogScrim: View {
    var onTap: (() -> Void)?

    var body: some View {
        Theme.Line.dim
            .ignoresSafeArea()
            .onTapGesture { onTap?() }
            .accessibilityHidden(true)
    }
}

// MARK: - Toggle (§7.12)

/// 44 x 26, square knob, hard edges: a panel switch, not an iOS capsule.
struct PanelToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(Theme.Motion.pillState) { isOn.toggle() }
        } label: {
            HStack(spacing: Theme.Metric.s12) {
                Text(title).typeRole(.body).foregroundStyle(Theme.Ink.ink)
                Spacer(minLength: Theme.Metric.s8)
                track
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(title, isOn: $isOn)
        }
    }

    private var track: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                .fill(isOn ? Theme.Accent.clayTint : Theme.Surface.well)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(isOn ? Theme.Accent.clay : Theme.Line.line2, lineWidth: 1)
                }
            RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                .fill(isOn ? Theme.Accent.clay : Theme.Surface.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(isOn ? Theme.Accent.clayPress : Theme.Line.line2, lineWidth: 1)
                }
                .frame(width: 20, height: 20)
                .padding(3)
        }
        .frame(width: 44, height: 26)
    }
}

// MARK: - Field (§7.13)

/// `paper` fill inside a panel, hard border, focus turns the border clay with
/// no glow. Secure fields show a mono mask.
struct PanelField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var isMono = false

    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .typeRole(isSecure || isMono ? .data : .body)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused($focused)
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(Theme.Surface.paper)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                .stroke(focused ? Theme.Accent.clay : Theme.Line.line2, lineWidth: 1)
        }
    }
}

/// An inset `well` block for machine output: self-test results, errors.
struct WellBlock: View {
    let text: String
    var tint: Color = Theme.Ink.ink2

    var body: some View {
        Text(text)
            .typeRole(.data)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Metric.s8)
            .background(Theme.Surface.well)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                    .stroke(Theme.Line.line2, lineWidth: 1)
            }
    }
}

/// A block of prose under a group of controls.
struct PanelNote: View {
    let text: String
    var body: some View {
        Text(text)
            .typeRole(.meta)
            .foregroundStyle(Theme.Ink.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
