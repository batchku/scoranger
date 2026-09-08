import SwiftUI

/// A set list the band shares: its running order, who is in it, and the things
/// each of them may do to it.
///
/// The product ask, principles 2, 4 and 5 of design/FIREBASE.md §0. The screen
/// is deliberately thin -- every rule it appears to apply is decided elsewhere
/// and tested there (`SetlistPermission`, `SharedOrder`, `SetlistInvite`), and
/// the copy that actually binds is `firebase/firestore.rules`.
///
/// It differs from the local set list screen in one visible way, and it has to:
/// **a shared set list you cannot reach is read-only and says so.** Your own
/// library is editable offline forever; this is cloud-authoritative and cached
/// (§4.4, §5.3). Showing a reorder that will never land is worse than refusing
/// it.
struct SharedSetlistScreen: View {
    let setlistId: String
    var onBack: () -> Void

    @EnvironmentObject var state: AppState
    @EnvironmentObject var shared: SharedSetlists
    @EnvironmentObject var signIn: SignIn

    @State private var inviting = false
    @State private var address = ""
    @State private var sending = false
    @State private var invitation: String?
    @State private var adding = false
    @State private var confirmingDelete = false

    private var setlist: SharedSetlists.Setlist? {
        shared.setlists.first { $0.id == setlistId }
    }

    private var role: SetlistRole { setlist?.role ?? .reader }
    private var mayEdit: Bool {
        SetlistPermission.allows(role, .addEntry) && !shared.isStale
    }

