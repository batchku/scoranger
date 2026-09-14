import SwiftUI

/// A piece and its arrangements (NAV_MODAL_FREE_0.4.2 §3.1).
///
/// What the arrangement SHEET was. Pushed from a piece row's ☰, and from
/// tapping a piece that holds more than one arrangement -- because a piece is
/// not openable: opening one means opening one of its arrangements.
struct PieceScreen: View {
    @EnvironmentObject var state: AppState
    let piece: PieceDoc
    var onBack: () -> Void
    var onOpen: (String) -> Void
    var push: (Route) -> Void
    var onImport: (String) -> Void

    /// The arrangement row whose ☰ is open, its actions in the row (P2).
    @State private var openArrangement: String?
    @EnvironmentObject var panel: PanelModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Ph2's rule, on this page too: a phone has no column beside the page,
    /// so the page's own tools sit on one line at its foot. Without it the
    /// panel at rest -- "This piece" -- is not reachable on a phone at all
    /// now that a rest state no longer covers the page it belongs to.
    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        Screen(title: "", backLabel: "Library",
               subtitle: summary, onBack: onBack,
               trailing: {
                   PanelButton(title: "New arrangement", kind: .primary,
                               identifier: "piece-new-arrangement-\(piece.slug)") {
                       Task { _ = await state.createArrangement(pieceSlug: piece.slug) }
                   }
               }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Metric.s12) {
                    EditableTitle(text: piece.name, role: .title,
                                  identifier: "piece-title") { name in
                        Task { _ = await state.renamePiece(piece: piece.slug, name: name) }
                    }
                    Text(headMeta).typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                        .lineLimit(1)
                }
                .padding(.horizontal, Theme.Metric.pageSide)
                .padding(.top, Theme.Metric.s12)
                .padding(.bottom, Theme.Metric.s12)

