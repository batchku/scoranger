import SwiftUI

/// The arrangement details body. Its screen supplies the
/// frame, the numeral, the title and Done; this is band headers and rows.
/// Destructive actions sit in the body, last, never in the header.
///
/// It is also where an arrangement's metadata is edited. There is one title,
/// not several: what the sidebar shows, what this sheet shows, and what is
/// engraved at the top of the page are the same value, and saving writes all
/// of them through the engine's `set-metadata` op (a new version, like any
/// other change to the notation).
struct ScoreInfoView: View {
    /// The score as it was when the sheet opened. Everything reads `live`
    /// instead: the sheet edits the arrangement, so it has to show the results
    /// of its own edits — the new version, the new title, the new piece.
    let score: ScoreDoc
    @EnvironmentObject var state: AppState

    /// The slug the sheet is currently looking at. Normally the one it opened
    /// with — but the slug is editable here, and after a move the opening
    /// snapshot no longer matches anything in the manifest.
    @State private var currentSlug: String?

    private var live: ScoreDoc {
        let slug = currentSlug ?? score.slug
        return state.manifest?.scores.first { $0.slug == slug } ?? score
    }

    @State private var draftTitle = ""
    @State private var draftComposer = ""
    @State private var draftArranger = ""
    /// What was last persisted; comparing against the snapshot would leave the
    /// Save button showing after a successful write.
    @State private var saved = AppState.ScoreMetadata()
    @State private var saving = false
    /// The metadata the notation actually carries, read from the engine. For
    /// scores imported before the fields were reconciled this can differ from
    /// the library name — the note below says so, and one save fixes it.
    @State private var engraved: AppState.ScoreMetadata?
    @State private var renamingPart: Int?
    @State private var draftPartName = ""
    @State private var confirmingDelete = false
    @State private var pieceListOpen = false
    @State private var draftSlug = ""
    @State private var savedSlug = ""
    @State private var renamingSlug = false