    var body: some View {
        Screen(title: setlist?.name ?? "Shared set list",
               backLabel: "My library",
               subtitle: subtitle,
               onBack: onBack) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if shared.isStale { offline }
                order
                actions
                people
            }
        }
        .onAppear { shared.open(setlistId) }
        .onDisappear { shared.close() }
    }

    private var subtitle: String? {
        guard let setlist else { return nil }
        let people = setlist.members.count
        return people == 1 ? "Just you" : "\(people) people"
    }

    // MARK: - offline

    private var offline: some View {
        // §5.3: named, and the actions are gone rather than dead. A greyed
        // button a person can still tap teaches them the app is broken.
        PanelNote(text: "You're offline, so this is the set list as you last "
                  + "saw it. You can read and mark it up; adding and "
                  + "reordering need a connection.")
            .padding(Theme.Metric.panelPadding)
            .accessibilityIdentifier("shared-offline")
    }

    // MARK: - the running order

    @ViewBuilder
    private var order: some View {
        BandHeader("Running order")
        if shared.entries.isEmpty {
            PanelNote(text: mayEdit
                      ? "Nothing yet — add an arrangement below."
                      : "Nothing in this set list yet.")
                .padding(Theme.Metric.panelPadding)
                .accessibilityIdentifier("shared-empty")
        }
        ForEach(Array(shared.entries.enumerated()), id: \.element.id) { index, entry in
            entryRow(entry, position: index + 1)
        }
    }

    private func entryRow(_ entry: SharedSetlists.Entry, position: Int) -> some View {
        HStack(spacing: Theme.Metric.s12) {
            Text("\(position)").typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                .frame(width: 20, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).typeRole(.body).foregroundStyle(Theme.Ink.ink)
                    .lineLimit(1)
                if let composer = entry.composer, !composer.isEmpty {
                    Text(composer).typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Metric.s8)
            if mayEdit {
                Button { move(entry, by: -1) } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.plain)
                .foregroundStyle(position == 1 ? Theme.Ink.ink3 : Theme.Accent.clayStrong)
                .disabled(position == 1)
                .accessibilityIdentifier("shared-up-\(position)")

                Button { move(entry, by: 1) } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.plain)
                .foregroundStyle(position == shared.entries.count
                                 ? Theme.Ink.ink3 : Theme.Accent.clayStrong)
                .disabled(position == shared.entries.count)
                .accessibilityIdentifier("shared-down-\(position)")
            }
        }
        .padding(.horizontal, Theme.Metric.s16)
        .frame(minHeight: Theme.Metric.hitTarget)
        .contentShape(Rectangle())
        .accessibilityIdentifier("shared-entry-\(position)")
    }

    /// Reorder by one place. The write is a single fractional index on a single
    /// document (§6.5), which is what lets two people move different entries at
    /// the same time without either move being lost.
    private func move(_ entry: SharedSetlists.Entry, by offset: Int) {
        let list = shared.entries
        guard let at = list.firstIndex(of: entry),
              let landing = SharedOrder.neighbours(moving: at, by: offset,
                                                   in: list.map(\.order))
        else { return }
        Task {
            do {
                try await shared.move(entry, afterKey: landing.before,
                                      beforeKey: landing.after, in: setlistId)
            } catch {
                state.report("move that entry", error)
            }
        }
    }

    // MARK: - what can be done

    @ViewBuilder
    private var actions: some View {
        BandHeader("This set list")
        if mayEdit {
            PanelButton(title: "Add an arrangement", kind: .normal,
                        identifier: "shared-add") { adding = true }
        }
        if SetlistPermission.allows(role, .invite) && !shared.isStale {
            PanelButton(title: "Invite somebody", kind: .normal,
                        identifier: "shared-invite") { inviting = true; address = "" }
            if inviting { inviteField }
        }
        if let setlist, setlist.isOwner {
            // PRINCIPLE 4, the one asymmetry. Named as what it does to other
            // people, not as "Delete".
            PanelButton(title: confirmingDelete
                        ? "Delete for everybody — tap again"
                        : "Delete this set list",
                        kind: .destructive,
                        identifier: "shared-delete") {
                if confirmingDelete {
                    Task {
                        do { try await shared.delete(setlist); onBack() }
                        catch { state.report("delete that set list", error) }
                    }
                } else {
                    confirmingDelete = true
                }
            }
            if confirmingDelete {
                PanelNote(text: "Everybody's markup on every arrangement in it "
                          + "goes too. Nobody else can do this.")
                    .padding(Theme.Metric.panelPadding)
            }
        } else if SetlistPermission.mayLeave(role) {
            PanelButton(title: "Leave this set list", kind: .destructive,
                        identifier: "shared-leave") {
                guard let uid = signIn.account?.uid else { return }
                Task {
                    do { try await shared.removeMember(uid, from: setlistId); onBack() }
                    catch { state.report("leave that set list", error) }
                }
            }
        }

        if adding { arrangementPicker }
    }

    // MARK: - inviting

    @ViewBuilder
    private var inviteField: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.s8) {
            TextField("Their email address", text: $address)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .accessibilityIdentifier("shared-invite-address")

            // The address has to be the one they sign in with: the Function
            // checks it against their VERIFIED token, so a typo is a refusal
            // rather than a stranger getting in (§0.4).
            Text("It has to be the address they sign in with.")
                .typeRole(.meta).foregroundStyle(Theme.Ink.ink3)

            if let invitation, let setlist {
                let text = SharedInviteLink.message(setlistName: setlist.name,
                                                    email: SetlistInvite.normalise(address),
                                                    inviteId: invitation)
                Text("Send them this. The link on its own gets nobody in — it "
                     + "only works for that address.")
                    .typeRole(.meta).foregroundStyle(Theme.Ink.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                ShareLink(item: text) {
                    Text("Send the invitation").typeRole(.control)
                }
                .accessibilityIdentifier("shared-invite-send")
            } else {
                PanelButton(title: sending ? "Inviting…" : "Invite",
                            kind: .primary, identifier: "shared-invite-confirm") {
                    guard !sending, let setlist else { return }
                    sending = true
                    Task {
                        defer { sending = false }
                        do { invitation = try await shared.invite(address, to: setlist) }
                        catch { state.report("send that invitation", error) }
                    }
                }
                .disabled(!SetlistInvite.looksLikeAnAddress(address))
            }
        }
        .padding(.horizontal, Theme.Metric.s16)
        .padding(.bottom, Theme.Metric.s12)
    }

    // MARK: - adding one of mine

    /// Every arrangement in my own library, to copy in.
    ///
    /// A COPY (§4.3, §12.13): the bytes go under `shared/{setlistId}/` so a
    /// member's permission to read them is a property of the path and not a
    /// chain of lookups into my private library. Books and sources have no
    /// share path at all and the engine refuses them (`bundle.share_payload`).
    @ViewBuilder
    private var arrangementPicker: some View {
        BandHeader("Add from my library")
        let already = Set(shared.entries.map(\.scoreUid))
        let mine = (state.manifest?.scores ?? [])
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
        if mine.isEmpty {
            PanelNote(text: "Nothing in your library yet.")
                .padding(Theme.Metric.panelPadding)
        }
        ForEach(mine) { score in
            Button {
                add(score)
            } label: {
                HStack {
                    Text(score.name).typeRole(.body).foregroundStyle(Theme.Ink.ink)
                        .lineLimit(1)
                    Spacer(minLength: Theme.Metric.s8)
                    if let uid = score.uid, already.contains(uid) {
                        Text("in the set").typeRole(.meta)
                            .foregroundStyle(Theme.Ink.ink3)
                    }
                }
                .padding(.horizontal, Theme.Metric.s16)
                .frame(minHeight: Theme.Metric.hitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("shared-candidate-\(score.slug)")
        }
    }

    private func add(_ score: ScoreDoc) {
        Task {
            do {
                // The engine decides what an entry carries, because the engine
                // is what knows which version is pinned and where it lives.
                let payload = try await state.sharePayload(for: score.slug)
                let last = shared.entries.last?.order
                try await shared.addEntry(to: setlistId, payload: payload,
                                          after: last, before: nil)
                adding = false
            } catch {
                state.report("add that arrangement", error)
            }
        }
    }

    // MARK: - who is in it

    @ViewBuilder
    private var people: some View {
        if let setlist {
            BandHeader("Who's in it")
            ForEach(setlist.members.keys.sorted(), id: \.self) { uid in
                let theirs = SetlistRole(rawValue: setlist.members[uid] ?? "") ?? .reader
                HStack(spacing: Theme.Metric.s12) {
                    // Colour first, because it is how their marks are told
                    // apart on the page (§6.3).
                    Circle()
                        .fill(InkLayers.colour(slot: InkLayers.colourSlot(
                            for: uid, participants: Array(setlist.members.keys))))
                        .frame(width: 12, height: 12)
                    Text(uid == signIn.account?.uid ? "You" : shortened(uid))
                        .typeRole(.body).foregroundStyle(Theme.Ink.ink)
                    Spacer(minLength: Theme.Metric.s8)
                    Text(theirs == .owner ? "made it" : "can add and reorder")
                        .typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                    if setlist.isOwner && uid != signIn.account?.uid {
                        Button {
                            Task {
                                do { try await shared.removeMember(uid, from: setlistId) }
                                catch { state.report("remove that person", error) }
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Accent.clayStrong)
                        .accessibilityIdentifier("shared-remove-\(uid)")
                    }
                }
                .padding(.horizontal, Theme.Metric.s16)
                .frame(minHeight: Theme.Metric.hitTarget)
            }
            PanelNote(text: "Up to \(SetlistPermission.membershipCap) people in "
                      + "a set list. Everybody can add, reorder and mark up; "
                      + "only whoever made it can delete it.")
                .padding(Theme.Metric.panelPadding)
        }
    }

    /// A uid is not a name and this build has no directory of people, so it is
    /// shortened rather than shown whole or invented into a name.
    private func shortened(_ uid: String) -> String {
        uid.count <= 8 ? uid : "Somebody · " + uid.suffix(4)
    }
}
