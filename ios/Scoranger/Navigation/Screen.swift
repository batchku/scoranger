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
                // collapsed to ONE element: a Button whose label is a stack is
                // reported as a container, and the identifier lands on
                // something untappable -- the selection chip's bug, third time
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Back to \(backLabel)")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("screen-back")

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
                Theme.Rule()
            }

            ScrollView {
                // The content column is capped and centred. Full-bleed rows on
                // a 13" iPad put a label and its own chevron 1300pt apart
                // (L34); a row has to read as one thing.
                content()
                    .frame(maxWidth: Theme.Metric.readingColumn)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.Surface.band)
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
    /// The row stands for what is on screen right now -- one version of many,
    /// one arrangement of a piece. Marked, not just tinted, so a test and a
    /// screen reader can both tell which one it is.
    var isSelected: Bool = false
    var identifier: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Metric.s8) {
                Text(title).typeRole(.row)
                    .foregroundStyle(isDestructive ? Theme.Status.danger : Theme.Ink.ink)
                    // WRAPS rather than overflowing (§6.3 rule 1). At XXXL
                    // "Chord symbols" plus its value plus the chevron is wider
                    // than a phone, and an HStack that cannot fit its children
                    // draws them outside itself: the rows measured 429pt in a
                    // 402pt window, 13.7 off each edge.
                    .fixedSize(horizontal: false, vertical: true)
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
            .background(isSelected ? Theme.Accent.clayTint : Color.clear)
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle().fill(Theme.Accent.clay).frame(width: 3)
                }
            }
            .contentShape(Rectangle())
            // A rule under every row. Without one the rows ran together into a
            // column of floating text, which is most of why these screens read
            // as unfinished (L34).
            .overlay(alignment: .bottom) {
                Theme.Rule()
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
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
    /// What the confirming button says. Deleting is the common case, but the
    /// same two-step strip is the app's answer to any irreversible action --
    /// a reset that throws away every nudge in a part is one.
    var verb: String = "Delete"
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
                Text(verb).typeRole(.control)
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
                .accessibilityIdentifier("inline-name-field")
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

/// The undo bar (§5.2), in the action bar's slot.
///
/// A bar is not a modal: anchored, blocking nothing, and the list scrolls
/// behind it. It is offered because the engine marks rather than unlinks --
/// without the two-phase delete behind it this would be a button that lies.
/// What the app has to say when something did not happen.
///
/// It exists because `notice` was written in five places and read in none:
/// an import that found nothing, a PDF that would not transcribe, a missing OMR
/// service -- each set a message that no view ever showed, so the app answered
/// every one of them by returning to the library without a word. A message
/// stays until it is dismissed; it is shown BECAUSE something went wrong, and a
/// reader who looked away should still find it.
struct NoticeBar: View {
    let message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Metric.s8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Ink.ink2)
                .padding(.top, 2)
            Text(message).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("notice-text")
            Spacer(minLength: Theme.Metric.s8)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Ink.ink2)
                    .frame(width: Theme.Metric.hitTarget, height: Theme.Metric.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("notice-dismiss")
        }
        .padding(.horizontal, Theme.Metric.s16)
        .padding(.vertical, Theme.Metric.s12)
        .background(Theme.Surface.panel)
        .overlay(alignment: .top) { Theme.Rule() }
        .shadow(color: Color(hex: 0x1A1917).opacity(0.07), radius: 18, y: -6)
        .accessibilityIdentifier("notice-bar")
    }
}

