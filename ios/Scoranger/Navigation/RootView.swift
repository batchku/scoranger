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
                    onAdd: { showImporter = true })
    }

    /// Choosing between the arrangements of a piece (§4.4). A piece is not
    /// openable; opening one means opening one of its arrangements.
    @ViewBuilder
    private var pieceSheet: some View {
        if let slug = pieceChoice,
           let piece = (state.manifest?.pieces ?? []).first(where: { $0.slug == slug }) {
            ZStack {
                DialogScrim { pieceChoice = nil }
                PanelSheet(title: piece.name, onDone: { pieceChoice = nil }) {
                    VStack(alignment: .leading, spacing: 0) {
                    BandHeader("Arrangements")
                    ForEach(Array(piece.arrangements.enumerated()), id: \.offset) { index, arr in
                        if let score = state.manifest?.scores.first(where: { $0.slug == arr }) {
                            Button {
                                pieceChoice = nil
                                open(arr)
                            } label: {
                                HStack(spacing: Theme.Metric.s12) {
                                    NumeralBadge(number: index + 1)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(score.title ?? score.name)
                                            .typeRole(.titleS).foregroundStyle(Theme.Ink.ink)
                                        Text("\(score.versions.count) versions")
                                            .typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, Theme.Metric.panelPadding)
                                .padding(.vertical, Theme.Metric.sheetRowVertical)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("arrangement-choice-\(arr)")
                        }
                    }
                    }
                }
            }
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
            pieceChoice = slug
        }
    }

    private func open(_ slug: String) {
        cameFrom = tab
        state.select(slug: slug)
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
