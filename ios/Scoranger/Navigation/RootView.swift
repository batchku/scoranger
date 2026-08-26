import SwiftUI

/// The app's places (NAVIGATION_SYSTEM.md §3).
///
/// Browsing and reading are separate now. A bottom tab bar holds Home and My
/// Library; a score opens OVER them, full screen, and X closes it back to
/// wherever it came from. It is not a third tab: it is a document you are in.
///
/// The score's own state -- page, zoom, selection, chat -- survives a close and
/// reopen within a session, because `AppState` outlives this view and the score
/// screen is only hidden, never rebuilt from nothing.
struct RootView: View {
    @EnvironmentObject var state: AppState

    @State private var tab: AppTab = .home
    @State private var scoreOpen = false
    /// Where the score was opened from, so X knows where to go back to (§3).
    @State private var cameFrom: AppTab = .home

    @State private var homeSearch = ""
    @State private var librarySearch = ""
    @State private var segment: LibrarySegment = .pieces
    @State private var sort: LibrarySort = .name
    @State private var filters: Set<LibraryFilter> = []
    @State private var editing = false

    @State private var pieceChoice: String?
    @State private var setlistPickerScore: ScoreDoc?
    @State private var arrangementPickerSetlist: SetlistDoc?
    @State private var detailsScore: ScoreDoc?
    @State private var renaming: (id: String, isPiece: Bool, isSetlist: Bool, draft: String)?
    @State private var deleting: LibraryRow?
    @State private var newName = ""
    @State private var creating: LibrarySegment?
    /// The old library manager, kept reachable until drag-to-file has its own
    /// home in Edit mode. Nothing is removed before its replacement exists.
    @State private var classicManager = false
    @State private var showSettings = false
    @State private var showImporter = false

    var body: some View {
        ZStack {
            Theme.Surface.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    switch tab {
                    case .home:    home
                    case .library: library
                    case .shared:  EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                TabBar(selection: $tab)
            }
            .opacity(scoreOpen ? 0 : 1)
            // hidden, not unloaded: coming back to the library should not cost
            // a rebuild, and the score is what is expensive to re-open
            .allowsHitTesting(!scoreOpen)

            if scoreOpen {
                ContentView(onClose: close)
                    .transition(.opacity)
            }
        }
        .task {
            Theme.verifyFontsRegistered()
            state.resetViewPreferencesForTesting()
            state.startPolling()
        }
        .overlay { pieceSheet }
        .overlay { managementSheets }
        .overlay {
            if showSettings {
                ZStack {
                    DialogScrim { showSettings = false }
                    PanelSheet(title: "Settings", onDone: { showSettings = false }) {
                        SettingsView()
                    }
                }
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: ContentView.scoreTypes) { result in
            if case .success(let url) = result { state.receiveFile(at: url) }
        }
    }

    /// Everything a row's menu can open.
    @ViewBuilder
    private var managementSheets: some View {
        if let setlist = arrangementPickerSetlist {
            ZStack {
                DialogScrim { arrangementPickerSetlist = nil }
                SetlistArrangementPicker(setlist: setlist) { arrangementPickerSetlist = nil }
            }
        }
        if let score = setlistPickerScore {
            ZStack {
                DialogScrim { setlistPickerScore = nil }
                SetlistPicker(score: score) { setlistPickerScore = nil }
            }
        }
        if let score = detailsScore {
            ZStack {
                DialogScrim { detailsScore = nil }
                PanelSheet(title: score.name,
                           number: state.placement(of: score.slug)?.number,
                           onDone: { detailsScore = nil }) {
                    ScoreInfoView(score: score)
                }
            }
        }
        if let renaming {
            PanelAlert(title: "Rename",
                       message: "A new name for \(renaming.draft).",
                       field: Binding(get: { self.renaming?.draft ?? "" },
                                      set: { self.renaming?.draft = $0 }),
                       verb: "Rename",
                       onCancel: { self.renaming = nil },
                       onConfirm: { commitRename() })
        }
        if let deleting {
            PanelAlert(title: "Delete \(deleting.title)?",
                       message: "This cannot be undone.",
                       verb: "Delete",
                       isDestructive: true,
                       onCancel: { self.deleting = nil },
                       onConfirm: { commitDelete(deleting) })
        }
        if let creating {
            PanelAlert(title: creating == .pieces ? "New piece" : "New set list",
                       message: "Give it a name.",
                       field: $newName,
                       verb: "Create",
                       onCancel: { self.creating = nil },
                       onConfirm: { commitCreate(creating) })
        }

    }

    private func commitRename() {
        guard let renaming else { return }
        let name = renaming.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        self.renaming = nil
        guard !name.isEmpty else { return }
        Task {
            if renaming.isSetlist {
                _ = await state.renameSetlist(setlist: renaming.id, name: name)
            } else if renaming.isPiece {
                _ = await state.renamePiece(piece: renaming.id, name: name)
            } else {
                _ = await state.renameScore(slug: renaming.id, name: name)
            }
        }
    }

    private func commitDelete(_ row: LibraryRow) {
        deleting = nil
        if segment == .setlists {
            Task { _ = await state.deleteSetlist(row.id) }
        } else if let piece = (state.manifest?.pieces ?? []).first(where: { $0.slug == row.id }) {
            // deleting a piece deletes its arrangements, which is what the
            // sidebar's menu did
            for slug in piece.arrangements { state.deleteScore(slug: slug) }
        } else {
            state.deleteScore(slug: row.id)
        }
    }

    private func commitCreate(_ segment: LibrarySegment) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        creating = nil
        guard !name.isEmpty else { return }
        Task {
            if segment == .setlists {
                _ = await state.createSetlist(name: name)
            } else {
                state.createPieceAndAssign(name: name, scoreSlug: "")
            }
        }
    }

