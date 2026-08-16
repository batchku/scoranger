import SwiftUI

import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var showChat = true
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var didSetInitialChat = false
    @State private var pendingDelete: ScoreDoc?
    @State private var infoScore: ScoreDoc?
    /// Score awaiting a "New piece…" name (drives the naming alert).
    @State private var newPieceTarget: ScoreDoc?
    @State private var newPieceName = ""

    private static let scoreTypes: [UTType] = ([
        UTType(filenameExtension: "musicxml"),
        UTType(filenameExtension: "mxl"),
        UTType(filenameExtension: "xml"),
        UTType(filenameExtension: "mid"),
        UTType(filenameExtension: "midi"),
    ].compactMap { $0 }) + [.pdf]

    /// Which column shows in compact width — set to .detail to open a score.
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            sidebar
        } detail: {
            detail
        }
        .task {
            state.startPolling()
        }
    }

    private func openScore(_ slug: String, version: String? = nil) {
        state.select(slug: slug, version: version)
        compactColumn = .detail
    }

    // MARK: sidebar

    private var sidebar: some View {
        // Plain List — no selection binding: the system's row selection fought
        // the per-row buttons (eaten taps, three competing highlight colors).
        // Preview highlight is ours alone; navigation goes through openScore.
        List {
            Section {
                if state.manifest == nil {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("starting engine…")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                ForEach(state.pendingImports) { pending in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(pending.name)
                            Spacer()
                            if pending.fraction == nil {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        if let fraction = pending.fraction {
                            ProgressView(value: fraction)
                                .controlSize(.small)
                        }
                        Text(pending.stage)
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            // Arrangements grouped by piece, then everything unfiled.
            ForEach(state.pieceSections, id: \.piece.slug) { section in
                Section(section.piece.name) {
                    ForEach(section.arrangements) { score in
                        scoreRow(score)
                    }
                }
            }
            Section((state.manifest?.pieces ?? []).isEmpty ? "Scores" : "Unfiled") {
                ForEach(state.unfiledScores) { score in
                    scoreRow(score)
                }
            }
            // Versions of the previewed score (falls back to the open one);
            // tapping a version opens the score pinned to it.
            if let score = state.previewedScore {
                Section("Versions") {
                    ForEach(score.versions.reversed()) { v in
                        Button {
                            openScore(score.slug,
                                      version: v.id == score.latest ? nil : v.id)
                        } label: {
                            HStack {
                                Text(v.id).font(.system(.caption, design: .monospaced))
                                Text(v.op).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                if score.slug == state.selectedScore?.slug,
                                   v.id == state.displayedVersionID {
                                    Image(systemName: "eye").font(.caption2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Scoranger")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Circle()
                    .fill(state.engineOK ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                    .accessibilityLabel(state.engineOK ? "Engine connected" : "Engine unreachable")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if state.useLocalEngine {
                    Button { showImporter = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Import score")
                }
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $infoScore) { ScoreInfoView(score: $0) }
        .alert(
            "Delete \(pendingDelete?.name ?? "score")?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let score = pendingDelete { state.deleteScore(slug: score.slug) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This removes the score and all its versions.")
        }
        .alert("New piece", isPresented: Binding(
            get: { newPieceTarget != nil },
            set: { if !$0 { newPieceTarget = nil } }
        )) {
            TextField("Piece name", text: $newPieceName)
            Button("OK") {
                let name = newPieceName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let score = newPieceTarget, !name.isEmpty {
                    state.createPieceAndAssign(name: name, scoreSlug: score.slug)
                }
                newPieceTarget = nil
            }
            Button("Cancel", role: .cancel) { newPieceTarget = nil }
        } message: {
            Text("File “\(newPieceTarget?.name ?? "score")” under a new piece.")
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: Self.scoreTypes) { result in
            // receiveFile routes by type: PDFs -> cloud OMR, scores -> direct import
            if case .success(let url) = result { state.receiveFile(at: url) }
        }
        .alert("Scoranger", isPresented: Binding(
            get: { state.notice != nil },
            set: { if !$0 { state.notice = nil } }
        )) {
            Button("OK", role: .cancel) { state.notice = nil }
        } message: {
            Text(state.notice ?? "")
        }
    }

    /// A score row: tap previews (versions in the sidebar), the trailing icons
    /// show metadata, duplicate, or open the score in the detail pane.
    private func scoreRow(_ score: ScoreDoc) -> some View {
        HStack(spacing: 4) {
            Button {
                state.previewedSlug = score.slug
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(score.name)
                        .foregroundStyle(.primary)
                    Text("\(score.versions.count) versions\(sourceCountLabel(score))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            rowIcon("info.circle", label: "Score details") { infoScore = score }
            rowIcon("plus.square.on.square", label: "Duplicate score") {
                state.duplicateScore(slug: score.slug)
            }
            rowIcon("chevron.right.circle", label: "Open score") {
                openScore(score.slug)
            }
        }
        // one highlight system only: warm attention color on the previewed row
        .listRowBackground(
            state.previewedSlug == score.slug ? Color.orange.opacity(0.22) : nil)
        .contextMenu {
            Menu("Move to piece") {
                // full manifest list, including pieces with no arrangements yet
                ForEach(state.manifest?.pieces ?? []) { piece in
                    Button {
                        state.assignToPiece(scoreSlug: score.slug, piece: piece.slug)
                    } label: {
                        if score.piece == piece.slug {
                            Label(piece.name, systemImage: "checkmark")
                        } else {
                            Text(piece.name)
                        }
                    }
                }
                Divider()
                Button("New piece…") {
                    newPieceName = ""
                    newPieceTarget = score
                }
            }
            if score.piece != nil {
                Button("Remove from piece") {
                    state.assignToPiece(scoreSlug: score.slug, piece: nil)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            // non-destructive role: the row shouldn't vanish before the
            // confirmation alert is answered
            Button { pendingDelete = score } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    /// Trailing per-row icon button; borderless so it doesn't hijack the row
    /// tap, sized for a comfortable finger target.
    private func rowIcon(_ systemName: String, label: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundStyle(.secondary)
                .frame(minWidth: 32, minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    private func sourceCountLabel(_ score: ScoreDoc) -> String {
        let n = score.sources?.count ?? 0
        return n > 0 ? " · \(n) source\(n == 1 ? "" : "s")" : ""
    }

    // MARK: detail

    @ViewBuilder
    private var detail: some View {
        if let score = state.selectedScore {
            Group {
                if hSize == .compact {
                    // iPhone: chat replaces the score pane instead of squeezing it
                    if showChat { ChatView() } else { scorePane(score) }
                } else {
                    HStack(spacing: 0) {
                        scorePane(score)
                        if showChat {
                            Divider()
                            ChatView()
                                .frame(width: 360)
                        }
                    }
                }
            }
            .onAppear {
                if !didSetInitialChat {
                    didSetInitialChat = true
                    if hSize == .compact { showChat = false }
                }
            }
            .navigationTitle(score.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { detailToolbar }
        } else {
            ContentUnavailableView(
                "No score selected",
                systemImage: "music.quarternote.3",
                description: Text(!state.engineOK && !state.useLocalEngine
                    ? "Engine unreachable — check the URL in Settings and that `scor serve` is running on your Mac."
                    : "Tap + to import a MusicXML or MIDI file."))
        }
    }

    @ViewBuilder
    private func scorePane(_ score: ScoreDoc) -> some View {
        ZStack {
            if let doc = state.pdfDocument, let vid = state.displayedVersionID {
                if hSize == .compact {
                    // iPhone: zoomable read-only view; pencil markup is iPad-only
                    ScoreZoomView(document: doc)
                } else {
                    ScorePagesView(document: doc, annotationKey: "\(score.slug)/\(vid)")
                }
            } else if state.loadingPDF {
                ProgressView("Engraving…")
            } else if let err = state.lastError {
                ContentUnavailableView("Render failed", systemImage: "exclamationmark.triangle",
                                       description: Text(err))
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            versionsMenu
            gearMenu
            Button { showChat.toggle() } label: {
                Label("Chat", systemImage: showChat ? "sidebar.trailing" : "bubble.left.and.text.bubble.right")
            }
        }
    }

    /// Version picker mirroring the sidebar's Versions section, so version
    /// hopping works without opening the sidebar (essential on iPhone).
    @ViewBuilder
    private var versionsMenu: some View {
        if let score = state.selectedScore {
            Menu {
                ForEach(score.versions.reversed()) { v in
                    Button {
                        state.pinnedVersion = (v.id == score.latest) ? nil : v.id
                        Task { await state.renderIfNeeded() }
                    } label: {
                        if v.id == state.displayedVersionID {
                            Label("\(v.id) · \(v.op)", systemImage: "checkmark")
                        } else {
                            Text("\(v.id) · \(v.op)")
                        }
                    }
                }
            } label: {
                Text(state.displayedVersionID ?? "")
                    .font(.system(.caption, design: .monospaced))
            }
            .accessibilityLabel("Versions")
        }
    }

    private var gearMenu: some View {
        Menu {
            Button { state.transpose(semitones: 1) } label: {
                Label("Transpose up a semitone", systemImage: "arrow.up")
            }
            Button { state.transpose(semitones: -1) } label: {
                Label("Transpose down a semitone", systemImage: "arrow.down")
            }
            Toggle("Use flats", isOn: Binding(
                get: { state.useFlats[state.selectedScore?.slug ?? "", default: true] },
                set: { newValue in
                    if let slug = state.selectedScore?.slug {
                        state.useFlats[slug] = newValue
                    }
                    state.respell(preferFlats: newValue)
                }
            ))
            if hSize != .compact {
                Button {
                    if let score = state.selectedScore, let vid = state.displayedVersionID {
                        DrawingStore.shared.clear(prefix: "\(score.slug)/\(vid)")
                        // force page reload to drop canvases' in-memory drawings
                        Task { await state.renderIfNeeded(force: true) }
                    }
                } label: {
                    Label("Clear markup", systemImage: "pencil.slash")
                }
            }
        } label: {
            Label("Score options", systemImage: "gearshape")
        }
    }
}