                ForEach(Array(piece.arrangements.enumerated()), id: \.offset) { index, slug in
                    if let score = state.manifest?.scores.first(where: { $0.slug == slug }) {
                        arrangementRow(score, number: index + 1)
                        Theme.Rule()
                    }
                }
                if piece.arrangements.isEmpty {
                    Text("No arrangements yet. New arrangement starts an empty one; Import brings a file in.")
                        .typeRole(.body).foregroundStyle(Theme.Ink.ink2)
                        .padding(Theme.Metric.pageSide)
                }
            }
            .padding(.bottom, isCompact ? PageFootStrip.inset : Theme.Metric.s32)
        }
        .overlay(alignment: .bottom) {
            if isCompact {
                PageFootStrip(items: [
                    .init(id: "piece-tool-import", title: "Import",
                          glyph: "arrow.down.to.line") { onImport(piece.slug) },
                    .init(id: "piece-tool-more", title: "More") { push(.thisPiece(piece.slug)) },
                ])
            }
        }
    }

    /// "Hubert Giraud · 2 arrangements · in 1 set list"
    private var headMeta: String {
        var bits: [String] = []
        if let composer = piece.composer, !composer.isEmpty { bits.append(composer) }
        bits.append(summary)
        let lists = (state.manifest?.setlists ?? [])
            .filter { !$0.arrangements.filter(piece.arrangements.contains).isEmpty }.count
        if lists > 0 { bits.append("in \(lists) set list" + (lists == 1 ? "" : "s")) }
        return bits.joined(separator: " · ")
    }

    private var labels: [String: String] {
        let scores = piece.arrangements.compactMap { slug in
            state.manifest?.scores.first { $0.slug == slug }
        }
        let shown = ScoreTitle.labels(for: scores.map { score in
            ScoreTitle.Arrangement(
                title: score.title, name: score.name, slug: score.slug,
                parts: (score.versions.last?.parts ?? []).map(\.name),
                isScan: ArtifactTag.holding(of: score) == .pdf)
        })
        return Dictionary(uniqueKeysWithValues: zip(scores.map(\.slug), shown))
    }

    private func label(_ score: ScoreDoc) -> String {
        labels[score.slug] ?? ScoreTitle.arrangementName(title: score.title,
                                                         name: score.name,
                                                         slug: score.slug)
    }

    /// Spelled out rather than built inline: as one `+` chain in the modifier
    /// the type checker gave up on the whole row.
    private func arrangementLabel(_ score: ScoreDoc, number: Int) -> String {
        let name = label(score)
        let count = score.versions.count
        let versions = "\(count) version" + (count == 1 ? "" : "s")
        let format = ArtifactTag.holding(of: score).map { ArtifactTag.label($0) }
        return (["Arrangement number \(number)", name, versions] + (format.map { [$0] } ?? []))
            .joined(separator: ", ")
    }

    private func arrangementRow(_ score: ScoreDoc, number: Int) -> some View {
        let open = openArrangement == score.slug
        return HStack(spacing: Theme.Metric.s12) {
            HStack(spacing: Theme.Metric.s12) {
                    NumeralBadge(number: number)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(label(score)).typeRole(.titleS)
                            .foregroundStyle(Theme.Ink.ink).lineLimit(1)
                        if open {
                            RowActionsBar(actions: arrangementActions(score, number: number))
                        } else {
                            HStack(spacing: Theme.Metric.s4) {
                                Text(arrangementMeta(score))
                                    .typeRole(.meta).foregroundStyle(Theme.Ink.ink3).lineLimit(1)
                                ForEach(Array(ArtifactTag.chips(
                                                files: score.versions.map(\.file))
                                                .enumerated()), id: \.offset) { _, chip in
                                    DerivedChip(chip: chip)
                                }
                            }
                        }
                    }
                    Spacer()
            }
            .rowTappable(label: arrangementLabel(score, number: number),
                         identifier: "arrangement-choice-\(score.slug)",
                         isSelected: state.selectedSlug == score.slug,
                         container: open) { onOpen(score.slug) }

            if !open {
                // Beside a panel on a narrow page the date and Open give way
                // [C8]: the row itself still opens, and ☰ stays.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Metric.s12) {
                        Text(LibraryModel.day(score.versions.last?.time ?? nil))
                            .typeRole(.data).foregroundStyle(Theme.Ink.ink3).lineLimit(1)
                        PanelButton(title: "Open", identifier: "arrangement-open-\(score.slug)") {
                            onOpen(score.slug)
                        }
                    }
                    .fixedSize()
                    PanelButton(title: "Open", identifier: "arrangement-open-\(score.slug)") {
                        onOpen(score.slug)
                    }
                    .fixedSize()
                    Color.clear.frame(width: 0, height: 0)
                }
            }
            RowMenuButton(identifier: "row-menu-\(score.slug)",
                          label: open ? "Close \(label(score))'s actions" : "Manage \(label(score))",
                          isOpen: open) {
                if open { openArrangement = nil; panel.done() } else { openArrangement = score.slug }
            }
        }
        .padding(.horizontal, Theme.Metric.pageSide)
        .padding(.vertical, Theme.Metric.s8)
        .frame(minHeight: 64)
        // [C4]: the open row is a flat tint band the width of the page.
        .background(open ? Theme.Accent.clayTint : Color.clear)
    }

    /// "v003 · 4 parts · Tuesday at the Ship"
    private func arrangementMeta(_ score: ScoreDoc) -> String {
        var bits: [String] = []
        if let latest = score.versions.last { bits.append(latest.name) }
        let parts = score.versions.last?.parts?.count ?? 0
        bits.append("\(parts) part" + (parts == 1 ? "" : "s"))
        let lists = (state.manifest?.setlists ?? []).filter { $0.arrangements.contains(score.slug) }
        if let first = lists.first { bits.append(first.name) }
        return bits.joined(separator: " · ")
    }

    /// P2: Up, Down, Duplicate, Move to piece, Arrangement, Delete.
    private func arrangementActions(_ score: ScoreDoc, number: Int) -> [RowActionItem] {
        [
            RowActionItem(id: "arr-up-\(score.slug)", title: "Up", glyph: "chevron.up",
                          enabled: number > 1) { move(score.slug, by: -1) },
            RowActionItem(id: "arr-down-\(score.slug)", title: "Down", glyph: "chevron.down",
                          enabled: number < piece.arrangements.count) { move(score.slug, by: 1) },
            RowActionItem(id: "arrangement-duplicate-\(score.slug)", title: "Duplicate") {
                Task { _ = await state.duplicateScore(slug: score.slug) }
            },
            RowActionItem(id: "arrangement-move-\(score.slug)", title: "Move to piece",
                          lit: panel.isShowing(.moveToPiece([score.slug]))) {
                panel.toggle(.moveToPiece([score.slug]))
            },
            RowActionItem(id: "arrangement-manage-\(score.slug)", title: "Arrangement",
                          lit: panel.isShowing(.arrangement(score.slug))) {
                panel.toggle(.arrangement(score.slug))
            },
            RowActionItem(id: "edit-delete-\(score.slug)", title: "Delete", destructive: true,
                          confirm: "Delete?") {
                openArrangement = nil
                state.deleteScore(slug: score.slug)
            },
        ]
    }

    private func orderButton(_ glyph: String, label: String, id: String,
                             enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Ink.ink2)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
    }

    /// Move an arrangement within its piece. #N is a position, so this
    /// renumbers -- which is the whole point of the control.
    private func move(_ slug: String, by delta: Int) {
        var order = piece.arrangements
        guard let from = order.firstIndex(of: slug) else { return }
        let to = from + delta
        guard order.indices.contains(to) else { return }
        order.swapAt(from, to)
        state.reorderPiece(piece: piece.slug, order: order)
    }

    private var summary: String {
        let n = piece.arrangements.count
        return "\(n) arrangement\(n == 1 ? "" : "s")"
    }

}

