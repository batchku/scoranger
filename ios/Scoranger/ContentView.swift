import SwiftUI

import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var showChat = true
    @State private var showSettings = false
    @State private var showImporter = false

    private static let scoreTypes: [UTType] = [
        UTType(filenameExtension: "musicxml"),
        UTType(filenameExtension: "mxl"),
        UTType(filenameExtension: "xml"),
        UTType(filenameExtension: "mid"),
        UTType(filenameExtension: "midi"),
    ].compactMap { $0 }

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
                ForEach(state.manifest?.scores ?? []) { score in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(score.name)
                        Text("\(score.versions.count) versions\(sourceCountLabel(score))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
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
            if case .success(let url) = result { state.importScore(from: url) }
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
            HStack(spacing: 0) {
                scorePane(score)
                if showChat {
                    Divider()
                    ChatView()
                        .frame(width: 360)
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
                ScorePagesView(document: doc, annotationKey: "\(score.slug)/\(vid)")
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
            Button { state.transpose(semitones: -1) } label: {
                Label("Down a semitone", systemImage: "arrow.down")
            }
            Button { state.transpose(semitones: 1) } label: {
                Label("Up a semitone", systemImage: "arrow.up")
            }
            Button {
                if let score = state.selectedScore, let vid = state.displayedVersionID {
                    DrawingStore.shared.clear(prefix: "\(score.slug)/\(vid)")
                    // force page reload to drop canvases' in-memory drawings
                    Task { await state.renderIfNeeded(force: true) }
                }
            } label: {
                Label("Clear markup", systemImage: "pencil.slash")
            }
            Button { showChat.toggle() } label: {
                Label("Chat", systemImage: showChat ? "sidebar.trailing" : "bubble.left.and.text.bubble.right")
            }
        }
    }
}
