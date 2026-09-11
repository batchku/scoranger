import SwiftUI

/// Where an arrangement should be filed (NAV_MODAL_FREE_0.4.2 §3.3).
///
/// What `MoveToPieceSheet` was. The spec calls filing the single biggest hole
/// the revision closes: it previously existed only as a drag or a long press,
/// so someone who did not know the gesture had no way to file anything.
struct MoveToPieceScreen: View {
    @EnvironmentObject var state: AppState
    let moving: [String]
    var onBack: () -> Void

    @State private var creating = false
    @State private var draft = ""

    var body: some View {
        Screen(title: "Move to piece", backLabel: "Back",
               subtitle: subject, onBack: onBack) {
            VStack(alignment: .leading, spacing: 0) {
                // The consequence, stated before the choice rather than
                // discovered after it: #N is a position within a piece.
                Text("Arrangements are numbered within their piece, so moving "
                     + "these renumbers both pieces.")
                    .typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Metric.s20)
                    .padding(.vertical, Theme.Metric.s12)

                BandHeader("Pieces")
                ForEach(state.manifest?.pieces ?? []) { piece in
                    ScreenRow(title: piece.name,
                              value: current == piece.slug ? "current" : nil,
                              leads: false,
                              identifier: "move-target-\(piece.slug)") {
                        commit(to: piece.slug)
                    }
                }

                BandHeader("Or")
                if creating {
                    InlineRenameRow(text: $draft,
                                    onSave: { commitNewPiece() },
                                    onCancel: { creating = false })
                } else {
                    ScreenRow(title: "New piece", leads: false,
                              identifier: "move-target-new") {
                        draft = ""
                        creating = true
                    }
                }
                ScreenRow(title: "Remove from piece", value: "leaves them unfiled",
                          leads: false, identifier: "move-target-none") {
                    commit(to: nil)
                }
            }
            .padding(.bottom, Theme.Metric.s32)
        }
    }

    private var subject: String {
        moving.count == 1
            ? (state.manifest?.scores.first { $0.slug == moving[0] }
                .map { ScoreTitle.arrangementName(title: $0.title, name: $0.name,
                                                  slug: $0.slug) } ?? "one arrangement")
            : "\(moving.count) arrangements"
    }

    private var current: String? {
        moving.count == 1 ? state.placement(of: moving[0])?.piece.slug : nil
    }

    private func commit(to piece: String?) {
        for slug in moving { state.assignToPiece(scoreSlug: slug, piece: piece) }
        onBack()
    }

    private func commitNewPiece() {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        creating = false
        guard !name.isEmpty else { return }
        Task {
            // assign-piece creates the piece when it is missing, so filing into
            // a new one is the same call with a new name
            for slug in moving { state.assignToPiece(scoreSlug: slug, piece: name) }
            onBack()
        }
    }
}

/// Which set lists an arrangement belongs to (§3.4). Membership commits on tap:
/// nothing to confirm, nothing to dismiss.
struct SetlistsForScreen: View {
    @EnvironmentObject var state: AppState
    let slug: String
    var onBack: () -> Void

    @State private var creating = false
    @State private var draft = ""

