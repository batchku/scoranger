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
    @State private var setlistRenameDraft = ""
    @State private var dropTargetPiece: String?

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
        if infoScore != nil || showSettings || alertRequest != nil {
            ZStack {
                DialogScrim {
                    // alerts are decisions: only sheets dismiss on the scrim
                    if alertRequest == nil { infoScore = nil; showSettings = false }
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
                           if !name.isEmpty { Task { await state.createSetlist(name: name) } }
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
        let bothOpen = libraryOpen && chatOpen && !isCompact
        let pageWidth = bothOpen ? Theme.Metric.pageWidthBothOpen : Theme.Metric.pageWidth
        HStack(spacing: 0) {
            Color.clear.frame(width: isCompact ? 0 : (libraryOpen ? Theme.Metric.libraryWidth : 0))
            Group {
                if let score = state.selectedScore {
                    scorePane(score)
                        .frame(maxWidth: pageWidth + Theme.Metric.s24)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity)
            Color.clear.frame(width: isCompact ? 0 : (chatOpen ? Theme.Metric.chatWidth : 0))
        }
        .animation(Theme.Motion.overlay(reduced: reduceMotion), value: libraryOpen)
        .animation(Theme.Motion.overlay(reduced: reduceMotion), value: chatOpen)
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
            emptyNote("No setlists yet. Use + to group pieces into a running order.")
        }
        ForEach(state.setlistSections, id: \.setlist.slug) { section in
            setlistRow(section.setlist, pieces: section.pieces)
            if !collapsedSetlists.contains(section.setlist.slug) {
                if section.pieces.isEmpty {
                    emptyNote("Empty — add pieces from the + on this setlist.")
                }
                ForEach(section.pieces) { piece in
                    setlistPieceRow(piece, in: section.setlist)
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
                        versionRows(for: score)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var unfiledSection: some View {
        if !state.unfiledScores.isEmpty {
            BandHeader((state.manifest?.pieces ?? []).isEmpty
                       ? "Arrangements" : "Unfiled arrangements")
            ForEach(state.unfiledScores) { score in
                arrangementRow(score)
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

    private func setlistRow(_ setlist: SetlistDoc, pieces: [PieceDoc]) -> some View {
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
            addPieceMenu(setlist, current: pieces)
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
    }

    private func addPieceMenu(_ setlist: SetlistDoc, current: [PieceDoc]) -> some View {
        let members = Set(current.map(\.slug))
        let candidates = (state.manifest?.pieces ?? []).filter { !members.contains($0.slug) }
        return Menu {
            if candidates.isEmpty {
                Text("Every piece is already in this setlist")
            }
            ForEach(candidates) { piece in
                Button(piece.name) {
                    Task { await state.addPieceToSetlist(setlist: setlist.slug,
                                                         piece: piece.slug) }
                }
            }
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
        .accessibilityLabel("Add a piece to \(setlist.name)")
    }

    private func setlistPieceRow(_ piece: PieceDoc, in setlist: SetlistDoc) -> some View {
        let arrangements = state.pieceSections
            .first { $0.piece.slug == piece.slug }?.arrangements ?? []
        return Button {
            collapsedPieces.remove(piece.slug)
            if let first = arrangements.first { openScore(first.slug) }
        } label: {
            HStack {
                Text(piece.name).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                Spacer()
                Text("\(arrangements.count)").typeRole(.data)
                    .foregroundStyle(Theme.Ink.ink3)
            }
            .padding(.leading, Theme.Metric.s20)
            .padding(.horizontal, Theme.Metric.panelPadding)
            .padding(.vertical, Theme.Metric.rowVertical)
            .frame(minHeight: Theme.Metric.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                Task { await state.removePieceFromSetlist(setlist: setlist.slug,
                                                          piece: piece.slug) }
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
        .overlay {
            if dropTargetPiece == piece.slug {
                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                    .strokeBorder(Theme.Accent.clay, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .background(Theme.Accent.clayTint.opacity(0.6))
            }
        }
        .onDrop(of: [.plainText], isTargeted: Binding(
            get: { dropTargetPiece == piece.slug },
            set: { dropTargetPiece = $0 ? piece.slug : nil }
        )) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let slug = object as? String else { return }
                Task { @MainActor in state.assignToPiece(scoreSlug: slug, piece: piece.slug) }
            }
            return true
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

            PanelIconButton(systemName: "info.circle", label: "Arrangement details",
                            bordered: false, size: 26) { infoScore = score }
        }
        .padding(.horizontal, Theme.Metric.panelPadding)
        .padding(.vertical, Theme.Metric.rowVertical)
        .frame(minHeight: Theme.Metric.rowMinHeight)
        .background(RowSelectionBackground(isSelected: isOpen))
        .onDrag { NSItemProvider(object: score.slug as NSString) }
        .contextMenu { arrangementMenu(score, number: number, inPiece: section) }
    }

    @ViewBuilder
    private func arrangementMenu(_ score: ScoreDoc, number: Int?,
                                 inPiece section: (piece: PieceDoc, arrangements: [ScoreDoc])?) -> some View {
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
        let isDisplayed = score.slug == state.selectedScore?.slug
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
            Toggle("Highlight a passage for chat", isOn: Binding(
                get: { state.highlightMode }, set: { state.highlightMode = $0 }))
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
