import SwiftUI
import UniformTypeIdentifiers

/// Score-first (§7, §8): the score is the permanent ground, the library and chat
/// slide over it, and every canvas control lives in one pill. There is no
/// navigation bar, no title bar and no split view — losing `NavigationSplitView`
/// is the largest change in the revamp.
struct ContentView: View {
    /// Leaving the score. The score view is presented OVER the tab bar and X is
    /// how you leave it (NAVIGATION_SYSTEM.md §3); the tabs own where "back"
    /// goes, so this only reports that it happened.
    var onClose: () -> Void = {}

    @EnvironmentObject var state: AppState
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The two overlays, which replace the split view's columns.

    /// Off by default and named a preview (§9.2): a transport that does nothing
    /// teaches people the app is broken. Previous and next step the setlist and
    /// work whether or not this is on.
    @AppStorage("showTransport") private var showTransport = false
    @State private var exportRequested = 0
    @State private var scoreScreen: ScoreScreen?
    @State private var optionsSection: String?
    @State private var chatOpen = false
    @State private var didSetInitialOverlays = false

    @State private var showSettings = false
    @State private var showImporter = false
    /// Piece rows are expanded by default; track only the collapsed ones.
    @State private var collapsedPieces: Set<String> = []
    @State private var collapsedSetlists: Set<String> = []
    /// Arrangements showing their version history.
    @State private var expandedArrangements: Set<String> = []
    /// Prompt groups showing their steps, keyed "<slug>/<group id>".
    @State private var expandedVersionGroups: Set<String> = []
    @State private var infoScore: ScoreDoc?
    @State private var importTargetPiece: String?
    /// Every dialog goes through one request, so they cannot disagree.
    @State private var newPieceName = ""
    @State private var newSetlistName = ""
    /// An arrangement that should go into the setlist about to be created.
    @State private var setlistSeedScore: String?
    /// The setlist whose arrangement picker is open.
    @State private var setlistPicker: SetlistDoc?
    /// The arrangement being put into a set list from its own row.
    @State private var setlistChooserScore: ScoreDoc?

    static let scoreTypes: [UTType] = ([
        UTType(filenameExtension: "musicxml"),
        UTType(filenameExtension: "mxl"),
        UTType(filenameExtension: "xml"),
        UTType(filenameExtension: "mid"),
        UTType(filenameExtension: "midi"),
    ].compactMap { $0 }) + [.pdf]