    var body: some View {
        Screen(title: "Set lists", backLabel: "Back", subtitle: name, onBack: onBack) {
            VStack(alignment: .leading, spacing: 0) {
                BandHeader("In these set lists")
                ForEach(state.manifest?.setlists ?? []) { setlist in
                    let member = setlist.arrangements.contains(slug)
                    Button {
                        Task {
                            if member {
                                _ = await state.removeFromSetlist(setlist: setlist.slug,
                                                                  score: slug)
                            } else {
                                _ = await state.addToSetlist(setlist: setlist.slug,
                                                             score: slug)
                            }
                        }
                    } label: {
                        HStack(spacing: Theme.Metric.s8) {
                            Image(systemName: member ? "checkmark.square.fill" : "square")
                                .foregroundStyle(member ? Theme.Accent.clayStrong
                                                        : Theme.Ink.ink3)
                            Text(setlist.name).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                            Spacer()
                            Text("\(setlist.arrangements.count)").typeRole(.data)
                                .foregroundStyle(Theme.Ink.ink3)
                        }
                        .padding(.horizontal, Theme.Metric.s20)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chooser-\(setlist.slug)")
                    .accessibilityAddTraits(member ? [.isSelected] : [])
                }
                BandHeader("Or")
                if creating {
                    InlineRenameRow(text: $draft, onSave: commitNew,
                                    onCancel: { creating = false })
                } else {
                    ScreenRow(title: "New set list", leads: false,
                              identifier: "setlists-new") { draft = ""; creating = true }
                }
            }
            .padding(.bottom, Theme.Metric.s32)
        }
    }

    private var name: String? {
        state.manifest?.scores.first { $0.slug == slug }
            .map { ScoreTitle.arrangementName(title: $0.title, name: $0.name,
                                              slug: $0.slug) }
    }

    private func commitNew() {
        let wanted = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        creating = false
        guard !wanted.isEmpty else { return }
        Task {
            if let made = await state.createSetlist(name: wanted) {
                _ = await state.addToSetlist(setlist: made, score: slug)
            }
        }
    }
}

/// A set list's running order (§3.5).
///
/// Here the row's ☰ EXPANDS rather than pushes, by the rule in
/// RowMenuBehaviour: every action is one tap and positional. One row open at a
/// time, and the open row's ☰ is lit so the two behaviours are told apart.
struct SetlistScreen: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var shared: SharedSetlists
    @EnvironmentObject var signIn: SignIn
    let slug: String
    var onBack: () -> Void
    var onOpen: (String) -> Void
    var push: (Route) -> Void

    @State private var expanded: String?

    private var setlist: SetlistDoc? {
        state.manifest?.setlists?.first { $0.slug == slug }
    }

    var body: some View {
        Screen(title: "", backLabel: "My library",
               subtitle: summary, onBack: onBack,
               trailing: {
                   PanelButton(title: "Play from the top", kind: .primary) {
                       if let first = setlist?.arrangements.first { onOpen(first) }
                   }
                   .accessibilityIdentifier("setlist-play")
               }) {
            VStack(alignment: .leading, spacing: 0) {
                // A set list could not be renamed at all (#52). The name IS
                // the control, the same as a piece's and an arrangement's --
                // the engine has had `rename-setlist` all along and nothing on
                // screen ever called it.
                EditableTitle(text: setlist?.name ?? "Set list", role: .title,
                              identifier: "setlist-title") { name in
                    Task { _ = await state.renameSetlist(setlist: slug, name: name) }
                }
                .padding(.horizontal, Theme.Metric.s20)
                .padding(.top, Theme.Metric.s12)
                .padding(.bottom, Theme.Metric.s8)

                BandHeader("Running order")
                ForEach(Array((setlist?.arrangements ?? []).enumerated()), id: \.offset) { index, member in
                    memberRow(member, at: index)
                    Divider().overlay(Theme.Line.line)
                }
                BandHeader("This set list")
                ScreenRow(title: "Add arrangements", leads: false,
                          identifier: "setlist-add-\(slug)") { push(.addArrangements(slug)) }
                if let setlist, setlist.isShared {
                    ScreenRow(title: "People in this set list", leads: true,
                              identifier: "setlist-people-\(slug)") {
                        if let shareId = setlist.shareId { push(.sharedSetlist(shareId)) }
                    }
                }
                // A WAY OUT, on the set list's own screen. A joined set list that
                // arrived with none of its music could not be removed from the
                // device at all: Edit-mode delete was the only path and it left
                // the membership behind. Named as what it does -- a member
                // leaves, the owner deletes for everybody -- with the same
                // second tap the shared screen asks for.
                if let setlist {
                    removal(for: setlist)
                }
            }
            .padding(.bottom, Theme.Metric.s32)
        }
    }

