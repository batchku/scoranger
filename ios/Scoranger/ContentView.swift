import SwiftUI

import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var showChat = true
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var didSetInitialChat = false

    private static let scoreTypes: [UTType] = ([
        UTType(filenameExtension: "musicxml"),
        UTType(filenameExtension: "mxl"),
        UTType(filenameExtension: "xml"),
        UTType(filenameExtension: "mid"),
        UTType(filenameExtension: "midi"),
    ].compactMap { $0 }) + [.pdf]

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .task {
            state.startPolling()
        }
    }

    // MARK: sidebar

    private var sidebar: some View {
        List(selection: Binding(
            get: { state.selectedScore?.slug },
            set: { if let slug = $0 { state.select(slug: slug) } }
        )) {
            Section("Scores") {
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
                ForEach(state.manifest?.scores ?? []) { score in
                    // Button, not bare List selection: selection-only rows
                    // ignore taps in compact width (iPhone)
                    Button {
                        state.select(slug: score.slug)
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
                    .tag(score.slug)
                }
            }
            if let score = state.selectedScore {
                Section("Versions") {
                    ForEach(score.versions.reversed()) { v in
                        Button {
                            state.pinnedVersion = (v.id == score.latest) ? nil : v.id
                            Task { await state.renderIfNeeded() }
                        } label: {
                            HStack {
                                Text(v.id).font(.system(.caption, design: .monospaced))
                                Text(v.op).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                if v.id == state.displayedVersionID {
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
