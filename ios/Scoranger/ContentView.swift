import SwiftUI
import UniformTypeIdentifiers

/// Score-first (§7, §8): the score is the permanent ground, the library and chat
/// slide over it, and every canvas control lives in one pill. There is no
/// navigation bar, no title bar and no split view — losing `NavigationSplitView`
/// is the largest change in the revamp.
struct ContentView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The two overlays, which replace the split view's columns.
    @State private var libraryOpen = false
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

    private static let scoreTypes: [UTType] = ([
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
            Theme.Surface.ground.ignoresSafeArea()
            canvasLayer
            overlayLayer
        }
        .overlay(alignment: .bottom) { pillLayer }
        .background(Theme.Surface.ground)
        .task {
            Theme.verifyFontsRegistered()
            state.resetViewPreferencesForTesting()
            state.startPolling()
        }
        .onChange(of: state.notice) { _, notice in
            if let notice { alertRequest = .notice(notice) }
        }
        .onAppear {
            guard !didSetInitialOverlays else { return }
            didSetInitialOverlays = true
            // the score is the ground: on iPad the library starts open so the
            // library is discoverable, on iPhone nothing covers the score
            libraryOpen = !isCompact
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
            Color.clear.frame(width: isCompact ? 0 : (libraryOpen ? Theme.Metric.libraryWidth : 0))
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
        .animation(Theme.Motion.overlay(reduced: reduceMotion), value: libraryOpen)
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
                ScorePagesView(document: doc, annotationKey: "\(score.slug)/\(vid)")
            }
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
        if !state.engineOK && !state.useLocalEngine {
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
                withAnimation(Theme.Motion.overlay(reduced: reduceMotion)) { libraryOpen = true }
            }
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var overlayLayer: some View {
        HStack(spacing: 0) {
            if libraryOpen {
                OverlayPanel(edge: .leading,
                             width: isCompact ? .infinity : Theme.Metric.libraryWidth) {
                    libraryPanel
                }
                .transition(panelTransition(.leading))
            }
            Spacer(minLength: 0)
            if chatOpen && !(isCompact && libraryOpen) {
                OverlayPanel(edge: .trailing,
                             width: isCompact ? .infinity : Theme.Metric.chatWidth) {
                    chatPanel
                }
                .transition(panelTransition(.trailing))
            }
        }
        .animation(Theme.Motion.overlay(reduced: reduceMotion), value: libraryOpen)
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

    // MARK: - Library

    @ViewBuilder
    private var libraryPanel: some View {
        VStack(spacing: 0) {
            OverlayHeader(subject: {
                Text("Scoranger")
                    .typeRole(.title)
                    .foregroundStyle(Theme.Ink.ink)
            }, trailing: {
                HStack(spacing: Theme.Metric.s4) {
                    LED(isOn: state.engineOK, showsLabel: false)
                    if state.useLocalEngine {
                        PanelIconButton(systemName: "plus", label: "Import an arrangement",
                                        size: 30) {
                            importTargetPiece = nil
                            showImporter = true
                        }
                    }
                    PanelIconButton(systemName: "gearshape", label: "Settings", size: 30) {
                        showSettings = true
                    }
                }
            }, onDismiss: {
                withAnimation(Theme.Motion.overlay(reduced: reduceMotion)) { libraryOpen = false }
            }, dismissLabel: "Close library")

            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    statusSection
                    setlistsSection
                    piecesSection
                    unfiledSection
                }
            }
            .background(Theme.Surface.panel)

            // build identity, always visible
            Text(Self.buildStamp)
                .typeRole(.dataS)
                .foregroundStyle(Theme.Ink.ink3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Metric.s6)
                .background(Theme.Surface.band)
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.Line.line2).frame(height: 1)
                }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if state.manifest == nil || !state.pendingImports.isEmpty {
            BandHeader("Status")
            if state.manifest == nil {
                HStack(spacing: Theme.Metric.s8) {
                    ProgressView().controlSize(.small).tint(Theme.Accent.clay)
                    Text("starting engine…").typeRole(.data)
                        .foregroundStyle(Theme.Ink.ink2)
                }
                .padding(.horizontal, Theme.Metric.panelPadding)
                .padding(.vertical, Theme.Metric.rowVertical)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // §7.18: name, a bordered track with a clay fill, stage in mono
            ForEach(state.pendingImports) { pending in
                VStack(alignment: .leading, spacing: Theme.Metric.s4) {
                    Text(pending.name).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                        .lineLimit(1)
                    if let fraction = pending.fraction {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Theme.Surface.well)
                                Rectangle().fill(Theme.Accent.clay)
                                    .frame(width: geo.size.width * fraction)
                            }
                        }
                        .frame(height: 4)
                        .overlay { Rectangle().stroke(Theme.Line.line2, lineWidth: 1) }
                    } else {
                        ProgressView().controlSize(.small).tint(Theme.Accent.clay)
                    }
                    Text(pending.stage).typeRole(.dataS).foregroundStyle(Theme.Ink.ink3)
                }
                .padding(.horizontal, Theme.Metric.panelPadding)
                .padding(.vertical, Theme.Metric.rowVertical)
            }
        }
    }

    @ViewBuilder
    private var setlistsSection: some View {
        BandHeader(title: "Setlists") {
            PanelIconButton(systemName: "plus", label: "New setlist", size: 22) {
                newSetlistName = ""
                alertRequest = .newSetlist
            }
        }
        if state.setlistSections.isEmpty {
            emptyNote("No setlists yet. Use + to put arrangements in a running order.")
        }
        ForEach(state.setlistSections, id: \.setlist.slug) { section in
            setlistRow(section.setlist, arrangements: section.arrangements)
            if !collapsedSetlists.contains(section.setlist.slug) {
                if section.arrangements.isEmpty {
                    emptyNote("Empty — add arrangements from the + on this setlist.")
                }
                ForEach(section.arrangements) { score in
                    setlistArrangementRow(score, in: section.setlist)
                        .id("setlist/\(section.setlist.slug)/\(score.slug)")
                }
            }
        }
    }

    @ViewBuilder
    private var piecesSection: some View {
        if !state.pieceSections.isEmpty {
            BandHeader("Pieces")
            ForEach(state.pieceSections, id: \.piece.slug) { section in
                pieceRow(section)
                if !collapsedPieces.contains(section.piece.slug) {
                    ForEach(Array(section.arrangements.enumerated()),
                            id: \.element.slug) { index, score in
                        arrangementRow(score, number: index + 1, inPiece: section)
                            // Identity has to say which section the row is in.
                            // Keyed on the slug alone, a row that moves between
                            // Unfiled and a piece matches the one it replaces
                            // and SwiftUI reuses it — keeping the numeral it had
                            // before the move (none, for a row arriving from
                            // Unfiled) along with its highlight.
                            .id("piece/\(section.piece.slug)/\(score.slug)")
                        versionRows(for: score)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var unfiledSection: some View {
        // The band exists only when something is in it, so dragging OUT of a
        // piece works when there is already an unfiled arrangement to aim at
        // and not otherwise. "Remove from piece" stays in the row's context
        // menu, which is the way that always works.
        if !state.unfiledScores.isEmpty {
            BandHeader((state.manifest?.pieces ?? []).isEmpty
                       ? "Arrangements" : "Unfiled arrangements")
                .acceptsArrangementDrop(.unfiled, target: $dropTarget) { slug in
                    state.assignToPiece(scoreSlug: slug, piece: nil)
                }
            ForEach(state.unfiledScores) { score in
                arrangementRow(score)
                    .id("unfiled/\(score.slug)")
                versionRows(for: score)
            }
        }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .typeRole(.meta)
            .foregroundStyle(Theme.Ink.ink3)
            .padding(.horizontal, Theme.Metric.panelPadding)
            .padding(.vertical, Theme.Metric.rowVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Rows

    private func caret(_ expanded: Bool) -> some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.Accent.clay)
            .rotationEffect(.degrees(expanded ? 90 : 0))
    }

    private func setlistRow(_ setlist: SetlistDoc,
                            arrangements: [ScoreDoc]) -> some View {
        let collapsed = collapsedSetlists.contains(setlist.slug)
        return HStack(spacing: Theme.Metric.s8) {
            Button {
                withAnimation(Theme.Motion.disclosure) {
                    if collapsed { collapsedSetlists.remove(setlist.slug) }
                    else { collapsedSetlists.insert(setlist.slug) }
                }
            } label: {
                HStack(spacing: Theme.Metric.s8) {
                    caret(!collapsed)
                    Text(setlist.name).typeRole(.titleS).foregroundStyle(Theme.Ink.ink)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(collapsed ? "Expand" : "Collapse") setlist \(setlist.name)")
            addArrangementButton(setlist)
        }
        .padding(.horizontal, Theme.Metric.panelPadding)
        .padding(.vertical, Theme.Metric.rowVertical)
        .frame(minHeight: Theme.Metric.rowMinHeight)
        .contextMenu {
            Button {
                setlistRenameDraft = setlist.name
                alertRequest = .renameSetlist(setlist)
            } label: { Label("Rename setlist", systemImage: "pencil") }
            Button(role: .destructive) { alertRequest = .deleteSetlist(setlist) } label: {
                Label("Delete setlist", systemImage: "trash")
            }
        }
        .acceptsArrangementDrop(.setlist(setlist.slug), target: $dropTarget) { slug in
            Task { await state.addToSetlist(setlist: setlist.slug, score: slug) }
        }
    }

    /// The + on a setlist: pick arrangements to put in it.
    private func addArrangementButton(_ setlist: SetlistDoc) -> some View {
        Button { setlistPicker = setlist } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Ink.ink2)
                .frame(width: 22, height: 22)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(Theme.Line.line2, lineWidth: 1)
                }
                .frame(width: Theme.Metric.hitTarget, height: Theme.Metric.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("add-to-setlist-\(setlist.slug)")
        .accessibilityLabel("Add an arrangement to \(setlist.name)")
    }

    /// One arrangement in a running order. It shows the piece it belongs to,
    /// because in a set the tune is the context and the arrangement is the
    /// thing being played.
    private func setlistArrangementRow(_ score: ScoreDoc,
                                       in setlist: SetlistDoc) -> some View {
        let placement = state.placement(of: score.slug)
        return Button { openScore(score.slug) } label: {
            HStack(spacing: Theme.Metric.s8) {
                if let placement { NumeralBadge(number: placement.number) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(score.name).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                        .lineLimit(1)
                    if let placement {
                        Text(placement.piece.name).typeRole(.meta)
                            .foregroundStyle(Theme.Ink.ink3).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, Theme.Metric.s20)
            .padding(.horizontal, Theme.Metric.panelPadding)
            .padding(.vertical, Theme.Metric.rowVertical)
            .frame(minHeight: Theme.Metric.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("setlist-\(setlist.slug)-\(score.slug)")
        .contextMenu {
            Button(role: .destructive) {
                Task { await state.removeFromSetlist(setlist: setlist.slug,
                                                     score: score.slug) }
            } label: { Label("Remove from \(setlist.name)", systemImage: "minus.circle") }
        }
    }

    private func pieceRow(_ section: (piece: PieceDoc, arrangements: [ScoreDoc])) -> some View {
        let piece = section.piece
        let collapsed = collapsedPieces.contains(piece.slug)
        return HStack(spacing: Theme.Metric.s8) {
            Button {
                withAnimation(Theme.Motion.disclosure) {
                    if collapsed { collapsedPieces.remove(piece.slug) }
                    else { collapsedPieces.insert(piece.slug) }
                }
            } label: {
                HStack(spacing: Theme.Metric.s8) {
                    caret(!collapsed)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(piece.name).typeRole(.titleS).foregroundStyle(Theme.Ink.ink)
                        Text("\(section.arrangements.count) arrangement"
                             + (section.arrangements.count == 1 ? "" : "s"))
                            .typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(collapsed ? "Expand" : "Collapse") \(piece.name)")
            addArrangementMenu(section)
        }
        .padding(.horizontal, Theme.Metric.panelPadding)
        .padding(.vertical, Theme.Metric.rowVertical)
        .frame(minHeight: Theme.Metric.rowMinHeight)
        .background(RowSelectionBackground(isSelected: false))
        .acceptsArrangementDrop(.piece(piece.slug), target: $dropTarget) { slug in
            state.assignToPiece(scoreSlug: slug, piece: piece.slug)
        }
    }

    private func addArrangementMenu(
        _ section: (piece: PieceDoc, arrangements: [ScoreDoc])) -> some View {
        Menu {
            Button {
                Task {
                    if let slug = await state.createArrangement(pieceSlug: section.piece.slug,
                                                               name: "New arrangement") {
                        openScore(slug)
                        chatOpen = true
                    }
                }
            } label: { Label("New blank arrangement", systemImage: "doc") }
            if !section.arrangements.isEmpty {
                Menu {
                    ForEach(Array(section.arrangements.enumerated()),
                            id: \.element.slug) { index, score in
                        Button("#\(index + 1)  \(score.name)") {
                            Task {
                                if let slug = await state.duplicateScore(
                                    slug: score.slug, name: "\(score.name) copy") {
                                    openScore(slug)
                                    chatOpen = true
                                }
                            }
                        }
                    }
                } label: { Label("Duplicate an arrangement", systemImage: "plus.square.on.square") }
            }
            Button {
                importTargetPiece = section.piece.slug
                showImporter = true
            } label: { Label("Import a file into this piece", systemImage: "square.and.arrow.down") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Ink.ink2)
                .frame(width: 22, height: 22)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(Theme.Line.line2, lineWidth: 1)
                }
                .frame(width: Theme.Metric.hitTarget, height: Theme.Metric.hitTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Add an arrangement to \(section.piece.name)")
    }

    /// §7.4 + §7.5. Unfiled arrangements have no numeral and no reserved space:
    /// the number only means something inside a piece.
    private func arrangementRow(_ score: ScoreDoc, number: Int? = nil,
                                inPiece section: (piece: PieceDoc, arrangements: [ScoreDoc])? = nil) -> some View {
        let isOpen = state.selectedScore?.slug == score.slug
        let expanded = expandedArrangements.contains(score.slug)
        return HStack(spacing: Theme.Metric.s6) {
            Button {
                withAnimation(Theme.Motion.disclosure) {
                    if expanded { expandedArrangements.remove(score.slug) }
                    else { expandedArrangements.insert(score.slug) }
                }
            } label: {
                caret(expanded)
                    .frame(width: 20, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Hide versions of \(score.name)"
                                         : "Show versions of \(score.name)")
            .accessibilityIdentifier("versions-toggle-\(score.slug)")

            Button { openScore(score.slug) } label: {
                HStack(spacing: Theme.Metric.s8) {
                    if let number { NumeralBadge(number: number) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(score.name).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                            .lineLimit(1)
                        Text(arrangementSubtitle(score)).typeRole(.meta)
                            .foregroundStyle(Theme.Ink.ink3).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("arrangement-\(score.slug)")
            // the highlight is a selection, so say so: VoiceOver announces it
            // and a test can count how many rows claim to be selected
            .accessibilityAddTraits(isOpen ? [.isSelected] : [])

            PanelIconButton(systemName: "info.circle", label: "Arrangement details",
                            bordered: false, size: 26) { infoScore = score }
        }
        .padding(.horizontal, Theme.Metric.panelPadding)
        .padding(.vertical, Theme.Metric.rowVertical)
        .frame(minHeight: Theme.Metric.rowMinHeight)
        .background(RowSelectionBackground(isSelected: isOpen))
        .onDrag { NSItemProvider(object: score.slug as NSString) }
        .contextMenu { arrangementMenu(score, number: number, inPiece: section) }
        // outside the context menu, which swallows the drop when it wraps it
        .modifier(RowDrop(section: section, score: score,
                          target: $dropTarget, state: state))
    }

    @ViewBuilder
    private func arrangementMenu(_ score: ScoreDoc, number: Int?,
                                 inPiece section: (piece: PieceDoc, arrangements: [ScoreDoc])?) -> some View {
        // A flat action, not a nested Menu: a Menu inside a contextMenu hung
        // the app hard enough for the watchdog to kill it.
        Button {
            setlistChooserScore = score
        } label: { Label("Add to set list…", systemImage: "music.note.list") }
        if let section, let number {
            let index = number - 1
            let slugs = section.arrangements.map(\.slug)
            if index > 0 {
                Button {
                    var order = slugs; order.swapAt(index, index - 1)
                    state.reorderPiece(piece: section.piece.slug, order: order)
                } label: { Label("Move up (become #\(number - 1))", systemImage: "arrow.up") }
            }
            if index < slugs.count - 1 {
                Button {
                    var order = slugs; order.swapAt(index, index + 1)
                    state.reorderPiece(piece: section.piece.slug, order: order)
                } label: { Label("Move down (become #\(number + 1))", systemImage: "arrow.down") }
            }
        }
        Button {
            Task { await state.duplicateScore(slug: score.slug, name: "\(score.name) copy") }
        } label: { Label("Duplicate arrangement", systemImage: "plus.square.on.square") }
        Menu("Move to piece") {
            ForEach(state.manifest?.pieces ?? []) { piece in
                Button {
                    state.assignToPiece(scoreSlug: score.slug, piece: piece.slug)
                } label: {
                    if score.piece == piece.slug {
                        Label(piece.name, systemImage: "checkmark")
                    } else { Text(piece.name) }
                }
            }
            Divider()
            Button("New piece…") {
                newPieceName = ""
                alertRequest = .newPiece(score)
            }
        }
        if score.piece != nil {
            Button("Remove from piece") {
                state.assignToPiece(scoreSlug: score.slug, piece: nil)
            }
        }
        Divider()
        Button(role: .destructive) { alertRequest = .deleteArrangement(score) } label: {
            Label("Delete arrangement", systemImage: "trash")
        }
    }

    private func arrangementSubtitle(_ score: ScoreDoc) -> String {
        var bits: [String] = []
        let parts = (score.versions.first { $0.id == score.latest }
                     ?? score.versions.last)?.parts ?? []
        if !parts.isEmpty {
            let names = parts.map(\.name)
            bits.append(names.count <= 3
                        ? names.joined(separator: ", ")
                        : names.prefix(2).joined(separator: ", ") + " +\(names.count - 2) more")
        }
        bits.append("\(score.versions.count) version\(score.versions.count == 1 ? "" : "s")")
        if let n = score.sources?.count, n > 0 {
            bits.append("\(n) source\(n == 1 ? "" : "s")")
        }
        return bits.joined(separator: " · ")
    }

    // MARK: - Version rows (§7.6)

    @ViewBuilder
    private func versionRows(for score: ScoreDoc) -> some View {
        if expandedArrangements.contains(score.slug) {
            ForEach(state.versionGroups(for: score)) { group in
                versionGroupRow(score, group)
                if expandedVersionGroups.contains("\(score.slug)/\(group.id)") {
                    ForEach(group.subs.reversed()) { step in
                        stepRow(score, step)
                    }
                }
            }
        }
    }

    private func versionGroupRow(_ score: ScoreDoc,
                                 _ group: AppState.VersionGroup) -> some View {
        let key = "\(score.slug)/\(group.id)"
        let expanded = expandedVersionGroups.contains(key)
        let hasSteps = group.subs.count > 1
        // Exactly one row in the library may be lit, and it is the row that
        // stands for the version on screen. A group's steps include its own
        // face, so while the group is open the step rows own the highlight --
        // lighting the group as well put two marks on one version, which read
        // as two versions being open at once.
        let isDisplayed = score.slug == state.selectedScore?.slug
            && !expanded
            && (group.face.id == state.displayedVersionID
                || group.subs.contains { $0.id == state.displayedVersionID })
        return HStack(spacing: Theme.Metric.s6) {
            if hasSteps {
                Button {
                    withAnimation(Theme.Motion.disclosure) {
                        if expanded { expandedVersionGroups.remove(key) }
                        else { expandedVersionGroups.insert(key) }
                    }
                } label: {
                    caret(expanded).frame(width: 18, height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Hide the steps of this prompt"
                                             : "Show the \(group.subs.count) steps of this prompt")
                .accessibilityIdentifier("steps-toggle-\(score.slug)-\(group.id)")
            } else {
                Spacer().frame(width: 18)
            }
            Button {
                openScore(score.slug,
                          version: group.face.id == score.latest ? nil : group.face.id)
            } label: {
                HStack(spacing: Theme.Metric.s6) {
                    Text(group.face.id).typeRole(.data).foregroundStyle(Theme.Ink.ink2)
                    Text(group.title).typeRole(.meta).foregroundStyle(Theme.Ink.ink)
                        .lineLimit(1)
                    if hasSteps {
                        Text("\(group.subs.count) steps").typeRole(.dataS)
                            .foregroundStyle(Theme.Ink.ink3)
                    }
                    Spacer(minLength: 0)
                    if isDisplayed {
                        Image(systemName: "circle.fill").font(.system(size: 7))
                            .foregroundStyle(Theme.Accent.clay)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("version-\(score.slug)-\(group.face.id)")
            // a highlight nobody can query is a highlight nobody can test
            .accessibilityAddTraits(isDisplayed ? [.isSelected] : [])
        }
        .padding(.leading, Theme.Metric.versionIndent - 18)
        .padding(.trailing, Theme.Metric.panelPadding)
        .padding(.vertical, Theme.Metric.versionRowVertical)
        .background(isDisplayed ? Theme.Surface.well : Color.clear)
    }

    private func stepRow(_ score: ScoreDoc, _ version: VersionDoc) -> some View {
        let isDisplayed = score.slug == state.selectedScore?.slug
            && version.id == state.displayedVersionID
        return Button {
            openScore(score.slug, version: version.id == score.latest ? nil : version.id)
        } label: {
            HStack(spacing: Theme.Metric.s6) {
                Text(version.id).typeRole(.data).foregroundStyle(Theme.Ink.ink2)
                Text(version.op).typeRole(.meta).foregroundStyle(Theme.Ink.ink2).lineLimit(1)
                Spacer(minLength: 0)
                if isDisplayed {
                    Image(systemName: "circle.fill").font(.system(size: 7))
                        .foregroundStyle(Theme.Accent.clay)
                }
            }
            .padding(.leading, Theme.Metric.stepIndent)
            .padding(.trailing, Theme.Metric.panelPadding)
            .padding(.vertical, Theme.Metric.versionRowVertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isDisplayed ? Theme.Surface.well : Color.clear)
        .accessibilityIdentifier("step-\(score.slug)-\(version.id)")
        .accessibilityAddTraits(isDisplayed ? [.isSelected] : [])
    }

    // MARK: - Pill

    /// Wrapped in a child view so the annotation controller can be observed:
    /// the pill shows markup state and the live ink colour.
    @ViewBuilder
    private var pillLayer: some View {
        PillLayer(annotation: state.annotation,
                  number: state.selectedScore.flatMap { state.placement(of: $0.slug)?.number },
                  versionID: state.displayedVersionID,
                  libraryOpen: $libraryOpen,
                  chatOpen: $chatOpen,
                  showsMarkup: !isCompact,
                  versionMenu: { versionMenuItems },
                  optionsMenu: { optionsMenuItems })
    }

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
            withAnimation(Theme.Motion.overlay(reduced: reduceMotion)) { libraryOpen = false }
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
    /// A row inserts *between* rows, so it marks the gap rather than the row.
    let asInsertionLine: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: asInsertionLine ? .top : .center) {
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
    let state: AppState

    func body(content: Content) -> some View {
        if let section {
            content.acceptsArrangementDrop(
                .row(piece: section.piece.slug, before: score.slug),
                target: $target,
                insertionLine: true
            ) { slug in
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
                                insertionLine: Bool = false,
                                perform: @escaping (String) -> Void) -> some View {
        modifier(DropHighlight(active: target.wrappedValue == zone,
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
private struct PillLayer<VersionMenu: View, OptionsMenu: View>: View {
    @ObservedObject var annotation: AnnotationController
    let number: Int?
    let versionID: String?
    @Binding var libraryOpen: Bool
    @Binding var chatOpen: Bool
    let showsMarkup: Bool
    @ViewBuilder var versionMenu: () -> VersionMenu
    @ViewBuilder var optionsMenu: () -> OptionsMenu

    var body: some View {
        CanvasPill(number: number,
                   versionID: versionID,
                   libraryOpen: $libraryOpen,
                   chatOpen: $chatOpen,
                   markupActive: annotation.isOn,
                   markupInk: annotation.ink.swatch,
                   showsMarkup: showsMarkup,
                   onMarkup: { annotation.isOn.toggle() },
                   versionMenu: versionMenu,
                   optionsMenu: optionsMenu)
    }
}