    @State private var confirmingRemoval = false

    @ViewBuilder
    private func removal(for setlist: SetlistDoc) -> some View {
        let mine = setlist.ownerUid == nil || setlist.ownerUid == signIn.account?.uid
        let title: String = {
            if !setlist.isShared { return "Delete this set list" }
            return mine ? "Delete for everybody" : "Leave this set list"
        }()
        ScreenRow(title: confirmingRemoval ? "\(title) — tap again" : title,
                  leads: false, isDestructive: true,
                  identifier: "setlist-remove-\(slug)") {
            guard confirmingRemoval else { confirmingRemoval = true; return }
            Task {
                let done: Bool
                if !setlist.isShared {
                    done = await state.deleteSetlist(slug)
                } else if mine {
                    guard let shareId = setlist.shareId else { return }
                    do {
                        let remote = try await shared.fetch(shareId)
                        done = await state.deleteSharedSetlistEverywhere(setlist, shared: shared, remote: remote)
                    } catch {
                        state.report("delete that set list", error); return
                    }
                } else {
                    guard let uid = signIn.account?.uid else {
                        state.notice = "Sign in to leave a shared set list."; return
                    }
                    done = await state.leaveSharedSetlist(setlist, shared: shared, uid: uid)
                }
                if done { onBack() }
            }
        }
        if confirmingRemoval, setlist.isShared, mine {
            PanelNote(text: "Everybody's copy of the running order and markup goes too. "
                      + "Nobody else can do this.")
                .padding(Theme.Metric.panelPadding)
        }
    }

    private func memberRow(_ member: String, at index: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Metric.s12) {
                Button { onOpen(member) } label: {
                    HStack(spacing: Theme.Metric.s12) {
                        NumeralBadge(number: index + 1, role: .numeralM)
                        Text(label(for: member)).typeRole(.row)
                            .foregroundStyle(Theme.Ink.ink)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("setlist-member-\(member)")

                RowMenuButton(identifier: "row-menu-\(member)",
                              label: "Manage \(label(for: member))",
                              isOpen: expanded == member) {
                    expanded = expanded == member ? nil : member
                }
            }
            .padding(.horizontal, Theme.Metric.s20)
            .padding(.vertical, 9)

            if expanded == member { memberActions(member, at: index) }
        }
    }

    private func memberActions(_ member: String, at index: Int) -> some View {
        HStack(spacing: Theme.Metric.s6) {
            action("Move up", id: "arr-up-\(member)", enabled: index > 0) {
                move(member, by: -1)
            }
            action("Move down", id: "arr-down-\(member)",
                   enabled: index + 1 < (setlist?.arrangements.count ?? 0)) {
                move(member, by: 1)
            }
            action("Manage", id: "setlist-manage-\(member)", enabled: true) {
                push(.arrangement(member))
            }
            action("Remove", id: "setlist-remove-\(member)", enabled: true,
                   destructive: true) {
                Task { _ = await state.removeFromSetlist(setlist: slug, score: member) }
                expanded = nil
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Metric.s20)
        .padding(.bottom, Theme.Metric.s8)
        .background(Theme.Surface.well)
    }

    private func action(_ title: String, id: String, enabled: Bool,
                        destructive: Bool = false,
                        run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title).typeRole(.meta)
                .foregroundStyle(destructive ? Theme.Status.danger : Theme.Ink.ink2)
                .padding(.horizontal, Theme.Metric.s8)
                .padding(.vertical, 5)
                .background(Theme.Surface.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(Theme.Line.line2, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.42)
        .accessibilityIdentifier(id)
    }

    private func move(_ member: String, by delta: Int) {
        guard var order = setlist?.arrangements,
              let from = order.firstIndex(of: member) else { return }
        let to = from + delta
        guard order.indices.contains(to) else { return }
        order.swapAt(from, to)
        Task { _ = await state.reorderSetlist(slug, order: order) }
    }

    private func label(for member: String) -> String {
        if let p = state.placement(of: member) { return "\(p.piece.name) #\(p.number)" }
        return state.manifest?.scores.first { $0.slug == member }
            .map { ScoreTitle.arrangementName(title: $0.title, name: $0.name,
                                              slug: $0.slug) } ?? member
    }

    private var summary: String? {
        guard let n = setlist?.arrangements.count else { return nil }
        return "\(n) arrangement\(n == 1 ? "" : "s")"
    }
}

/// Which arrangements a set list holds — the other direction of membership.
struct AddArrangementsScreen: View {
    @EnvironmentObject var state: AppState
    let slug: String
    var onBack: () -> Void

