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
    /// One stack per tab (§8.6). The score view stays OUTSIDE them -- it is
    /// presented over the tabs, which is what lets its page, zoom and selection
    /// survive going back to the library and returning.
    @State private var homePath: [Route] = []
    @State private var libraryPath: [Route] = []
    @State private var scoreOpen = false
    /// Where the score was opened from, so X knows where to go back to (§3).
    @State private var cameFrom: AppTab = .home

    @State private var homeSearch = ""
    @State private var librarySearch = ""
    @State private var segment: LibrarySegment = .pieces
    @State private var sort: LibrarySort = .name
    @State private var filters: Set<LibraryFilter> = []
    @State private var editing = false

    /// Whether the piece being named is the destination of an import.
    /// Where an import should land, asked BEFORE the file picker (0.4.1 item 9).
    @State private var importDestination: ImportDestination?
    @State private var importIntoPiece: String?
    @State private var showSettings = false
    @State private var showImporter = false

    var body: some View {
        ZStack {
            Theme.Surface.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    switch tab {
                    case .home:
                        NavigationStack(path: $homePath) {
                            home.navigationBarHidden(true)
                                .navigationDestination(for: Route.self) { screen($0, in: .home) }
                        }
                    case .library:
                        NavigationStack(path: $libraryPath) {
                            library.navigationBarHidden(true)
                                .navigationDestination(for: Route.self) { screen($0, in: .library) }
                        }
                    case .shared:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                TabBar(selection: $tab)
            }
            .opacity(scoreOpen ? 0 : 1)
            // hidden, not unloaded: coming back to the library should not cost
            // a rebuild, and the score is what is expensive to re-open
            .allowsHitTesting(!scoreOpen)

            if let undo = state.undoableDelete, !scoreOpen {
                VStack {
                    Spacer()
                    UndoBar(what: undo.what,
                            onUndo: { state.restoreDeleted() },
                            onDismiss: {
                                state.undoableDelete = nil
                                Task { await state.sweepDeleted() }
                            })
                        .padding(.bottom, Theme.Metric.tabBarHeight)
                }
            }

            if scoreOpen {
                ContentView(onClose: close)
                    .transition(.opacity)
            }
        }
        .task {
            // reclaim anything whose undo window passed while the app was shut
            await state.sweepDeleted()
            Theme.verifyFontsRegistered()
            state.resetViewPreferencesForTesting()
            state.startPolling()
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: ContentView.scoreTypes) { result in
            let piece = importIntoPiece
            importIntoPiece = nil
            if case .success(let url) = result {
                state.receiveFile(at: url, intoPiece: piece)
                tab = .library
                segment = .pieces
            }
        }
    }

    /// Deleting knows what it is deleting: a set list is unmade, a piece takes
    /// its arrangements with it, an arrangement goes on its own.
    private func commitDelete(_ row: LibraryRow) {
        if segment == .setlists {
            Task { _ = await state.deleteSetlist(row.id) }
        } else if (state.manifest?.pieces ?? []).contains(where: { $0.slug == row.id }) {
            state.deletePiece(row.id)
        } else {
            state.deleteScore(slug: row.id)
        }
    }

    /// What a route shows.
    @ViewBuilder
    private func screen(_ route: Route, in tab: AppTab) -> some View {
        let pop = { if tab == .home { _ = homePath.popLast() } else { _ = libraryPath.popLast() } }
        let push: (Route) -> Void = { r in
            if tab == .home { homePath.append(r) } else { libraryPath.append(r) }
        }
        switch route {
        case .piece(let slug):
            if let piece = (state.manifest?.pieces ?? []).first(where: { $0.slug == slug }) {
                PieceScreen(piece: piece, onBack: pop,
                            onOpen: { open($0) }, push: push,
                            onImport: { pieceSlug in
                                importIntoPiece = pieceSlug
                                showImporter = true
                            })
                    .navigationBarHidden(true)
                    .accessibilityIdentifier("screen-piece-\(slug)")
            }
        case .arrangement(let slug):
            if let score = state.manifest?.scores.first(where: { $0.slug == slug }) {
                ArrangementScreen(score: score, onBack: pop,
                                  onOpen: { open(slug) }, push: push)
                    .navigationBarHidden(true)
                    .accessibilityIdentifier("screen-arrangement-\(slug)")
            }
        case .moveToPiece(let slugs):
            MoveToPieceScreen(moving: slugs, onBack: pop)
                .navigationBarHidden(true)
        case .setlistsFor(let slug):
            SetlistsForScreen(slug: slug, onBack: pop)
                .navigationBarHidden(true)
        case .setlist(let slug):
            SetlistScreen(slug: slug, onBack: pop,
                          onOpen: { member in
                              if let setlist = state.manifest?.setlists?
                                  .first(where: { $0.slug == slug }) {
                                  RecentSetlists.opened(setlist.slug)
                                  state.currentSetlist = setlist.slug
                              }
                              open(member)
                          },
                          push: push)
                .navigationBarHidden(true)
                .accessibilityIdentifier("screen-setlist-\(slug)")
        case .addArrangements(let slug):
            AddArrangementsScreen(slug: slug, onBack: pop)
                .navigationBarHidden(true)
        case .versions(let slug):
            VersionsScreen(slug: slug, onBack: pop,
                           onShow: { version in
                               state.select(slug: slug, version: version)
                               open(slug, version: version)
                           })
                .navigationBarHidden(true)
        case .parts(let slug):
            PartsScreen(slug: slug, onBack: pop)
                .navigationBarHidden(true)
        case .details(let slug):
            if let score = state.manifest?.scores.first(where: { $0.slug == slug }) {
                Screen(title: "Details", backLabel: "Back",
                       subtitle: score.title ?? score.name, onBack: pop) {
                    ScoreInfoView(score: score)
                }
                .navigationBarHidden(true)
            }
        case .importDestination:
            ImportDestinationScreen(onBack: pop,
                                    onNewPiece: { name in
                                        Task {
                                            let slug = await state.createPiece(named: name)
                                            importIntoPiece = slug
                                            pop()
                                            showImporter = true
                                        }
                                    },
                                    onExisting: { pieceSlug in
                                        importIntoPiece = pieceSlug
                                        pop()
                                        showImporter = true
                                    })
                .navigationBarHidden(true)
        case .settings, .settingsSection:
            Screen(title: "Settings", backLabel: "My library", onBack: pop) {
                SettingsView()
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: - Places

    private var home: some View {
        HomeView(search: $homeSearch,
                 onOpen: openPieceOrArrangement,
                 onOpenSetlist: openSetlist,
                 onImport: { homePath.append(.importDestination) },
                 onNewArrangement: { tab = .library; segment = .pieces },
                 onNewSetlist: { tab = .library; segment = .setlists },
                 onAsk: askAboutLastScore,
                 onSettings: { homePath.append(.settings) },
                 onAllPieces: { tab = .library; segment = .pieces },
                 onAllSetlists: { tab = .library; segment = .setlists })
    }

    /// A new piece, or one that already exists.
    enum ImportDestination: Equatable { case choosing, newPiece, existing }

    /// Ask first, then pick the file.
    ///
    /// The old flow picked a file and then put the result wherever it landed --
    /// which was Unfiled, reachable only by scrolling past every piece, with an
    /// inbox badge on Home that was not tappable. Ali could not find what he
    /// had imported. Asking first means the answer to "where did it go?" is
    /// something the user chose.
    private func chooserRow(title: String, detail: String, id: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Metric.s8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                    if !detail.isEmpty {
                        Text(detail).typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Ink.ink3)
            }
            .padding(.horizontal, Theme.Metric.panelPadding)
            .padding(.vertical, Theme.Metric.sheetRowVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(id)
    }

    private var library: some View {
        LibraryView(segment: $segment, search: $librarySearch, sort: $sort,
                    filters: $filters, editing: $editing,
                    onOpenPiece: openPieceOrArrangement,
                    onOpenArrangement: { open($0) },
                    onOpenSetlist: openSetlist,
                    onRowMenu: { row in
                        // A piece opens its own screen; an unfiled arrangement
                        // opens the arrangement screen (§3.5's rule: both need
                        // a target list, so both push).
                        if (state.manifest?.pieces ?? []).contains(where: { $0.slug == row.id }) {
                            libraryPath.append(.piece(row.id))
                        } else if segment == .setlists {
                            libraryPath.append(.setlist(row.id))
                        } else {
                            libraryPath.append(.arrangement(row.id))
                        }
                    },
                    onCreate: { name in
                        Task {
                            if segment == .setlists {
                                // a set list with nothing in it is not worth
                                // making, so naming one leads straight to
                                // choosing what goes in it
                                if let slug = await state.createSetlist(name: name) {
                                    libraryPath.append(.addArrangements(slug))
                                }
                            } else {
                                _ = await state.createPiece(named: name)
                            }
                        }
                    },
                    onImport: { libraryPath.append(.importDestination) },
                    onRowAction: handle,
                    onBarAction: handleBar)
    }

    /// Choosing between the arrangements of a piece (§4.4). A piece is not
    /// openable; opening one means opening one of its arrangements.
    /// Choosing between the arrangements of a piece (§4.4), with their
    /// versions -- the sidebar's expandable rows, rehomed.
    // MARK: - Row actions -- the sidebar's management, rehomed (§8)

    /// The Edit-mode action bar (§2.2), over whatever is highlighted.
    private func handleBar(_ action: LibraryAction, _ ids: Set<String>,
                           _ kind: LibrarySelectionKind) {
        let scores = ids.compactMap { id in state.manifest?.scores.first { $0.slug == id } }
        switch action {
        case .newArrangement:
            guard let id = ids.first else { return }
            Task { _ = await state.createArrangement(pieceSlug: id) }
        case .moveToPiece:
            libraryPath.append(.moveToPiece(scores.map(\.slug)))
        case .addToSetlist:
            if let first = scores.first { libraryPath.append(.setlistsFor(first.slug)) }
        case .duplicate:
            Task { for score in scores { _ = await state.duplicateScore(slug: score.slug) } }
        case .delete:
            // the undo bar is the confirmation: the row goes at once and comes
            // back for as long as the engine still holds it
            for id in ids {
                switch kind {
                case .setlists: Task { _ = await state.deleteSetlist(id) }
                case .pieces:   state.deletePiece(id)
                default:        state.deleteScore(slug: id)
                }
            }
            editing = false
        }
    }

    /// Every row currently in the library, for the bar to name what it is
    /// acting on.
    private var libraryRows: [LibraryRow] {
        guard let manifest = state.manifest else { return [] }
        return segment == .pieces
            ? LibraryModel.pieceRows(manifest: manifest)
                + LibraryModel.unfiledRows(manifest: manifest)
            : LibraryModel.setlistRows(manifest: manifest)
    }

    private func handle(_ row: LibraryRow, _ action: RowAction) {
        let score = state.manifest?.scores.first { $0.slug == row.id }
        switch action {
        case .open:
            open(row)
        case .versions:
            // a piece opens its own screen, which lists its arrangements;
            // a lone arrangement opens its versions directly
            if (state.manifest?.pieces ?? []).contains(where: { $0.slug == row.id }) {
                libraryPath.append(.piece(row.id))
            } else {
                libraryPath.append(.versions(row.id))
            }
        case .details:
            if score != nil {
                libraryPath.append(.details(row.id))
            } else if let piece = (state.manifest?.pieces ?? []).first(where: { $0.slug == row.id }),
                      let first = piece.arrangements.first {
                libraryPath.append(.details(first))
            }
        case .addToSetlist:
            // from a SET LIST, pick its arrangements; from an arrangement, pick
            // its set lists -- two directions, two questions
            if segment == .setlists {
                libraryPath.append(.addArrangements(row.id))
            } else if score != nil {
                libraryPath.append(.setlistsFor(row.id))
            } else if let piece = (state.manifest?.pieces ?? []).first(where: { $0.slug == row.id }),
                      let first = piece.arrangements.first {
                libraryPath.append(.setlistsFor(first))
            }
        case .delete:
            commitDelete(row)
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
            // A piece with several arrangements PUSHES its screen (§4). It
            // used to open a sheet; the sheet is gone, and for a while this
            // set a flag nothing rendered -- so tapping such a piece did
            // nothing at all.
            if tab == .home { homePath.append(.piece(slug)) }
            else { libraryPath.append(.piece(slug)) }
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
