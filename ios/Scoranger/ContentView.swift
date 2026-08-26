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
    @State private var alertRequest: AlertRequest?
    @State private var newPieceName = ""
    @State private var newSetlistName = ""
    /// An arrangement that should go into the setlist about to be created.
    @State private var setlistSeedScore: String?
    /// The setlist whose arrangement picker is open.
    @State private var setlistPicker: SetlistDoc?
    /// The arrangement being put into a set list from its own row.
    @State private var setlistChooserScore: ScoreDoc?
    @State private var setlistRenameDraft = ""
    /// Which target the dragged arrangement is currently over. One piece of
    /// state for all of them, so exactly one thing can be lit at a time.
    @State private var dropTarget: DropTarget?
    /// The arrangement currently lifted, if any. Every place it could be
    /// dropped shows itself while it is in the air — before this, the highlight
    /// only appeared once the finger was already over a target, so lifting a
    /// row taught the user nothing about where it could go.
    ///
    /// SwiftUI's `.onDrag` has no "session ended" callback, so a drag the user
    /// abandons in mid-air is cleared by the timeout below rather than by an
    /// event. A drop clears it immediately.
    @State private var lifted: String?
    @State private var liftTimeout: Task<Void, Never>?

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
        VStack(spacing: 0) {
            ScoreTopBar(annotation: state.annotation,
                        number: state.selectedScore
                            .flatMap { state.placement(of: $0.slug)?.number },
                        title: scoreTitle,
                        subtitle: scoreSubtitle,
                        mode: $state.scoreMode,
                        titleMenuOpen: $state.titleMenuOpen,
                        moreOpen: $state.moreMenuOpen,
                        chatOpen: chatOpen,
                        onClose: onClose,
                        onAsk: {
                            withAnimation(Theme.Motion.overlay(reduced: reduceMotion)) {
                                chatOpen.toggle()
                            }
                        })
            ZStack(alignment: .top) {
                Theme.Surface.ground
                canvasLayer
                overlayLayer
                // The two menus the top bar opens. Plain children of the
                // canvas stack rather than an overlay on the whole view: as an
                // overlay they did not materialise at all, and a menu that
                // cannot be opened is worse than one that is in the wrong place.
                if state.titleMenuOpen || state.moreMenuOpen {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { state.titleMenuOpen = false; state.moreMenuOpen = false }
                    titleMenu
                    HStack { Spacer(); moreMenu }
                }
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
                               onJump: { index in state.visiblePageIndices = [index] })
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
        .onChange(of: state.notice) { _, notice in
            if let notice { alertRequest = .notice(notice) }
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
        .overlay { dialogLayer }
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

    @ViewBuilder
    private var titleMenu: some View {
        if state.titleMenuOpen, let score = state.selectedScore {
            TitleMenu(score: score,
                      onPick: { slug in
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
                          state.moreMenuOpen = true
                      })
                .padding(.top, Theme.Metric.s4)
        }
    }

    @ViewBuilder
    private var moreMenu: some View {
        if state.moreMenuOpen {
            MoreMenu(mode: $state.scoreMode,
                     showTransport: $showTransport,
                     onClose: { state.moreMenuOpen = false },
                     onSettings: { showSettings = true },
                     onDetails: { infoScore = state.selectedScore },
                     onExport: { exportRequested += 1 })
                .padding(.top, Theme.Metric.s4)
                .padding(.trailing, Theme.Metric.s12)
        }
    }

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

    // MARK: - Dialogs

    @ViewBuilder
    private var dialogLayer: some View {
        if infoScore != nil || showSettings || alertRequest != nil
            || setlistPicker != nil || setlistChooserScore != nil {
            ZStack {
                DialogScrim {
                    // alerts are decisions: only sheets dismiss on the scrim
                    if alertRequest == nil {
                        infoScore = nil
                        showSettings = false
                        setlistPicker = nil
                        setlistChooserScore = nil
                    }
                }
                if let score = infoScore {
                    PanelSheet(title: score.name,
                               number: state.placement(of: score.slug)?.number,
                               onDone: { infoScore = nil }) {
                        ScoreInfoView(score: score)
                    }
                } else if showSettings {
                    PanelSheet(title: "Settings", onDone: { showSettings = false }) {
                        SettingsView()
                    }
                } else if let setlist = setlistPicker {
                    PanelSheet(title: setlist.name, onDone: { setlistPicker = nil }) {
                        SetlistPickerView(setlist: setlist)
                    }
                } else if let score = setlistChooserScore {
                    PanelSheet(title: score.name,
                               onDone: { setlistChooserScore = nil }) {
                        SetlistChooserView(score: score) {
                            newSetlistName = ""
                            setlistSeedScore = score.slug
                            setlistChooserScore = nil
                            alertRequest = .newSetlist
                        }
                    }
                }
                if let request = alertRequest { alertView(request) }
            }
            .transition(.opacity)
        }
    }

    /// One presenter for every dialog, so they cannot disagree about width,
    /// footer or button order.
    enum AlertRequest: Equatable {
        case deleteArrangement(ScoreDoc)
        case newPiece(ScoreDoc)
        case newSetlist
        case renameSetlist(SetlistDoc)
        case deleteSetlist(SetlistDoc)
        case notice(String)
    }

    @ViewBuilder
    private func alertView(_ request: AlertRequest) -> some View {
        switch request {
        case .deleteArrangement(let score):
            PanelAlert(title: "Delete \(score.name)?",
                       message: "This removes the arrangement and all its versions. The piece and its other arrangements are untouched.",
                       verb: "Delete", isDestructive: true,
                       onCancel: { alertRequest = nil },
                       onConfirm: {
                           state.deleteScore(slug: score.slug)
                           alertRequest = nil
                       })
        case .newPiece(let score):
            PanelAlert(title: "New piece",
                       message: "File \u{201C}\(score.name)\u{201D} under a new piece.",
                       field: $newPieceName, fieldPlaceholder: "Piece name",
                       verb: "Create",
                       onCancel: { alertRequest = nil },
                       onConfirm: {
                           let name = newPieceName.trimmingCharacters(in: .whitespacesAndNewlines)
                           if !name.isEmpty {
                               state.createPieceAndAssign(name: name, scoreSlug: score.slug)
                           }
                           alertRequest = nil
                       })
        case .newSetlist:
            PanelAlert(title: "New setlist",
                       message: "A setlist is an ordered group of pieces \u{2014} a gig's running order.",
                       field: $newSetlistName, fieldPlaceholder: "Setlist name",
                       verb: "Create",
                       onCancel: { alertRequest = nil },
                       onConfirm: {
                           let name = newSetlistName.trimmingCharacters(in: .whitespacesAndNewlines)
                           let seed = setlistSeedScore
                           setlistSeedScore = nil
                           if !name.isEmpty {
                               Task {
                                   // name first, then contents — and the picker
                                   // opens on the setlist that was just made
                                   guard let slug = await state.createSetlist(name: name)
                                   else { return }
                                   if let seed {
                                       await state.addToSetlist(setlist: slug, score: seed)
                                   }
                                   setlistPicker = state.manifest?.setlists?
                                       .first { $0.slug == slug }
                               }
                           }
                           alertRequest = nil
                       })
        case .renameSetlist(let setlist):
            PanelAlert(title: "Rename setlist",
                       field: $setlistRenameDraft, fieldPlaceholder: "Setlist name",
                       verb: "Rename",
                       onCancel: { alertRequest = nil },
                       onConfirm: {
                           let name = setlistRenameDraft
                               .trimmingCharacters(in: .whitespacesAndNewlines)
                           if !name.isEmpty {
                               Task { await state.renameSetlist(setlist: setlist.slug, name: name) }
                           }
                           alertRequest = nil
                       })
        case .deleteSetlist(let setlist):
            PanelAlert(title: "Delete \(setlist.name)?",
                       message: "Only the grouping is removed. The pieces and their arrangements stay.",
                       verb: "Delete", isDestructive: true,
                       onCancel: { alertRequest = nil },
                       onConfirm: {
                           Task { await state.deleteSetlist(setlist.slug) }
                           alertRequest = nil
                       })
        case .notice(let text):
            PanelNotice(title: "Scoranger", message: text) {
                state.notice = nil
                alertRequest = nil
            }
        }
    }

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
                      action: { alertRequest = .deleteArrangement(score) })
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
                    Menu {
                        ForEach(catalog.models.keys.sorted(), id: \.self) { alias in
                            Button {
                                state.chatModel = alias
                            } label: {
                                if state.chatModel == alias {
                                    Label(alias, systemImage: "checkmark")
                                } else { Text(alias) }
                            }
                        }
                    } label: {
                        Text(state.chatModel.isEmpty ? (catalog.default) : state.chatModel)
                            .typeRole(.data)
                            .foregroundStyle(Theme.Ink.ink2)
                            .padding(.vertical, Theme.Metric.s4)
                            .padding(.horizontal, Theme.Metric.s6)
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                                    .stroke(Theme.Line.line2, lineWidth: 1)
                            }
                    }
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