    private func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSave: Bool {
        guard !saving, !trimmed(draftTitle).isEmpty else { return false }
        return trimmed(draftTitle) != (saved.title ?? "")
            || trimmed(draftComposer) != (saved.composer ?? "")
            || trimmed(draftArranger) != (saved.arranger ?? "")
    }
    /// The page says something other than the arrangement's name (an import
    /// from before the two were one field).
    private var engravedMismatch: String? {
        guard let engravedTitle = engraved?.title, !engravedTitle.isEmpty,
              engravedTitle != trimmed(draftTitle) else { return nil }
        return engravedTitle
    }
    private var canRenameSlug: Bool {
        let want = trimmed(draftSlug)
        return !renamingSlug && !want.isEmpty && want != savedSlug
    }
    private var currentPieceSlug: String? { live.piece }
    private var currentPiece: PieceDoc? {
        state.manifest?.pieces?.first { $0.slug == currentPieceSlug }
    }
    private func pieceName(_ slug: String?) -> String {
        guard let slug else { return "None" }
        return state.manifest?.pieces?.first { $0.slug == slug }?.name ?? slug
    }
    private var latestParts: [PartDoc] {
        let doc = live
        return doc.versions.first { $0.id == doc.latest }?.parts
            ?? doc.versions.last?.parts ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BandHeader("Arrangement")
            metadataEditor
            SheetRow(label: "Piece") { pieceMenu }
            slugEditor
            if let latest = live.latest {
                SheetRow("Latest version", latest, mono: true)
            }

            if !latestParts.isEmpty {
                BandHeader("Scored for")
                ForEach(latestParts, id: \.index) { part in
                    partRow(part)
                }
            }

            BandHeader("Versions")
            ForEach(live.versions.reversed()) { version in
                SheetRow(label: version.id) {
                    HStack(spacing: Theme.Metric.s8) {
                        Text(version.op).typeRole(.meta).foregroundStyle(Theme.Ink.ink)
                        if version.id == live.latest {
                            Text("latest").typeRole(.dataS)
                                .foregroundStyle(Theme.Accent.clayStrong)
                        }
                    }
                }
            }

            if let sources = live.sources, !sources.isEmpty {
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
        .task { await load() }
    }

    // MARK: - Metadata

    @ViewBuilder
    private var metadataEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.s12) {
            // One title. It is what the page engraves, what the sidebar lists
            // and what the sheet header says — there is no second title-ish
            // field to reconcile it against.
            LabeledField("Title", text: $draftTitle, identifier: "arrangement-title")
            LabeledField("Composer", text: $draftComposer,
                         identifier: "arrangement-composer")
            LabeledField("Arranger", text: $draftArranger,
                         identifier: "arrangement-arranger")
            if let engravedTitle = engravedMismatch {
                PanelNote(text: "The page still engraves \u{201C}\(engravedTitle)\u{201D}. "
                          + "Saving makes the title on the score the same as this one.")
            }
            HStack(spacing: Theme.Metric.s8) {
                if let placement = state.placement(of: score.slug) {
                    Text("Number in piece").typeRole(.body)
                        .foregroundStyle(Theme.Ink.ink2)
                    NumeralBadge(number: placement.number)
                }
                Spacer(minLength: Theme.Metric.s8)
                if saving {
                    ProgressView().controlSize(.small).tint(Theme.Accent.clay)
                } else if canSave {
                    PanelButton(title: "Save", kind: .primary, action: commitMetadata)
                        .accessibilityIdentifier("save-metadata")
                }
            }
        }
        .padding(Theme.Metric.panelPadding)
    }

    /// The slug is the arrangement's handle: its folder on disk, the ref chat
    /// uses for a sibling arrangement. Auto-generated ones can be ugly, so it
    /// is editable — but it is a move, not a rename, so it saves on its own
    /// rather than riding along with the title.
    @ViewBuilder
    private var slugEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledField(label: "Slug", text: $draftSlug, isMono: true,
                         identifier: "arrangement-slug") {
                if renamingSlug {
                    ProgressView().controlSize(.small).tint(Theme.Accent.clay)
                } else if canRenameSlug {
                    PanelButton(title: "Move", kind: .primary, action: commitSlug)
                        .accessibilityIdentifier("save-slug")
                }
            }
            PanelNote(text: "The handle this arrangement is filed under, and how "
                      + "chat refers to it (arr:\(savedSlug)). Letters, numbers "
                      + "and dashes; anything else is folded into dashes.")
        }
        .padding(.horizontal, Theme.Metric.panelPadding)
        .padding(.vertical, Theme.Metric.s12)
    }

    @ViewBuilder
    private var pieceMenu: some View {
        // An inline reveal, not a menu (NAV_MODAL_FREE_0.4.2 §2): the pieces
        // expand under the row and a tap commits. Nothing floats, and the list
        // is short enough that it does not need a screen of its own.
        VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: Theme.Metric.s8) {
            Button { pieceListOpen.toggle() } label: {
                HStack(spacing: 4) {
                    Text(pieceName(currentPieceSlug))
                        .typeRole(.body)
                        .foregroundStyle(Theme.Accent.clayStrong)
                    Image(systemName: pieceListOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Ink.ink3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("piece-menu")
            if let piece = currentPiece {
                // the name is the control: tap it to rename, no pencil button
                EditableTitle(text: piece.name, role: .body,
                              identifier: "rename-piece") { name in
                    Task { await state.renamePiece(piece: piece.slug, name: name) }
                }
            }
            Spacer(minLength: 0)
        }
        if pieceListOpen {
            VStack(alignment: .leading, spacing: 0) {
                pieceChoice(name: "None", slug: nil)
                ForEach(state.manifest?.pieces ?? []) { piece in
                    pieceChoice(name: piece.name, slug: piece.slug)
                }
            }
            .padding(.top, Theme.Metric.s6)
        }
        }
    }

    private func pieceChoice(name: String, slug: String?) -> some View {
        Button {
            state.assignToPiece(scoreSlug: score.slug, piece: slug)
            pieceListOpen = false
        } label: {
            HStack(spacing: Theme.Metric.s6) {
                Image(systemName: currentPieceSlug == slug ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(currentPieceSlug == slug ? Theme.Accent.clayStrong
                                                              : Theme.Ink.ink3)
                Text(name).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                Spacer()
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("piece-choice-\(slug ?? "none")")
    }

    // MARK: - Parts

    /// A part row, tappable to rename. The name is the staff label engraved on
    /// every system, so renaming goes through the engine's `rename-part` op.
    @ViewBuilder
    private func partRow(_ part: PartDoc) -> some View {
        if renamingPart == part.index {
            EditableTitle(text: part.name, role: .row,
                          identifier: "part-name",
                          startEditing: true,
                          onCommit: { name in
                              renamingPart = nil
                              let wanted = trimmed(name)
                              guard !wanted.isEmpty, wanted != part.name else { return }
                              Task { await state.renamePart(slug: score.slug,
                                                            part: "#\(part.index)",
                                                            name: wanted) }
                          })
                .padding(.horizontal, Theme.Metric.panelPadding)
                .padding(.vertical, Theme.Metric.s8)
        } else {
            // ScreenRow, like every other row on a pushed screen. It collapses
            // to ONE accessibility element, so a tap reaches the button rather
            // than the stack inside it -- the hand-rolled Button here was
            // findable and untappable, which is the container trap this project
            // has now debugged four separate times.
            ScreenRow(title: part.name,
                      value: partDetail(part),
                      leads: false,
                      identifier: "part-\(part.index)") {
                draftPartName = part.name
                renamingPart = part.index
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

    // MARK: - Load and save

    private func load() async {
        let fromNotation = await state.scoreMetadata(slug: score.slug)
        engraved = fromNotation
        // The library name wins as the editable value: it is what the user
        // named this arrangement. The credits only exist in the notation.
        let doc = live
        draftTitle = doc.name
        draftComposer = fromNotation?.composer ?? doc.composer ?? ""
        draftArranger = fromNotation?.arranger ?? ""
        saved = AppState.ScoreMetadata(title: draftTitle,
                                       composer: draftComposer,
                                       arranger: draftArranger)
        currentSlug = doc.slug
        draftSlug = doc.slug
        savedSlug = doc.slug
    }

    private func commitSlug() {
        guard canRenameSlug else { return }
        let want = trimmed(draftSlug)
        renamingSlug = true
        Task {
            if let now = await state.renameSlug(slug: live.slug, to: want) {
                currentSlug = now    // everything the sheet reads follows the move
                draftSlug = now      // the engine normalizes; show what it used
                savedSlug = now
            } else {
                draftSlug = savedSlug
            }
            renamingSlug = false
        }
    }

    private func commitMetadata() {
        guard canSave else { return }
        let title = trimmed(draftTitle)
        let composer = trimmed(draftComposer)
        let arranger = trimmed(draftArranger)
        saving = true
        Task {
            // one call, so one new version carries the whole edit
            let ok = await state.setScoreMetadata(
                slug: score.slug,
                title: title == (saved.title ?? "") ? nil : title,
                composer: composer == (saved.composer ?? "") ? nil : composer,
                arranger: arranger == (saved.arranger ?? "") ? nil : arranger)
            if ok {
                saved = AppState.ScoreMetadata(title: title, composer: composer,
                                               arranger: arranger)
                engraved = await state.scoreMetadata(slug: score.slug)
            }
            saving = false
        }
    }
}
