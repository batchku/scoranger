import SwiftUI

/// Shared set lists, where set lists are.
///
/// They sit in the library's set-list segment rather than behind an account
/// screen because a shared set list IS a set list: what a person is looking for
/// at a rehearsal is "the Tuesday set", and which of them happens to live in
/// the cloud is not how anybody sorts their music.
///
/// It shows nothing at all when signed out, and that is principle 1 of
/// design/FIREBASE.md §0: *"no login should ever gate using the app."* A reader
/// with no account sees their library exactly as they always did -- not a
/// prompt, not a locked row, not an empty section explaining what they are
/// missing.
struct SharedSetlistsBand: View {
    var onOpen: (String) -> Void

    @EnvironmentObject var state: AppState
    @EnvironmentObject var signIn: SignIn
    @EnvironmentObject var shared: SharedSetlists

    @State private var naming = false
    @State private var draft = ""
    @State private var claiming = false

    var body: some View {
        // Signed out: nothing. Not a teaser.
        if signIn.account != nil {
            VStack(alignment: .leading, spacing: 0) {
                if let invite = state.pendingInvite { invitation(invite) }
                BandHeader("Shared with the band")
                if shared.setlists.isEmpty {
                    PanelNote(text: "Nothing shared yet. Make one, add "
                              + "arrangements to it, and invite whoever "
                              + "you're playing with.")
                        .padding(Theme.Metric.panelPadding)
                        .accessibilityIdentifier("shared-none")
                }
                ForEach(shared.setlists) { setlist in
                    Button { onOpen(setlist.id) } label: {
                        HStack(spacing: Theme.Metric.s12) {
                            Image(systemName: "person.2")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.Accent.clayStrong)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(setlist.name).typeRole(.body)
                                    .foregroundStyle(Theme.Ink.ink).lineLimit(1)
                                Text(setlist.isOwner ? "You made this"
                                     : "Shared with you")
                                    .typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                            }
                            Spacer(minLength: Theme.Metric.s8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.Ink.ink3)
                        }
                        .padding(.horizontal, Theme.Metric.s16)
                        .frame(minHeight: Theme.Metric.hitTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shared-row-\(setlist.id)")
                    Divider().overlay(Theme.Line.line)
                }
                if naming { nameField } else {
                    PanelButton(title: "New shared set list", kind: .normal,
                                identifier: "shared-new") { draft = ""; naming = true }
                }
            }
            .onAppear { shared.watchMemberships() }
        }
    }

    // MARK: - an invitation that arrived

    /// An invitation link that has been opened but not claimed.
    ///
    /// Shown rather than claimed silently: joining a set list means somebody
    /// else's copies of somebody else's music appear in this app, and that is
    /// a thing a person agrees to.
    @ViewBuilder
    private func invitation(_ inviteId: String) -> some View {
        BandHeader("You've been invited")
        PanelNote(text: "Somebody shared a set list with you. Joining it puts "
                  + "their running order in your library; your own music is "
                  + "not shared back.")
            .padding(Theme.Metric.panelPadding)
        PanelButton(title: claiming ? "Joining…" : "Join the set list",
                    kind: .primary, identifier: "shared-claim") {
            guard !claiming else { return }
            claiming = true
            Task {
                defer { claiming = false }
                do {
                    let id = try await shared.claim(inviteId: inviteId)
                    state.pendingInvite = nil
                    shared.watchMemberships()
                    onOpen(id)
                } catch {
                    state.report("join that set list", error)
                }
            }
        }
        PanelButton(title: "Not now", kind: .normal,
                    identifier: "shared-claim-dismiss") {
            state.pendingInvite = nil
        }
    }

    // MARK: - making one

    @ViewBuilder
    private var nameField: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.s8) {
            TextField("What's this set for?", text: $draft)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("shared-new-name")
            PanelButton(title: "Make it", kind: .primary,
                        identifier: "shared-new-confirm") {
                let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task {
                    do {
                        let id = try await shared.create(named: name)
                        naming = false
                        shared.watchMemberships()
                        onOpen(id)
                    } catch {
                        state.report("make that set list", error)
                    }
                }
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, Theme.Metric.s16)
        .padding(.bottom, Theme.Metric.s12)
    }
}