/// What a dragged arrangement is hovering over.
///
/// Every row in the library drags (it carries its slug), and four kinds of
/// thing accept a drop: a piece heading files it, a row inside a piece places
/// it at that position, a setlist heading adds it to the running order, and
/// the Unfiled band takes it out of its piece. Every one of those also stays
/// in the context menu — a drag that will not start on someone's iPad must
/// never be the only way to do something.
enum DropTarget: Equatable {
    case piece(String)
    case setlist(String)
    /// Insert before this arrangement, in this piece.
    case row(piece: String, before: String)
    case unfiled
}

/// The dashed outline that says "let go here".
private struct DropHighlight: ViewModifier {
    let active: Bool
    /// Something is in the air that this target could accept: shown quietly, so
    /// lifting a row reveals where it can go.
    let available: Bool
    /// A row inserts *between* rows, so it marks the gap rather than the row.
    let asInsertionLine: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: asInsertionLine ? .top : .center) {
            if !active && available {
                if asInsertionLine {
                    Capsule().fill(Theme.Accent.clay.opacity(0.35))
                        .frame(height: 2)
                        .padding(.horizontal, Theme.Metric.panelPadding)
                } else {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .strokeBorder(Theme.Accent.clay.opacity(0.35),
                                      style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
            if active {
                if asInsertionLine {
                    Capsule().fill(Theme.Accent.clay)
                        .frame(height: 2)
                        .padding(.horizontal, Theme.Metric.panelPadding)
                } else {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .strokeBorder(Theme.Accent.clay,
                                      style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .background(Theme.Accent.clayTint.opacity(0.6))
                }
            }
        }
    }
}

/// A row inside a piece is a drop target: what lands on it takes its place in
/// the running order and everything below shifts down, which is the #N
/// renumbering the user sees. A row in Unfiled has no order to join, so it
/// accepts nothing.
private struct RowDrop: ViewModifier {
    let section: (piece: PieceDoc, arrangements: [ScoreDoc])?
    let score: ScoreDoc
    @Binding var target: DropTarget?
    /// What is in the air, if anything. A row never advertises itself as a
    /// place to drop the row that is already it.
    let lifted: String?
    let onDrop: () -> Void
    let state: AppState

    func body(content: Content) -> some View {
        if let section {
            content.acceptsArrangementDrop(
                .row(piece: section.piece.slug, before: score.slug),
                target: $target,
                available: lifted != nil && lifted != score.slug,
                insertionLine: true
            ) { slug in
                onDrop()
                guard slug != score.slug else { return }
                state.placeInPiece(scoreSlug: slug, piece: section.piece.slug,
                                   before: score.slug)
            }
        } else {
            content
        }
    }
}

extension View {
    /// Accept an arrangement dragged from anywhere in the library.
    ///
    /// The payload is the arrangement's slug as plain text, which is what the
    /// rows already hand out. `isTargeted` writes into one shared piece of
    /// state so only the zone under the finger lights up.
    func acceptsArrangementDrop(_ zone: DropTarget,
                                target: Binding<DropTarget?>,
                                available: Bool = false,
                                insertionLine: Bool = false,
                                perform: @escaping (String) -> Void) -> some View {
        modifier(DropHighlight(active: target.wrappedValue == zone,
                               available: available,
                               asInsertionLine: insertionLine))
            .dropDestination(for: String.self) { slugs, _ in
                guard let slug = slugs.first else { return false }
                perform(slug)
                return true
            } isTargeted: { over in
                target.wrappedValue = over ? zone : nil
            }
    }
}

/// Observes the shared annotation controller so the pill reflects markup state
/// and carries the live ink colour.
// The pill is gone from the score view: the top bar carries its duties
// (NAVIGATION_SYSTEM.md §8), and with the legacy overlay removed there is
// nothing left for its library button to open.