    /// Build identity, read from the bundle so what is displayed is exactly the
    /// CFBundleVersion App Store Connect records.
    static let buildStamp: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let sha = (Bundle.main.url(forResource: "build-sha", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) })?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "v\(version) · b\(build)" + (sha.map { " · \($0)" } ?? "")
    }()

    private var isCompact: Bool { hSize == .compact }

    var body: some View {
        ZStack {
            scoreBody
            if let screen = scoreScreen { scoreScreenView(screen) }
        }
    }

    @ViewBuilder
    private func scoreScreenView(_ screen: ScoreScreen) -> some View {
        switch screen {
        case .options, .optionsSection:
            ScoreOptionsScreen(mode: $state.scoreMode,
                               showTransport: $showTransport,
                               section: optionsSection,
                               onBack: {
                                   if optionsSection != nil { optionsSection = nil }
                                   else { scoreScreen = nil }
                               },
                               push: { optionsSection = $0 },
                               onSettings: { scoreScreen = .settings },
                               onDetails: { scoreScreen = .details })
                .background(Theme.Surface.ground)
                .accessibilityIdentifier("score-options")
        case .details:
            if let score = state.selectedScore {
                Screen(title: "Details", backLabel: "Options",
                       subtitle: score.title ?? score.name,
                       onBack: { scoreScreen = .options }) {
                    ScoreInfoView(score: score)
                }
                .background(Theme.Surface.ground)
            }
        case .settings:
            Screen(title: "Settings", backLabel: "Options",
                   onBack: { scoreScreen = .options }) {
                SettingsView()
            }
            .background(Theme.Surface.ground)
        case .chatModel:
            ChatModelScreen(onBack: { scoreScreen = nil })
                .background(Theme.Surface.ground)
        }
    }

    private var scoreBody: some View {
        VStack(spacing: 0) {
            ScoreTopBar(annotation: state.annotation,
                        number: state.selectedScore
                            .flatMap { state.placement(of: $0.slug)?.number },
                        title: scoreTitle,
                        subtitle: scoreSubtitle,
                        mode: $state.scoreMode,
                        titleMenuOpen: $state.titleMenuOpen,
                        moreOpen: Binding(get: { scoreScreen != nil },
                                          set: { on in
                                              scoreScreen = on ? .options : nil
                                              if !on { optionsSection = nil }
                                          }),
                        chatOpen: chatOpen,
                        onClose: onClose,
                        onAsk: {
                            withAnimation(Theme.Motion.overlay(reduced: reduceMotion)) {
                                chatOpen.toggle()
                            }
                        })
            if state.titleMenuOpen, let score = state.selectedScore {
                TitleSwitcherBand(score: score,
                                  onPickArrangement: { slug in
                                      state.titleMenuOpen = false
                                      state.select(slug: slug)
                                  },
                                  onPickVersion: { version in
                                      state.titleMenuOpen = false
                                      state.pinnedVersion = version
                                      Task { await state.renderIfNeeded() }
                                  },
                                  onAllVersions: {
                                      state.titleMenuOpen = false
                                      optionsSection = "Versions"
                                      scoreScreen = .options
                                  })
            }
            ZStack(alignment: .top) {
                Theme.Surface.ground
                canvasLayer
                overlayLayer
                // The two menus the top bar opens. Plain children of the
                // canvas stack rather than an overlay on the whole view: as an
                // overlay they did not materialise at all, and a menu that
                // cannot be opened is worse than one that is in the wrong place.

            }
            .overlay(alignment: .topTrailing) {
                if state.selectedScore != nil {
                    PositionCounters(pages: pageCounter, bar: barCounter)
                        .padding(.top, Theme.Metric.s8)
                        .padding(.trailing, Theme.Metric.s12)
                        .allowsHitTesting(false)
                }
            }
            // Performance mode gives the score the whole screen: the strip and
            // the transport go, and the page-turn zones become the point (§4.5).
            if state.scoreMode != .performance, let document = state.pdfDocument {
                ThumbnailStrip(document: document,
                               current: state.visiblePageIndices,
                               spread: state.twoPageSpread,
                               // straight to the unit holding that page: no
                               // offset arithmetic left to get wrong
                               onJump: { index in
                                   state.pageIndex = PagedCanvas.index(
                                       forPage: index, spread: state.twoPageSpread)
                               })
                if showTransport {
                    Transport(setlistLabel: setlistLabel,
                              canStep: setlistPosition != nil,
                              onPrevious: { stepSetlist(-1) },
                              onNext: { stepSetlist(1) })
                }
            }
        }
        .background(Theme.Surface.ground)
        .onChange(of: state.annotation.isOn) { _, on in
            // the ink bar can be dismissed from its own control, and the mode
            // must follow it or the top bar would lie about the Pencil
            if on { state.scoreMode = .edit } else if state.scoreMode == .edit { state.scoreMode = .read }
        }
        .task {
            Theme.verifyFontsRegistered()
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: Self.scoreTypes) { result in
            let piece = importTargetPiece
            importTargetPiece = nil
            if case .success(let url) = result {
                state.receiveFile(at: url, intoPiece: piece)
            }
        }
        // Panel dialogs, not system ones: a sheet is 620 wide over a 34% dim and
        // an alert has a band footer whose verb names the action (§7.15, §7.16).

    }

    // MARK: - The setlist, which is what the transport steps

    private var setlistPosition: (setlist: SetlistDoc, index: Int)? {
        guard let slug = state.currentSetlist, let current = state.selectedSlug,
              let setlist = state.manifest?.setlists?.first(where: { $0.slug == slug }),
              let index = setlist.arrangements.firstIndex(of: current) else { return nil }
        return (setlist, index)
    }

    private var setlistLabel: String? {
        guard let position = setlistPosition else { return nil }
        return "setlist · \(position.index + 1) of \(position.setlist.arrangements.count)"
    }

    private func stepSetlist(_ delta: Int) {
        guard let position = setlistPosition else { return }
        let next = position.index + delta
        guard position.setlist.arrangements.indices.contains(next) else { return }
        state.select(slug: position.setlist.arrangements[next])
    }

    // MARK: - The two menus the top bar opens

            // MARK: - Identity, counters

    private var scoreTitle: String {
        guard let score = state.selectedScore else { return "No arrangement" }
        return score.title ?? score.name
    }

    private var scoreSubtitle: String {
        guard let score = state.selectedScore else { return "" }
        let piece = state.manifest?.pieces?.first { $0.arrangements.contains(score.slug) }
        return [piece?.name, state.displayedVersionID]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var pageCounter: String {
        ScorePosition.pageLabel(visible: state.visiblePageIndices,
                                total: state.pdfDocument?.pageCount ?? 0)
    }

    /// The bar on screen, from the geometry the selection layer already builds.
    private var barCounter: Int? {
        guard let geometry = state.geometry else { return nil }
        let measures = state.visiblePageIndices.flatMap { index in
            geometry.page(index)?.elements.compactMap { $0.address?.measure } ?? []
        }
        return ScorePosition.bar(measuresOnScreen: measures)
    }

    // The score view's dialogs are gone (NAV_MODAL_FREE_0.4.2 §2). Details
    // and Settings are pushed screens now, reached through the "…" screen; the
    // set-list pickers and the alerts belonged to the legacy overlay, which
    // went with it. Nothing floats over the score any more except the docked
    // chrome -- chat, ink bar, strip, transport -- which blocks nothing and
    // needs no dismissing.

    // MARK: - Canvas

    /// The score, inset so it stays centred in whatever gap the overlays leave.
    /// The inset animates; the page itself does not resize unless both overlays
    /// are open (§5).
    @ViewBuilder
    private var canvasLayer: some View {
        HStack(spacing: 0) {
            // reserve exactly the panels' widths, so what remains IS the canvas
            Group {
                if let score = state.selectedScore {
                    // No width cap. The spec pins the page at 520 (436 with both
                    // panels open), but those came from a 1180pt mockup; capping
                    // an iPad's 1032pt canvas to 544 left dead bands either side
                    // and made the scroll view itself too narrow, so zoom hit
                    // hard limits well inside the screen. The score gets the
                    // whole gap and ScorePagesView sizes the page from it.
                    scorePane(score)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity)
            Color.clear.frame(width: isCompact ? 0 : (chatOpen ? Theme.Metric.chatWidth : 0))
        }
        .animation(Theme.Motion.overlay(reduced: reduceMotion), value: chatOpen)
        // a finished lasso opens chat: the selection has to be visibly received,
        // not silently held
        .onChange(of: state.chatOpenRequest) { _, _ in
            withAnimation(Theme.Motion.overlay(reduced: reduceMotion)) { chatOpen = true }
        }
    }

    @ViewBuilder
    private func scorePane(_ score: ScoreDoc) -> some View {
        if let doc = state.pdfDocument, let vid = state.displayedVersionID {
            if isCompact {
                ScoreZoomView(document: doc)
            } else {
                ScorePagesView(document: doc, annotationKey: "\(score.slug)/\(vid)", mode: state.scoreMode)
            }
        } else if score.versions.isEmpty {
            // An arrangement with no versions has no version to display, so
            // renderIfNeeded returns at its guard and nothing is ever in
            // flight. Saying so beats a spinner that can never finish.
            StateView(systemImage: "questionmark.square.dashed",
                      title: "Nothing to show",
                      message: "This arrangement has no versions — nothing was ever "
                             + "written to it. That usually means an import stopped "
                             + "part way. You can delete it and import the score again.",
                      actionTitle: "Delete this arrangement",
                      // and step back out: what is on screen no longer exists,
                      // and the undo bar lives in the library behind this
                      action: {
                          state.deleteScore(slug: score.slug)
                          onClose()
                      })
        } else if state.loadingPDF {
            StateView(systemImage: "music.note.list", title: "Engraving…",
                      message: "Verovio is setting the page.")
        } else if let err = state.lastError {
            StateView(systemImage: "exclamationmark.triangle",
                      title: "Render failed", message: "The engine could not draw this version.",
                      mono: err)
        } else {
            StateView(systemImage: "music.note", title: "Opening…")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !state.libraryLoaded {
            // Still looking. Nothing here is known yet -- not whether there are
            // scores, and not whether the engine is reachable -- so neither
            // message below can be told the truth, and both were shown for a
            // moment at every launch.
            StateView(systemImage: "music.note.list",
                      title: "Opening your library…",
                      message: "")
                .accessibilityIdentifier("library-loading")
        } else if !state.engineOK && !state.useLocalEngine {
            StateView(systemImage: "bolt.horizontal.circle",
                      title: "Engine unreachable",
                      message: "Check the URL in Settings and that the engine is running on your Mac.",
                      mono: state.engineURLString,
                      actionTitle: "Settings") { showSettings = true }
        } else {
            StateView(systemImage: "music.quarternote.3",
                      title: "No arrangement open",
                      message: "Open the library to pick an arrangement, or import a score.",
                      actionTitle: "Open library") {
            }
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var overlayLayer: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            if chatOpen {
                OverlayPanel(edge: .trailing,
                             width: isCompact ? .infinity : Theme.Metric.chatWidth) {
                    chatPanel
                }
                .transition(panelTransition(.trailing))
            }
        }
        .animation(Theme.Motion.overlay(reduced: reduceMotion), value: chatOpen)
    }

    /// Reduce Motion swaps the slide for a cross-fade (§5, §9).
    private func panelTransition(_ edge: OverlayEdge) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .move(edge: edge == .leading ? .leading : .trailing)
    }

    @ViewBuilder
    private var chatPanel: some View {
        VStack(spacing: 0) {
            OverlayHeader(subject: {
                HStack(spacing: Theme.Metric.s6) {
                    if let slug = state.selectedScore?.slug,
                       let placement = state.placement(of: slug) {
                        NumeralBadge(number: placement.number, role: .numeralM)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(state.selectedScore?.name ?? "Chat")
                            .typeRole(.title)
                            .foregroundStyle(Theme.Ink.ink)
                            .lineLimit(1)
                        if let slug = state.selectedScore?.slug,
                           let placement = state.placement(of: slug) {
                            Text(placement.piece.name)
                                .typeRole(.meta)
                                .foregroundStyle(Theme.Ink.ink3)
                                .lineLimit(1)
                        }
                    }
                }
            }, trailing: {
                if let catalog = state.modelCatalog {
                    // The chat header's model Menu becomes a pushed screen
                    // (NAV_MODAL_FREE_0.4.2 §7.3): the last popover in the app.
                    Button { scoreScreen = .chatModel } label: {
                        Text(state.chatModel.isEmpty ? (catalog.default) : state.chatModel)
                            .typeRole(.data)
                            .foregroundStyle(Theme.Ink.ink2)
                            .padding(.vertical, Theme.Metric.s4)
                            .padding(.horizontal, Theme.Metric.s6)
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                                    .stroke(Theme.Line.line2, lineWidth: 1)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chat-model")
                    .accessibilityLabel("Chat model")
                }
            }, onDismiss: {
                withAnimation(Theme.Motion.overlay(reduced: reduceMotion)) { chatOpen = false }
            }, dismissLabel: "Close chat")
            ChatView()
        }
    }

    // The legacy library overlay lived here: piece and set-list sections,
    // drag-to-file rows and three context menus. It is gone (0.4.1 §1).
    // Browsing is the Library tab, filing is Edit mode's Move-to-piece,
    // and reordering is the arrangement sheet -- so nothing was left that
    // only the overlay could do. The score screen now has exactly one
    // chrome: top bar, thumbnail strip, transport.

    // MARK: - Pill

    /// Wrapped in a child view so the annotation controller can be observed:
    /// the pill shows markup state and the live ink colour.

    @ViewBuilder
    private var versionMenuItems: some View {
        if let score = state.selectedScore {
            ForEach(state.versionGroups(for: score)) { group in
                Button {
                    state.pinnedVersion = (group.face.id == score.latest) ? nil : group.face.id
                    Task { await state.renderIfNeeded() }
                } label: {
                    if group.face.id == state.displayedVersionID {
                        Label("\(group.face.id) · \(shortTitle(group.title))",
                              systemImage: "checkmark")
                    } else {
                        Text("\(group.face.id) · \(shortTitle(group.title))")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var optionsMenuItems: some View {
        Button { state.transpose(semitones: 1) } label: {
            Label("Transpose up a semitone", systemImage: "arrow.up")
        }
        Button { state.transpose(semitones: -1) } label: {
            Label("Transpose down a semitone", systemImage: "arrow.down")
        }
        Toggle("Use flats", isOn: Binding(
            get: { state.useFlats[state.selectedScore?.slug ?? "", default: true] },
            set: { newValue in
                if let slug = state.selectedScore?.slug { state.useFlats[slug] = newValue }
                state.respell(preferFlats: newValue)
            }))
        if !isCompact {
            Button {
                if let score = state.selectedScore, let vid = state.displayedVersionID {
                    DrawingStore.shared.clear(prefix: "\(score.slug)/\(vid)")
                    Task { await state.renderIfNeeded(force: true) }
                }
            } label: { Label("Clear markup", systemImage: "pencil.slash") }
        }
    }

    private func shortTitle(_ title: String) -> String {
        title.count > 40 ? title.prefix(40).trimmingCharacters(in: .whitespaces) + "…" : title
    }

    // MARK: - Navigation

    private func openScore(_ slug: String, version: String? = nil) {
        state.select(slug: slug, version: version)
        // one pane at a time on iPhone: opening a score reveals it
        if isCompact {
        }
    }
}
/// A row inside a piece is a drop target: what lands on it takes its place in
/// the running order and everything below shifts down, which is the #N
/// renumbering the user sees. A row in Unfiled has no order to join, so it
/// accepts nothing.
private extension View {
}

/// Observes the shared annotation controller so the pill reflects markup state
/// and carries the live ink colour.
// The pill is gone from the score view: the top bar carries its duties
// (NAVIGATION_SYSTEM.md §8), and with the legacy overlay removed there is
// nothing left for its library button to open.