/// What a bundle holds, and the one tap that takes it in.
///
/// Somebody AirDropped an arrangement or a setlist. Nothing has been imported
/// yet: this says what is in the file -- what it is called, how many pieces,
/// whose markup rides along -- and waits (design/FIREBASE.md §13.3).
///
/// A bar rather than a sheet, on the UndoBar's shape, because the no-modal rule
/// (NAV_MODAL_FREE_0.4.2 §1) applies to surfaces this app invents and this is
/// one. The reader can ignore it and it costs them nothing.
struct BundleOfferBar: View {
    let summary: String
    let detail: String
    var onImport: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Theme.Metric.s8) {
            Image(systemName: "shippingbox")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Ink.ink2)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                    .accessibilityIdentifier("bundle-offer-summary")
                Text(detail).typeRole(.data).foregroundStyle(Theme.Ink.ink3)
                    .accessibilityIdentifier("bundle-offer-detail")
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Metric.s8)
            PanelButton(title: "Add to my library", kind: .primary, action: onImport)
                .accessibilityIdentifier("bundle-import")
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Ink.ink2)
                    .frame(width: Theme.Metric.hitTarget, height: Theme.Metric.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("bundle-dismiss")
        }
        .padding(.horizontal, Theme.Metric.s16)
        .padding(.vertical, Theme.Metric.s8)
        .frame(minHeight: 56)
        .background(Theme.Surface.panel)
        .overlay(alignment: .top) { Theme.Rule() }
        .shadow(color: Color(hex: 0x1A1917).opacity(0.07), radius: 18, y: -6)
        .accessibilityIdentifier("bundle-offer-bar")
    }
}

struct UndoBar: View {
    let what: String
    var seconds: Int = 10
    var onUndo: () -> Void
    var onDismiss: () -> Void

    @State private var remaining: Int = 10

    var body: some View {
        HStack(spacing: Theme.Metric.s8) {
            Text("Deleted \(what).").typeRole(.row).foregroundStyle(Theme.Ink.ink)
            Text("restorable for \(remaining)s").typeRole(.data)
                .foregroundStyle(Theme.Ink.ink3)
            Spacer(minLength: Theme.Metric.s8)
            PanelButton(title: "Undo", kind: .primary, action: onUndo)
                .accessibilityIdentifier("undo-delete")
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Ink.ink2)
                    .frame(width: Theme.Metric.hitTarget, height: Theme.Metric.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, Theme.Metric.s16)
        .frame(height: 56)
        .background(Theme.Surface.panel)
        .overlay(alignment: .top) { Theme.Rule() }
        .shadow(color: Color(hex: 0x1A1917).opacity(0.07), radius: 18, y: -6)
        .accessibilityIdentifier("undo-bar")
        .onAppear { remaining = seconds }
        .task {
            // A plain countdown, and it only decides when the BAR goes: the
            // engine's own window is what decides whether undo would work, and
            // it is deliberately longer so a slow tap still lands.
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                remaining -= 1
            }
            onDismiss()
        }
    }
}

/// A name you edit by tapping it.
///
/// There is no Rename button anywhere any more: the value IS the control. A
/// button whose only job is to let you edit the thing next to it is a button
/// that exists because the thing next to it was not tappable -- so the thing is
/// tappable instead, and the button goes.
///
/// Commit on return, cancel on escape or by tapping away. Modal-free by
/// construction: the keyboard is the only thing that overlays, and that is the
/// OS (NAV_MODAL_FREE_0.4.2 §5.1).
struct EditableTitle: View {
    let text: String
    var role: Theme.Role = .titleS
    var identifier: String
    /// Opens straight into the field, for a row that is already being renamed.
    var startEditing = false
    var onCommit: (String) -> Void

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing {
                TextField("Name", text: $draft)
                    .typeRole(role)
                    .foregroundStyle(Theme.Ink.ink)
                    .tint(Theme.Accent.clay)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { commit() }
                    .padding(.horizontal, Theme.Metric.s6)
                    .padding(.vertical, 3)
                    .background(Theme.Surface.paper)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                            .stroke(Theme.Accent.clay, lineWidth: 1)
                    }
                    .accessibilityIdentifier("\(identifier)-field")
                    .onAppear { focused = true }
                    .onChange(of: focused) { _, isFocused in
                        // tapping away commits, the way a renamed file does
                        if !isFocused && editing { commit() }
                    }
            } else {
                Button {
                    draft = text
                    editing = true
                } label: {
                    Text(text).typeRole(role).foregroundStyle(Theme.Ink.ink)
                        .lineLimit(1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel("\(text), tap to rename")
            }
        }
        .onAppear {
            if startEditing && !editing { draft = text; editing = true }
        }
    }

    private func commit() {
        editing = false
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != text else { return }
        onCommit(name)
    }
}