/// One arrangement's actions — the per-item screen a row's ☰ opens (§3.2).
///
/// Grouped by intent, and every row states its current answer, so the screen
/// reads as a summary as well as a menu: you often do not need to go deeper.
struct ArrangementScreen: View {
    @EnvironmentObject var state: AppState
    let score: ScoreDoc
    var onBack: () -> Void
    var onOpen: () -> Void
    var push: (Route) -> Void

    @State private var confirmingDelete = false

    var body: some View {
        Screen(title: "Arrangement", backLabel: "Back",
               subtitle: placement, onBack: onBack,
               trailing: {
                   PanelButton(title: "Open", kind: .primary, action: onOpen)
                       .accessibilityIdentifier("arrangement-open")
               }) {
            VStack(alignment: .leading, spacing: 0) {
                EditableTitle(text: ScoreTitle.arrangementName(title: score.title,
                                                              name: score.name,
                                                              slug: score.slug),
                              role: .title,
                              identifier: "arrangement-title") { name in
                    Task { _ = await state.renameScore(slug: score.slug, name: name) }
                }
                .padding(.horizontal, Theme.Metric.s20)
                .padding(.top, Theme.Metric.s12)
                .padding(.bottom, Theme.Metric.s8)

                ScreenRow(title: "Piece", value: pieceName ?? "unfiled",
                          identifier: "arrangement-move-\(score.slug)") {
                    push(.moveToPiece([score.slug]))
                }
                ScreenRow(title: "Set lists", value: setlistSummary,
                          identifier: "arrangement-setlists-\(score.slug)") {
                    push(.setlistsFor(score.slug))
                }
                ScreenRow(title: "Duplicate", leads: false,
                          identifier: "arrangement-duplicate-\(score.slug)") {
                    Task { _ = await state.duplicateScore(slug: score.slug) }
                }

                ScreenRow(title: "Versions", value: "\(score.versions.count)",
                          identifier: "edit-versions-\(score.slug)") {
                    push(.versions(score.slug))
                }
                ScreenRow(title: "Parts",
                          value: "\(score.versions.last?.parts?.count ?? 0)",
                          identifier: "arrangement-parts-\(score.slug)") {
                    push(.parts(score.slug))
                }
                ScreenRow(title: "Details", identifier: "row-details-\(score.slug)") {
                    push(.details(score.slug))
                }

                PanelLabel(text: "Careful")
                if confirmingDelete {
                    ConfirmDeleteStrip(what: deleteWarning,
                                       consequence: "Every version goes with it; the piece and its other arrangements stay.",
                                       identifier: "confirm-delete-\(score.slug)",
                                       onDelete: {
                                           confirmingDelete = false
                                           state.deleteScore(slug: score.slug)
                                           onBack()
                                       },
                                       onKeep: { confirmingDelete = false })
                } else {
                    ScreenRow(title: "Delete arrangement", leads: false,
                              isDestructive: true,
                              identifier: "edit-delete-\(score.slug)") {
                        confirmingDelete = true
                    }
                }
            }
            .padding(.bottom, Theme.Metric.s32)
        }
    }

