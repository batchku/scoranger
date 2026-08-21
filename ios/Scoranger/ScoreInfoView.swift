import SwiftUI

/// The arrangement sheet's body (§8 screen 07). `PanelSheet` supplies the
/// frame, the numeral, the title and Done; this is band headers and rows.
/// Destructive actions sit in the body, last, never in the header.
struct ScoreInfoView: View {
    let score: ScoreDoc
    @EnvironmentObject var state: AppState

    /// Local override so the piece row updates immediately after a pick — the
    /// sheet's `score` is a snapshot and never sees the refreshed manifest.
    @State private var pieceOverride: String??
    @State private var draftName = ""
    /// The name as last persisted; comparing against the snapshot would leave
    /// the Rename button showing after a successful save.
    @State private var savedName = ""
    @State private var renaming = false
    @State private var confirmingDelete = false

    private var trimmedDraft: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canRename: Bool {
        !trimmedDraft.isEmpty && trimmedDraft != savedName && !renaming
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
            ?? score.versions.last?.parts ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BandHeader("Arrangement")
            VStack(alignment: .leading, spacing: Theme.Metric.s12) {
                HStack(spacing: Theme.Metric.s8) {
                    PanelField(placeholder: "Name", text: $draftName)
                        .accessibilityLabel("Arrangement name")
                    if renaming {
                        ProgressView().controlSize(.small).tint(Theme.Accent.clay)
                    } else if canRename {
                        PanelButton(title: "Rename", kind: .primary, action: commitRename)
                    }
                }
                if let placement = state.placement(of: score.slug) {
                    HStack(spacing: Theme.Metric.s8) {
                        Text("Number in piece").typeRole(.body)
                            .foregroundStyle(Theme.Ink.ink2)
                        Spacer()
                        NumeralBadge(number: placement.number)
                    }
                }
            }
            .padding(Theme.Metric.panelPadding)

            SheetRow(label: "Piece") {
                Menu {
                    Button {
                        state.assignToPiece(scoreSlug: score.slug, piece: nil)
                        pieceOverride = .some(nil)
                    } label: {
                        currentPieceSlug == nil
                            ? Label("None", systemImage: "checkmark") : Label("None", systemImage: "")
                    }
                    ForEach(state.manifest?.pieces ?? []) { piece in
                        Button {
                            state.assignToPiece(scoreSlug: score.slug, piece: piece.slug)
                            pieceOverride = .some(piece.slug)
                        } label: {
                            if currentPieceSlug == piece.slug {
                                Label(piece.name, systemImage: "checkmark")
                            } else { Text(piece.name) }
                        }
                    }
                } label: {
                    Text(pieceName(currentPieceSlug))
                        .typeRole(.body)
                        .foregroundStyle(Theme.Accent.clayStrong)
                }
            }
            if let title = score.title, !title.isEmpty {
                SheetRow("Title", title)
            }
            if let composer = score.composer, !composer.isEmpty {
                SheetRow("Composer", composer)
            }
            SheetRow("Slug", score.slug, mono: true)
            if let latest = score.latest {
                SheetRow("Latest version", latest, mono: true)
            }

            if !latestParts.isEmpty {
                BandHeader("Scored for")
                ForEach(latestParts, id: \.index) { part in
                    partRow(part)
                }
            }

            BandHeader("Versions")
            ForEach(score.versions.reversed()) { version in
                SheetRow(label: version.id) {
                    HStack(spacing: Theme.Metric.s8) {
                        Text(version.op).typeRole(.meta).foregroundStyle(Theme.Ink.ink)
                        if version.id == score.latest {
                            Text("latest").typeRole(.dataS)
                                .foregroundStyle(Theme.Accent.clayStrong)
                        }
                    }
                }
            }

            if let sources = score.sources, !sources.isEmpty {
                BandHeader("Sources")
                ForEach(sources) { source in
                    SheetRow(label: source.id) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(source.name).typeRole(.body)
                                .foregroundStyle(Theme.Ink.ink)
                            if let parts = source.parts, !parts.isEmpty {
                                Text(parts.map(\.name).joined(separator: ", "))
                                    .typeRole(.meta)
                                    .foregroundStyle(Theme.Ink.ink3)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            // destructive last, in the body (§7.15)
            BandHeader("Danger")
            VStack(alignment: .leading, spacing: Theme.Metric.s8) {
                if confirmingDelete {
                    PanelNote(text: "This removes the arrangement and all its versions. The piece and its other arrangements are untouched.")
                    HStack(spacing: Theme.Metric.s8) {
                        PanelButton(title: "Cancel") { confirmingDelete = false }
                        PanelButton(title: "Delete arrangement", kind: .destructive) {
                            state.deleteScore(slug: score.slug)
                        }
                    }
                } else {
                    PanelButton(title: "Delete arrangement…") { confirmingDelete = true }
                }
            }
            .padding(Theme.Metric.panelPadding)
        }
        .onAppear {
            draftName = score.name
            savedName = score.name
        }
    }

    private func partRow(_ part: PartDoc) -> some View {
        SheetRow(label: part.name) {
            VStack(alignment: .trailing, spacing: 1) {
                if let instrument = part.instrument, instrument != part.name {
                    Text(instrument).typeRole(.body).foregroundStyle(Theme.Ink.ink)
                }
                Text(partDetail(part)).typeRole(.data)
                    .foregroundStyle(Theme.Ink.ink2)
            }
        }
    }

    /// Clefs, range, bars and note count — all machine values, so all mono.
    private func partDetail(_ part: PartDoc) -> String {
        var bits: [String] = []
        if let clefs = part.clefs, !clefs.isEmpty { bits.append(clefs.joined(separator: ", ")) }
        if let range = part.range, range.count == 2 { bits.append("\(range[0])–\(range[1])") }
        if let measures = part.measures { bits.append("\(measures) bars") }
        if let notes = part.notes { bits.append("\(notes) notes") }
        return bits.joined(separator: " · ")
    }

    private func commitRename() {
        guard canRename else { return }
        let name = trimmedDraft
        renaming = true
        Task {
            if await state.renameScore(slug: score.slug, name: name) { savedName = name }
            renaming = false
        }
    }
}