    var body: some View {
        Screen(title: "Add arrangements", backLabel: "Back", onBack: onBack) {
            VStack(alignment: .leading, spacing: 0) {
                BandHeader("In this set list")
                ForEach(state.manifest?.scores ?? []) { score in
                    let member = (state.manifest?.setlists?
                        .first { $0.slug == slug }?.arrangements ?? []).contains(score.slug)
                    Button {
                        Task {
                            if member {
                                _ = await state.removeFromSetlist(setlist: slug,
                                                                  score: score.slug)
                            } else {
                                _ = await state.addToSetlist(setlist: slug, score: score.slug)
                            }
                        }
                    } label: {
                        HStack(spacing: Theme.Metric.s8) {
                            Image(systemName: member ? "checkmark.square.fill" : "square")
                                .foregroundStyle(member ? Theme.Accent.clayStrong
                                                        : Theme.Ink.ink3)
                            Text(label(score)).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                            Spacer()
                        }
                        .padding(.horizontal, Theme.Metric.s20)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        member ? "picker-remove-\(score.slug)" : "picker-add-\(score.slug)")
                }
            }
            .padding(.bottom, Theme.Metric.s32)
        }
    }

    private func label(_ score: ScoreDoc) -> String {
        if let p = state.placement(of: score.slug) { return "\(p.piece.name) #\(p.number)" }
        return ScoreTitle.arrangementName(title: score.title, name: score.name,
                                          slug: score.slug)
    }
}

/// The version history (§3.6). Replaces the old version menu and the sheet's
/// nested list: tapping a version displays it and returns.
struct VersionsScreen: View {
    @EnvironmentObject var state: AppState
    let slug: String
    var onBack: () -> Void
    var onShow: (String?) -> Void

    @State private var expanded: Set<String> = []

    var body: some View {
        Screen(title: "Versions", backLabel: "Back", subtitle: name, onBack: onBack) {
            VStack(alignment: .leading, spacing: 0) {
                BandHeader("History")
                ForEach(groups) { group in
                    groupRow(group)
                    if expanded.contains(group.id) {
                        ForEach(group.subs.reversed(), id: \.id) { step in
                            ScreenRow(title: step.name,
                                      value: VersionLabel.text(op: step.op,
                                                               prompt: step.turn?.prompt),
                                      leads: false,
                                      isSelected: step.id == shown,
                                      identifier: "step-\(slug)-\(step.name)") {
                                show(step.id)
                            }
                            .padding(.leading, Theme.Metric.stepIndent)
                        }
                    }
                }
            }
            .padding(.bottom, Theme.Metric.s32)
        }
    }

    /// One chat prompt can produce a run of versions. They collapse into one
    /// row under the prompt that made them, opened by a caret -- history a
    /// person can read, rather than eight rows saying "transpose".
    private var groups: [AppState.VersionGroup] {
        score.map { state.versionGroups(for: $0) } ?? []
    }

