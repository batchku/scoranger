import SwiftUI

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
            Theme.Rule()
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
                        .stroke(isOn ? Theme.Accent.clay : Color.clear, lineWidth: 1.5)
                }
            RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                .fill(isOn ? Theme.Accent.clay : Theme.Surface.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(isOn ? Theme.Accent.clayPress : Color.clear, lineWidth: 1.5)
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
        // explicit, never inherited: an unstyled field takes the system's
        // foreground colour, which is white wherever the OS thinks it is dark
        .foregroundStyle(Theme.Ink.ink)
        .tint(Theme.Accent.clay)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .focused($focused)
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(Theme.Surface.paper)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                .stroke(focused ? Theme.Accent.clay : Color.clear, lineWidth: 1.5)
        }
    }
}

/// A `PanelField` with its name above it. Every editable field in a form gets
/// one: a placeholder disappears the moment there is text in the box, so it
/// cannot be the only thing naming the field.
struct LabeledField<Trailing: View>: View {
    let label: String
    @Binding var text: String
    var isMono = false
    var identifier: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .typeRole(.label)
                .foregroundStyle(Theme.Ink.ink2)
            HStack(spacing: Theme.Metric.s8) {
                PanelField(placeholder: label, text: $text, isMono: isMono)
                    .accessibilityIdentifier(identifier ?? label)
                    .accessibilityLabel(label)
                trailing()
            }
        }
    }
}

extension LabeledField where Trailing == EmptyView {
    init(_ label: String, text: Binding<String>, isMono: Bool = false,
         identifier: String? = nil) {
        self.init(label: label, text: text, isMono: isMono,
                  identifier: identifier) { EmptyView() }
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
