import SwiftUI

// The library's panel states (design/DESIGN_SYSTEM.md §7.2, L3, L4, L6, L11,
// P1, S1). Each is what a tool-row button or a row's action opens beside the
// page, headed by its name, closed with Done.

/// L3 · Sort. Five orders as items, the current one tinted.
struct SortPanel: View {
    @Binding var sort: LibrarySort
    @Environment(\.panelDone) private var done

    var body: some View {
        Screen(title: "Sort", backLabel: "Back", onBack: { done?() }) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(LibrarySort.allCases, id: \.self) { option in
                    ScreenRow(title: option.label, leads: false,
                              isSelected: sort == option,
                              identifier: "sort-\(option.rawValue)") { sort = option }
                }
                PanelNote(text: "Name sorts by the piece's name and shows the alphabet at the side.")
                    .padding(.horizontal, Theme.Metric.panelSide)
                    .padding(.top, Theme.Metric.s8)
            }
            .padding(.vertical, Theme.Metric.s8)
        }
    }
}

/// L4 · Filter. Five groups from the data model [C9]: capsules with counts,
/// several at once; the Filter button carries how many are on.
struct FilterPanel: View {
    @Binding var filters: Set<LibraryFilter>
    var groups: [LibraryModel.FilterGroup] = []
    @Environment(\.panelDone) private var done

    var body: some View {
        Screen(title: "Filter", backLabel: "Back",
               subtitle: filters.isEmpty ? nil : "\(filters.count) on", onBack: { done?() }) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    PanelLabel(text: group.group.title, ruled: index > 0)
                    ForEach(group.options, id: \.filter) { option in
                        ScreenRow(title: option.filter.label,
                                  value: "\(option.count)",
                                  leads: false,
                                  isSelected: filters.contains(option.filter),
                                  identifier: option.filter.identifier) {
                            if filters.contains(option.filter) { filters.remove(option.filter) }
                            else { filters.insert(option.filter) }
                        }
                    }
                }
                if !filters.isEmpty {
                    PanelButtons {
                        PanelButton(title: "Clear filters", identifier: "filter-clear") {
                            filters = []
                        }
                    }
                }
                PanelNote(text: "Instruments come from each arrangement's parts; a scan that has not been converted matches none.")
                    .padding(.horizontal, Theme.Metric.panelSide)
                    .padding(.top, Theme.Metric.s8)
            }
            .padding(.vertical, Theme.Metric.s8)
        }
    }
}

/// The ways to bring a score in (L10's three ways, and a book), as items
/// with the sentence under each as a note.
struct ImportPanel: View {
    var run: (LibraryQuickAction) -> Void
    @Environment(\.panelDone) private var done

    var body: some View {
        Screen(title: "Import", backLabel: "Back", onBack: { done?() }) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(LibraryQuickAction.imports) { action in
                    ScreenRow(title: action.bandTitle, leads: false,
                              identifier: action.identifier) {
                        done?()
                        run(action)
                    }
                    Text(action.bandSubtitle).typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Metric.panelSide + Theme.Metric.s16)
                        .padding(.bottom, Theme.Metric.s8)
                }
            }
            .padding(.vertical, Theme.Metric.s8)
        }
    }
}

/// New: a piece or a set list. Either names itself in place on the page.
struct NewPanel: View {
    var run: (LibraryQuickAction) -> Void
    @Environment(\.panelDone) private var done

    var body: some View {
        Screen(title: "New", backLabel: "Back", onBack: { done?() }) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(LibraryQuickAction.creations) { action in
                    ScreenRow(title: action == .new ? "Piece" : "Set list", leads: false,
                              identifier: action.identifier) {
                        done?()
                        run(action)
                    }
                    Text(action == .new ? "A piece holds its arrangements, numbered."
                                        : "A running order you can play from the top and share.")
                        .typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Metric.panelSide + Theme.Metric.s16)
                        .padding(.bottom, Theme.Metric.s8)
                }
            }
            .padding(.vertical, Theme.Metric.s8)
        }
    }
}

/// L6 · A piece's arrangements beside its row, each with its own Open, so
/// the common path -- open #2 -- is two taps and no screen change. The full
/// piece screen is the last item.
struct PieceArrangementsPanel: View {
    @EnvironmentObject var state: AppState
    let slug: String
    var onOpen: (String) -> Void
    var onPieceScreen: () -> Void
    var onImport: (String) -> Void
    @Environment(\.panelDone) private var done

    private var piece: PieceDoc? { (state.manifest?.pieces ?? []).first { $0.slug == slug } }