    private var placement: String? {
        guard let p = state.placement(of: score.slug) else { return "unfiled" }
        return "\(p.piece.name) · #\(p.number)"
    }

    private var pieceName: String? { state.placement(of: score.slug)?.piece.name }

    /// Shared with the score's Options screen, which leads to the same screen
    /// by the same name (§16).
    private var setlistSummary: String {
        SetlistMembership.rowValue(for: score.slug,
                                   in: state.manifest?.setlists ?? [])
    }

    private var deleteWarning: String {
        let n = score.versions.count
        return "Delete \(ScoreTitle.arrangementName(title: score.title, name: score.name, slug: score.slug)) and its \(n) version"
            + (n == 1 ? "?" : "s?")
    }

}

/// The one control a row carries (§2, §4). Visible, labelled, never a long
/// press.
struct RowMenuButton: View {
    /// The bordered square itself, inside a full hit target.
    static let side: CGFloat = 34

    var identifier: String
    var label: String
    var isOpen: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            // ☰ becomes ✕ while the row's actions are open (§7.3).
            Image(systemName: isOpen ? "xmark" : "line.3.horizontal")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isOpen ? Theme.Accent.clayStrong : Theme.Ink.ink2)
                // A BUTTON, like every other icon in the app. It was a naked
                // glyph sitting in the row's trailing edge, so the one control
                // a row carries did not look like a control at all.
                .frame(width: RowMenuButton.side, height: RowMenuButton.side)
                .background(isOpen ? Theme.Surface.paper : Theme.Surface.well)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
                .frame(width: Theme.Metric.hitTarget, height: Theme.Metric.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOpen ? [.isSelected] : [])
    }
}


/// One editable line of a piece's metadata.
///
/// Separate from `EditableTitle` for one reason: a name cannot be empty, and
/// these can. Clearing a composer is a thing a person does -- the credit was
/// wrong, or it was never a composer in the first place -- so an empty commit
/// has to reach the engine rather than be swallowed as "no change".
struct PieceField: View {
    let label: String
    let value: String
    var hint: String = ""
    var identifier: String
    var onCommit: (String) -> Void

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Metric.s12) {
            Text(label).typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                .frame(width: 82, alignment: .leading)
            if editing {
                TextField(hint.isEmpty ? label : hint, text: $draft)
                    .typeRole(.row).foregroundStyle(Theme.Ink.ink)
                    .tint(Theme.Accent.clay).textFieldStyle(.plain)
                    .focused($focused).submitLabel(.done)
                    .onSubmit { commit() }
                    .accessibilityIdentifier("\(identifier)-field")
            } else {
                Text(value.isEmpty ? "—" : value)
                    .typeRole(.row)
                    .foregroundStyle(value.isEmpty ? Theme.Ink.ink3 : Theme.Ink.ink)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Theme.Metric.s20)
        .frame(minHeight: Theme.Metric.hitTarget)
        .contentShape(Rectangle())
        .accessibilityIdentifier(identifier)
        .onTapGesture {
            guard !editing else { return }
            draft = value
            editing = true
            focused = true
        }
        .onChange(of: focused) { _, now in if !now && editing { commit() } }
    }

    private func commit() {
        editing = false
        focused = false
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != value { onCommit(trimmed) }
    }
}
