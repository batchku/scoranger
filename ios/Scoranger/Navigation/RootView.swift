import SwiftUI

/// The app's places (NAVIGATION_SYSTEM.md §3, §4C).
///
/// There is ONE place: My Library. Home is gone -- it was a lobby in front of
/// the library, holding a second search field, four large panels and two
/// "recent" sections of the same rows the library already lists -- and the tab
/// bar went with it, because one live tab and a disabled placeholder is not a
/// tab bar. A score opens OVER the library, full screen, and X always closes
/// back to it. It is not a place: it is a document you are in.
///
/// The score's own state -- page, zoom, selection, chat -- survives a close and
/// reopen within a session, because `AppState` outlives this view and the score
/// screen is only hidden, never rebuilt from nothing.
struct RootView: View {
    @EnvironmentObject var state: AppState

    /// The library's stack. The score view stays OUTSIDE it -- it is presented
    /// over the library, which is what lets its page, zoom and selection
    /// survive going back and returning.
    @State private var libraryPath: [Route] = []
    @State private var scoreOpen = false

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
    /// Settings is a panel docked at the trailing edge, not a screen that
    /// covers the library (#51). Anchored, non-blocking, nothing to dismiss
    /// but its own ✕ -- the same shape as the chat panel over the score.
    @State private var settingsOpen = false

    var body: some View {
        ZStack {
            Theme.Surface.ground.ignoresSafeArea()

            NavigationStack(path: $libraryPath) {
                library.navigationBarHidden(true)
                    .navigationDestination(for: Route.self) { screen($0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(scoreOpen ? 0 : 1)
            // hidden, not unloaded: coming back to the library should not cost
            // a rebuild, and the score is what is expensive to re-open
            .allowsHitTesting(!scoreOpen)

            if settingsOpen, !scoreOpen {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    OverlayPanel(edge: .trailing, width: Theme.Metric.settingsWidth) {
                        VStack(spacing: 0) {
                            OverlayHeader(subject: {
                                Text("Settings").typeRole(.title)
                                    .foregroundStyle(Theme.Ink.ink)
                            }, trailing: { EmptyView() }, onDismiss: {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    settingsOpen = false
                                }
                            }, dismissLabel: "Close settings")
                            ScrollView { SettingsView() }
                        }
                    }
                    .accessibilityIdentifier("settings-panel")
                    .transition(.move(edge: .trailing))
                }
                .ignoresSafeArea(edges: .bottom)
            }

            if let undo = state.undoableDelete, !scoreOpen {
                VStack {
                    Spacer()
                    UndoBar(what: undo.what,
                            onUndo: { state.restoreDeleted() },
                            onDismiss: {
                                state.undoableDelete = nil
                                Task { await state.sweepDeleted() }
                            })
                        .padding(.bottom, Theme.Metric.s20)
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
            // and clear pieces left holding nothing by a build that shipped
            // without the empty-piece rule. tidyPieces existed and worked and
            // was called from NOWHERE, so Ali's "Morrison's Jig -- 0
            // arrangements" survived every launch: the sweep that was supposed
            // to remove it never ran.
            await state.tidyPieces()
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
    private func screen(_ route: Route) -> some View {
        let pop = { _ = libraryPath.popLast() }
        let push: (Route) -> Void = { libraryPath.append($0) }
        // A route holds the slug it was pushed with, and an arrangement can be
        // MOVED to a new slug from the screen the route points at. Follow the
        // move rather than resolving to nothing.
        switch route.following(state.movedSlugs) {
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
            // picking a version MARKS it and stays on the list: this is the
            // history, and reading it means moving down it. The score opens on
            // whatever is marked when you go back to it -- and while reading,
            // the title band in the score is the faster way to switch.
            VersionsScreen(slug: slug, onBack: pop,
                           onShow: { version in
                               state.select(slug: slug, version: version)
                           })
                .navigationBarHidden(true)
        case .parts(let slug):
            PartsScreen(slug: slug, onBack: pop)
                .navigationBarHidden(true)
        case .details(let slug):
            // resolved ONCE, into a view that then follows its own edits: the
            // slug is editable on this screen, and re-resolving by slug on
            // every manifest tick closed the screen the instant a move landed
            DetailsScreen(slug: slug, onBack: pop)
                .navigationBarHidden(true)
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

    // MARK: - The place

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
                    onSettings: {
                        withAnimation(.easeOut(duration: 0.18)) { settingsOpen = true }
                    },
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
            libraryPath.append(.piece(slug))
        }
    }

    private func open(_ slug: String, version: String? = nil) {
        state.select(slug: slug, version: version)
        withAnimation(.easeOut(duration: 0.18)) { scoreOpen = true }
    }

    private func openSetlist(_ setlist: SetlistDoc) {
        state.currentSetlist = setlist.slug
        segment = .setlists
        if let first = setlist.arrangements.first { open(first) }
    }

    /// X always returns to the library, because there is nowhere else.
    private func close() {
        withAnimation(.easeOut(duration: 0.18)) { scoreOpen = false }
    }
}