    var body: some View {
        Screen(title: piece?.name ?? "Arrangements", backLabel: "Back",
               subtitle: piece?.composer, onBack: { done?() }) {
            VStack(alignment: .leading, spacing: 0) {
                PanelLabel(text: "Arrangements", ruled: false)
                ForEach(Array((piece?.arrangements ?? []).enumerated()), id: \.offset) { index, arrangement in
                    if let score = state.manifest?.scores.first(where: { $0.slug == arrangement }) {
                        arrangementRow(score, number: index + 1)
                    }
                }
                PanelLabel(text: "This piece")
                ScreenRow(title: "New arrangement", leads: false,
                          identifier: "piece-new-arrangement-\(slug)") {
                    Task { _ = await state.createArrangement(pieceSlug: slug) }
                }
                ScreenRow(title: "Import into this piece", leads: false,
                          identifier: "piece-import-\(slug)") { onImport(slug) }
                ScreenRow(title: "Piece screen", identifier: "piece-screen-\(slug)") {
                    onPieceScreen()
                }
            }
            .padding(.vertical, Theme.Metric.s8)
        }
    }

    private func arrangementRow(_ score: ScoreDoc, number: Int) -> some View {
        HStack(spacing: Theme.Metric.s12) {
            NumeralBadge(number: number, role: .numeralM)
            VStack(alignment: .leading, spacing: 2) {
                Text(ScoreTitle.arrangementName(title: score.title, name: score.name, slug: score.slug))
                    .typeRole(.row).foregroundStyle(Theme.Ink.ink).lineLimit(1)
                Text(meta(score)).typeRole(.data).foregroundStyle(Theme.Ink.ink3).lineLimit(1)
            }
            Spacer(minLength: Theme.Metric.s8)
            PanelButton(title: "Open", identifier: "arrangement-choice-\(score.slug)") {
                onOpen(score.slug)
            }
        }
        .padding(.horizontal, Theme.Metric.panelSide)
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) { Theme.Rule().padding(.horizontal, Theme.Metric.panelSide) }
    }

    private func meta(_ score: ScoreDoc) -> String {
        let parts = score.versions.last?.parts?.count ?? 0
        var bits = [score.versions.last?.name ?? ""]
        bits.append("\(parts) part" + (parts == 1 ? "" : "s"))
        let lists = (state.manifest?.setlists ?? []).filter { $0.arrangements.contains(score.slug) }
        if let first = lists.first { bits.append("in \(first.name)") }
        return bits.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// P1 · This piece: the panel at rest on the piece screen. Details as
/// editable fields, the sources, and Delete last under Careful.
struct ThisPiecePanel: View {
    @EnvironmentObject var state: AppState
    let slug: String
    var onImport: (String) -> Void
    var onDeleted: () -> Void
    @State private var confirmingDelete = false
    @Environment(\.panelDone) private var done

    private var piece: PieceDoc? { (state.manifest?.pieces ?? []).first { $0.slug == slug } }

    var body: some View {
        if let piece {
            Screen(title: "This piece", backLabel: "Back", onBack: { done?() }) {
                VStack(alignment: .leading, spacing: 0) {
                    PieceField(label: "Composer", value: piece.composer ?? "",
                               identifier: "piece-composer") { v in
                        Task { _ = await state.setPieceMetadata(piece.slug, composer: v) }
                    }
                    Theme.Rule().padding(.horizontal, Theme.Metric.panelSide)
                    PieceField(label: "Arranger", value: piece.arranger ?? "",
                               identifier: "piece-arranger") { v in
                        Task { _ = await state.setPieceMetadata(piece.slug, arranger: v) }
                    }
                    Theme.Rule().padding(.horizontal, Theme.Metric.panelSide)
                    PieceField(label: "Tags", value: (piece.tags ?? []).joined(separator: ", "),
                               hint: "chanson, waltz", identifier: "piece-tags") { v in
                        let tags = v.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        Task { _ = await state.setPieceMetadata(piece.slug, tags: tags) }
                    }

                    PanelLabel(text: "Sources")
                    Text(sourceSummary(piece)).typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                        .padding(.horizontal, Theme.Metric.panelSide)
                        .padding(.bottom, Theme.Metric.s8)
                    ScreenRow(title: "Import into this piece", leads: false,
                              identifier: "piece-import-\(piece.slug)") { onImport(piece.slug) }
                    ScreenRow(title: "New arrangement", leads: false,
                              identifier: "piece-new-arrangement-\(piece.slug)") {
                        Task { _ = await state.createArrangement(pieceSlug: piece.slug) }
                    }

                    PanelLabel(text: "Careful")
                    if confirmingDelete {
                        ConfirmDeleteStrip(what: deleteQuestion(piece),
                                           consequence: "Its arrangements and every version of them go with it.",
                                           identifier: "confirm-delete-\(piece.slug)",
                                           onDelete: {
                                               confirmingDelete = false
                                               state.deletePiece(piece.slug)
                                               done?()
                                               onDeleted()
                                           },
                                           onKeep: { confirmingDelete = false })
                    } else {
                        ScreenRow(title: "Delete piece", leads: false, isDestructive: true,
                                  identifier: "piece-delete-\(piece.slug)") {
                            confirmingDelete = true
                        }
                    }
                }
                .padding(.vertical, Theme.Metric.s8)
                .padding(.bottom, Theme.Metric.s32)
            }
        } else {
            Color.clear
        }
    }

    private func deleteQuestion(_ piece: PieceDoc) -> String {
        let n = piece.arrangements.count
        return n == 0 ? "Delete \(piece.name)?"
            : "Delete \(piece.name) and its \(n) arrangement\(n == 1 ? "" : "s")?"
    }

    private func sourceSummary(_ piece: PieceDoc) -> String {
        let count = piece.arrangements.compactMap { slug in
            state.manifest?.scores.first { $0.slug == slug }?.sources?.count
        }.reduce(0, +)
        return count == 0 ? "No other editions imported."
                          : "\(count) read-only source\(count == 1 ? "" : "s")."
    }
}

/// S1 · This set list: the panel at rest on the set list screen. Add, Share,
/// People when it is shared, and Delete (or Delete for everybody, or Leave)
/// last under Careful, confirming inline.
struct ThisSetlistPanel: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var shared: SharedSetlists
    @EnvironmentObject var signIn: SignIn
    let slug: String
    var push: (Route) -> Void
    var onShare: () -> Void
    var onRemoved: () -> Void
    @State private var confirmingRemoval = false
    @Environment(\.panelDone) private var done

    private var setlist: SetlistDoc? { state.manifest?.setlists?.first { $0.slug == slug } }

    var body: some View {
        if let setlist {
            Screen(title: "This set list", backLabel: "Back",
                   subtitle: summary(setlist), onBack: { done?() }) {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenRow(title: "Add",
                              identifier: "setlist-add-\(slug)") { push(.addArrangements(slug)) }
                    ScreenRow(title: setlist.isShared ? "Shared" : "Share",
                              value: setlist.isShared ? "with a link" : nil,
                              leads: false, identifier: "setlist-share-\(slug)") { onShare() }
                    if setlist.isShared, let shareId = setlist.shareId {
                        ScreenRow(title: "People", identifier: "setlist-people-\(slug)") {
                            push(.sharedSetlist(shareId))
                        }
                    }
                    PanelLabel(text: "Careful")
                    removal(for: setlist)
                }
                .padding(.vertical, Theme.Metric.s8)
                .padding(.bottom, Theme.Metric.s32)
            }
        } else {
            Color.clear
        }
    }

    private func summary(_ setlist: SetlistDoc) -> String {
        let n = setlist.arrangements.count
        return "\(n) arrangement\(n == 1 ? "" : "s")" + (setlist.isShared ? " · shared" : "")
    }

    @ViewBuilder
    private func removal(for setlist: SetlistDoc) -> some View {
        let mine = setlist.ownerUid == nil || setlist.ownerUid == signIn.account?.uid
        let title: String = {
            if !setlist.isShared { return "Delete" }
            return mine ? "Delete for everybody" : "Leave this set list"
        }()
        if confirmingRemoval {
            ConfirmDeleteStrip(
                what: "\(title)?",
                consequence: !setlist.isShared
                    ? "The running order goes; the arrangements stay in the library."
                    : (mine ? "Everybody's copy of the running order and markup goes too. Nobody else can do this."
                            : "It leaves your library; the others keep theirs."),
                verb: mine ? "Delete" : "Leave",
                identifier: "setlist-remove-\(slug)",
                onDelete: { confirmingRemoval = false; remove(setlist, mine: mine) },
                onKeep: { confirmingRemoval = false })
        } else {
            ScreenRow(title: title, leads: false, isDestructive: true,
                      identifier: "setlist-remove-\(slug)") { confirmingRemoval = true }
        }
    }

    private func remove(_ setlist: SetlistDoc, mine: Bool) {
        Task {
            let finished: Bool
            if !setlist.isShared {
                finished = await state.deleteSetlist(slug)
            } else if mine {
                guard let shareId = setlist.shareId else { return }
                do {
                    let remote = try await shared.fetch(shareId)
                    finished = await state.deleteSharedSetlistEverywhere(setlist, shared: shared, remote: remote)
                } catch {
                    state.report("delete that set list", error); return
                }
            } else {
                guard let uid = signIn.account?.uid else {
                    state.notice = "Sign in to leave a shared set list."; return
                }
                finished = await state.leaveSharedSetlist(setlist, shared: shared, uid: uid)
            }
            if finished { done?(); onRemoved() }
        }
    }
}