    // MARK: - Places

    private var home: some View {
        HomeView(search: $homeSearch,
                 onOpen: openPieceOrArrangement,
                 onOpenSetlist: openSetlist,
                 onImport: { showImporter = true },
                 onNewArrangement: { tab = .library; segment = .pieces },
                 onNewSetlist: { tab = .library; segment = .setlists },
                 onAsk: askAboutLastScore,
                 onSettings: { showSettings = true },
                 onAllPieces: { tab = .library; segment = .pieces },
                 onAllSetlists: { tab = .library; segment = .setlists })
    }

    private var library: some View {
        LibraryView(segment: $segment, search: $librarySearch, sort: $sort,
                    filters: $filters, editing: $editing,
                    onOpenPiece: openPieceOrArrangement,
                    onOpenArrangement: { open($0) },
                    onOpenSetlist: openSetlist,
                    onAdd: { addForSegment() },
                    onRowAction: handle)
    }

    /// Choosing between the arrangements of a piece (§4.4). A piece is not
    /// openable; opening one means opening one of its arrangements.
    /// Choosing between the arrangements of a piece (§4.4), with their
    /// versions -- the sidebar's expandable rows, rehomed.
    @ViewBuilder
    private var pieceSheet: some View {
        if let slug = pieceChoice,
           let piece = (state.manifest?.pieces ?? []).first(where: { $0.slug == slug }) {
            ZStack {
                DialogScrim { pieceChoice = nil }
                ArrangementSheet(
                    piece: piece,
                    onOpen: { arrangement, version in
                        pieceChoice = nil
                        open(arrangement, version: version)
                    },
                    onNewArrangement: {
                        pieceChoice = nil
                        Task { _ = await state.createArrangement(pieceSlug: piece.slug) }
                    },
                    onImportArrangement: {
                        pieceChoice = nil
                        showImporter = true
                    },
                    onRenamePiece: {
                        pieceChoice = nil
                        renaming = (piece.slug, true, false, piece.name)
                    },
                    onDone: { pieceChoice = nil },
                    onArrangementAction: { score, action in
                        pieceChoice = nil
                        handle(LibraryRow(id: score.slug, title: score.title ?? score.name,
                                          subtitle: "", chips: [], meta: "",
                                          sortName: score.name, composer: "",
                                          changed: "", arrangementCount: 1),
                               action)
                    })
            }
        }
    }

    // MARK: - Row actions -- the sidebar's management, rehomed (§8)

    private func handle(_ row: LibraryRow, _ action: RowAction) {
        let score = state.manifest?.scores.first { $0.slug == row.id }
        switch action {
        case .open:
            open(row)
        case .versions:
            // a piece opens its arrangement sheet, which lists versions per
            // arrangement; a lone arrangement opens straight into its own
            if (state.manifest?.pieces ?? []).contains(where: { $0.slug == row.id }) {
                pieceChoice = row.id
            } else if let score { detailsScore = score }
        case .details:
            if let score { detailsScore = score }
            else if let piece = (state.manifest?.pieces ?? []).first(where: { $0.slug == row.id }),
                    let first = piece.arrangements.first {
                detailsScore = state.manifest?.scores.first { $0.slug == first }
            }
        case .addToSetlist:
            // from a SET LIST, pick its arrangements; from an arrangement, pick
            // its set lists -- two directions, two questions
            if segment == .setlists,
               let setlist = (state.manifest?.setlists ?? []).first(where: { $0.slug == row.id }) {
                arrangementPickerSetlist = setlist
            } else if let score { setlistPickerScore = score }
            else if let piece = (state.manifest?.pieces ?? []).first(where: { $0.slug == row.id }),
                    let first = piece.arrangements.first {
                setlistPickerScore = state.manifest?.scores.first { $0.slug == first }
            }
        case .rename:
            renaming = (row.id,
                        (state.manifest?.pieces ?? []).contains { $0.slug == row.id },
                        segment == .setlists,
                        row.title)
        case .delete:
            deleting = row
        case .newArrangement:
            Task { _ = await state.createArrangement(pieceSlug: row.id) }
        }
    }

    private func open(_ row: LibraryRow) {
        if segment == .setlists,
           let setlist = (state.manifest?.setlists ?? []).first(where: { $0.slug == row.id }) {
            openSetlist(setlist)
        } else {
            openPieceOrArrangement(row.id)
        }
    }

    private func addForSegment() {
        creating = segment
        newName = ""
    }

    // MARK: - Transitions

    private func openPieceOrArrangement(_ slug: String) {
        guard let piece = (state.manifest?.pieces ?? []).first(where: { $0.slug == slug }) else {
            open(slug)
            return
        }
        // one arrangement opens straight away; several put the choice on screen
        if piece.arrangements.count == 1, let only = piece.arrangements.first {
            open(only)
        } else {
            pieceChoice = slug
        }
    }

    private func open(_ slug: String, version: String? = nil) {
        cameFrom = tab
        state.select(slug: slug, version: version)
        withAnimation(.easeOut(duration: 0.18)) { scoreOpen = true }
    }

    private func openSetlist(_ setlist: SetlistDoc) {
        RecentSetlists.opened(setlist.slug)
        state.currentSetlist = setlist.slug
        tab = .library
        segment = .setlists
        if let first = setlist.arrangements.first { open(first) }
    }

    /// Home's "Ask Scoranger": pick up the last arrangement and open chat on it.
    private func askAboutLastScore() {
        guard let slug = state.selectedSlug ?? state.manifest?.scores.first?.slug else { return }
        open(slug)
        state.chatOpenRequest += 1
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.18)) { scoreOpen = false }
        tab = cameFrom
    }
}