    @ViewBuilder
    private func groupRow(_ group: AppState.VersionGroup) -> some View {
        let steps = group.subs.count
        if steps > 1 {
            let open = expanded.contains(group.id)
            // The caret is a SIBLING of the row, not something inside it:
            // ScreenRow collapses its children into one accessibility element,
            // so a caret drawn inside it would be findable and untappable.
            HStack(spacing: 0) {
                Button {
                    if open { expanded.remove(group.id) } else { expanded.insert(group.id) }
                } label: {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Ink.ink3)
                        .frame(width: Theme.Metric.hitTarget, height: Theme.Metric.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(open ? "Hide the steps of this prompt"
                                         : "Show the \(steps) steps of this prompt")
                .accessibilityIdentifier("steps-toggle-\(slug)-\(group.id)")
                ScreenRow(title: group.title,
                          value: "\(group.face.name) · \(steps) steps",
                          leads: false,
                          // while the steps are open they own the highlight:
                          // a group's steps include its own face, and lighting
                          // both read as two versions being open at once
                          isSelected: !open && group.subs.contains { $0.id == shown },
                          identifier: "version-\(slug)-\(group.face.name)") {
                    show(group.face.id)
                }
            }
            .padding(.leading, Theme.Metric.s6)
        } else {
            ScreenRow(title: group.face.name,
                      value: VersionLabel.text(op: group.face.op,
                                               prompt: group.face.turn?.prompt),
                      leads: false,
                      isSelected: group.face.id == shown,
                      identifier: "version-\(slug)-\(group.face.name)") {
                show(group.face.id)
            }
        }
    }

    /// The version on screen right now -- the pinned one, or the latest when
    /// nothing is pinned.
    private var shown: String? {
        state.displayedVersionID ?? score?.latest
    }

    private func show(_ version: String) {
        onShow(version == score?.latest ? nil : version)
    }

    private var score: ScoreDoc? { state.manifest?.scores.first { $0.slug == slug } }
    private var name: String? {
        score.map { ScoreTitle.arrangementName(title: $0.title, name: $0.name,
                                               slug: $0.slug) }
    }
}

/// Parts and ranges — read-only, from the version snapshot the engine writes.
struct PartsScreen: View {
    @EnvironmentObject var state: AppState
    let slug: String
    var onBack: () -> Void

    var body: some View {
        Screen(title: "Parts and ranges", backLabel: "Back", subtitle: name,
               onBack: onBack) {
            VStack(alignment: .leading, spacing: 0) {
                BandHeader("Parts")
                let parts = score?.versions.last?.parts ?? []
                if parts.isEmpty {
                    Text("No parts recorded for this version.")
                        .typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                        .padding(Theme.Metric.s20)
                } else {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        ScreenRow(title: part.name,
                                  value: [part.instrument,
                                          part.range?.joined(separator: "–")]
                                      .compactMap { $0 }.joined(separator: " · "),
                                  leads: false,
                                  identifier: "part-\(part.name)") {}
                    }
                }
            }
            .padding(.bottom, Theme.Metric.s32)
        }
    }

    private var score: ScoreDoc? { state.manifest?.scores.first { $0.slug == slug } }
    private var name: String? {
        score.map { ScoreTitle.arrangementName(title: $0.title, name: $0.name,
                                               slug: $0.slug) }
    }
}


/// An arrangement's details.
///
/// It takes the slug once and keeps the ScoreDoc it found. The slug is
/// editable inside, so a screen that re-resolved by slug would tear itself
/// down mid-edit -- `ScoreInfoView` already follows the move on its own.
struct DetailsScreen: View {
    @EnvironmentObject var state: AppState
    let slug: String
    var onBack: () -> Void

    @State private var opened: ScoreDoc?

    var body: some View {
        Group {
            if let score = opened {
                Screen(title: "Details", backLabel: "Back",
                       subtitle: ScoreTitle.arrangementName(title: score.title,
                                                            name: score.name,
                                                            slug: score.slug),
                       onBack: onBack) {
                    ScoreInfoView(score: score)
                }
            } else {
                Color.clear
            }
        }
        .onAppear {
            if opened == nil {
                opened = state.manifest?.scores.first { $0.slug == slug }
            }
        }
    }
}
