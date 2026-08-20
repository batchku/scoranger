import SwiftUI

/// Metadata sheet for a score: overview (including its piece, editable via a
/// menu), the latest version's parts, the version history, and any attached
/// sources. Everything shown comes from the manifest's ScoreDoc.
struct ScoreInfoView: View {
    let score: ScoreDoc
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    /// Local override so the Piece label updates immediately after a pick —
    /// the sheet's `score` is a snapshot and won't see the refreshed manifest.
    @State private var pieceOverride: String??
    /// Editable arrangement name. Seeded from the snapshot on appear; committed
    /// on submit or via the Rename button.
    @State private var draftName = ""
    /// The name as last persisted. `score` is a snapshot taken when the sheet
    /// opened and never sees the refreshed manifest, so comparing against it
    /// would leave the Rename button showing after a successful save.
    @State private var savedName = ""
    @State private var renaming = false
    @FocusState private var nameFocused: Bool

    private var trimmedDraft: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Only offer Rename when there is a real, different name to save.
    private var canRename: Bool {
        !trimmedDraft.isEmpty && trimmedDraft != savedName && !renaming
    }

    private func commitRename() {
        guard canRename else { return }
        let name = trimmedDraft
        renaming = true
        nameFocused = false
        Task {
            if await state.renameScore(slug: score.slug, name: name) {
                savedName = name
            }
            renaming = false
        }
    }

    private var currentPieceSlug: String? {
        if let pieceOverride { return pieceOverride }
        return score.piece
    }

    private func pieceName(_ slug: String?) -> String {
        guard let slug else { return "None" }
        return state.manifest?.pieces?.first { $0.slug == slug }?.name ?? slug
    }

    private var latestParts: [PartDoc] {
        score.versions.first { $0.id == score.latest }?.parts
            ?? score.versions.last?.parts
            ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Arrangement") {
                    // editable: renaming is label-only, so it needs no version
                    HStack {
                        TextField("Name", text: $draftName)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit(commitRename)
                            .accessibilityLabel("Arrangement name")
                        if renaming {
                            ProgressView().controlSize(.small)
                        } else if canRename {
                            Button("Rename", action: commitRename)
                                .buttonStyle(.borderless)
                                .font(.callout.weight(.semibold))
                        }
                    }
                    if let placement = state.placement(of: score.slug) {
                        LabeledContent("Number in piece") {
                            Text("#\(placement.number)")
                                .font(.body.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    if let title = score.title, !title.isEmpty {
                        LabeledContent("Title", value: title)
                    }
                    if let composer = score.composer, !composer.isEmpty {
                        LabeledContent("Composer", value: composer)
                    }
                    LabeledContent("Piece") {
                        Menu {
                            Button {
                                state.assignToPiece(scoreSlug: score.slug, piece: nil)
                                pieceOverride = .some(nil)
                            } label: {
                                if currentPieceSlug == nil {
                                    Label("None", systemImage: "checkmark")
                                } else {
                                    Text("None")
                                }
                            }
                            ForEach(state.manifest?.pieces ?? []) { piece in
                                Button {
                                    state.assignToPiece(scoreSlug: score.slug, piece: piece.slug)
                                    pieceOverride = .some(piece.slug)
                                } label: {
                                    if currentPieceSlug == piece.slug {
                                        Label(piece.name, systemImage: "checkmark")
                                    } else {
                                        Text(piece.name)
                                    }
                                }
                            }
                        } label: {
                            Text(pieceName(currentPieceSlug))
                        }
                    }
                    LabeledContent("Slug") {
                        Text(score.slug).font(.system(.caption, design: .monospaced))
                    }
                    if let latest = score.latest {
                        LabeledContent("Latest") {
                            Text(latest).font(.system(.caption, design: .monospaced))
                        }
                    }
                }
                if !latestParts.isEmpty {
                    Section("Scored for (latest version)") {
                        ForEach(latestParts, id: \.index) { part in
                            partRow(part)
                        }
                    }
                }
                Section("Versions (this arrangement's history)") {
                    ForEach(score.versions.reversed()) { v in
                        versionRow(v)
                    }
                }
                if let sources = score.sources, !sources.isEmpty {
                    Section("Sources (other editions of the piece)") {
                        ForEach(sources) { source in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(source.id)
                                        .font(.system(.caption, design: .monospaced))
                                    Text(source.name)
                                }
                                if let parts = source.parts, !parts.isEmpty {
                                    Text(parts.map(\.name).joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(savedName.isEmpty ? score.name : savedName)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                draftName = score.name
                savedName = score.name
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func partRow(_ part: PartDoc) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(part.name)
                Spacer()
                if let instrument = part.instrument, instrument != part.name {
                    Text(instrument)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            let detail = partDetail(part)
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func partDetail(_ part: PartDoc) -> String {
        var bits: [String] = []
        if let clefs = part.clefs, !clefs.isEmpty {
            bits.append(clefs.joined(separator: ", "))
        }
        if let range = part.range, range.count == 2 {
            bits.append("\(range[0])–\(range[1])")
        }
        if let measures = part.measures {
            bits.append("\(measures) measure\(measures == 1 ? "" : "s")")
        }
        if let notes = part.notes {
            bits.append("\(notes) note\(notes == 1 ? "" : "s")")
        }
        return bits.joined(separator: " · ")
    }

    private func versionRow(_ v: VersionDoc) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(v.id).font(.system(.caption, design: .monospaced))
                Text(v.op).font(.caption)
                Spacer()
                if v.id == score.latest {
                    Text("latest")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let time = v.time {
                Text(time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
