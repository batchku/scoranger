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

    @State private var confirmingDelete = false

    var body: some View {
        Screen(title: "", backLabel: "My library",
               subtitle: summary, onBack: onBack) {
            VStack(alignment: .leading, spacing: 0) {
                // The name IS the control: tap it to rename. There is no
                // Rename button, because a button whose only job is to let you
                // edit the thing beside it exists only because the thing was
                // not tappable.
                EditableTitle(text: piece.name, role: .title,
                              identifier: "piece-title") { name in
                    Task { _ = await state.renamePiece(piece: piece.slug, name: name) }
                }
                .padding(.horizontal, Theme.Metric.s20)
                .padding(.top, Theme.Metric.s12)
                .padding(.bottom, Theme.Metric.s8)

                BandHeader("Arrangements — tap to open")
                ForEach(Array(piece.arrangements.enumerated()), id: \.offset) { index, slug in
                    if let score = state.manifest?.scores.first(where: { $0.slug == slug }) {
                        arrangementRow(score, number: index + 1)
                        Divider().overlay(Theme.Line.line)
                    }
                }

                // Whatever the migration wrote, a person can change. Tags
                // arrived from Newzik; nothing about them should be harder to
                // correct than it was to import.
                BandHeader("Details")
                PieceField(label: "Composer", value: piece.composer ?? "",
                           identifier: "piece-composer") { v in
                    Task { _ = await state.setPieceMetadata(piece.slug, composer: v) }
                }
                Divider().overlay(Theme.Line.line)
                PieceField(label: "Arranger", value: piece.arranger ?? "",
                           identifier: "piece-arranger") { v in
                    Task { _ = await state.setPieceMetadata(piece.slug, arranger: v) }
                }
                Divider().overlay(Theme.Line.line)
                PieceField(label: "Tags", value: (piece.tags ?? []).joined(separator: ", "),
                           hint: "Serbia, Bulgaria", identifier: "piece-tags") { v in
                    let tags = v.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    Task { _ = await state.setPieceMetadata(piece.slug, tags: tags) }
                }

                BandHeader("This piece")
                ScreenRow(title: "New arrangement", leads: false,
                          identifier: "piece-new-arrangement-\(piece.slug)") {
                    Task { _ = await state.createArrangement(pieceSlug: piece.slug) }
                }
                ScreenRow(title: "Import into this piece", leads: false,
                          identifier: "piece-import-\(piece.slug)") { onImport(piece.slug) }

                BandHeader("Sources")
                Text(sourceSummary).typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                    .padding(.horizontal, Theme.Metric.s20)
                    .padding(.vertical, Theme.Metric.s8)

                // Separated by its own band so Delete and Delete piece are never
                // adjacent -- one destroys an arrangement, the other the folder.
                BandHeader("Careful")
                if confirmingDelete {
                    ConfirmDeleteStrip(what: deleteWarning,
                                       identifier: "confirm-delete-\(piece.slug)",
                                       onDelete: {
                                           confirmingDelete = false
                                           state.deletePiece(piece.slug)
                                           onBack()
                                       },
                                       onKeep: { confirmingDelete = false })
                } else {
                    ScreenRow(title: "Delete piece", leads: false, isDestructive: true,
                              identifier: "piece-delete-\(piece.slug)") {
                        confirmingDelete = true
                    }
                }
            }
            .padding(.bottom, Theme.Metric.s32)
        }
    }

    private func arrangementRow(_ score: ScoreDoc, number: Int) -> some View {
        HStack(spacing: Theme.Metric.s12) {
            Button { onOpen(score.slug) } label: {
                HStack(spacing: Theme.Metric.s12) {
                    NumeralBadge(number: number)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(score.title ?? score.name).typeRole(.titleS)
                            .foregroundStyle(Theme.Ink.ink)
                        Text("\(score.versions.count) version"
                             + (score.versions.count == 1 ? "" : "s"))
                            .typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // one element, not a stack: a Button whose label is a stack is
            // reported as a container, and the highlight has to live on the
            // element a test can see
            .accessibilityElement(children: .ignore)
            // "Arrangement number N" is the phrase the numeral badge used, and
            // the chat context hands the model the same number
            .accessibilityLabel("Arrangement number \(number), "
                                + "\(score.title ?? score.name), "
                                + "\(score.versions.count) version"
                                + (score.versions.count == 1 ? "" : "s"))
            .accessibilityAddTraits(state.selectedSlug == score.slug
                                    ? [.isButton, .isSelected] : [.isButton])
            .accessibilityIdentifier("arrangement-choice-\(score.slug)")

            // Order, in place. This is what dragging one arrangement onto
            // another used to do -- the same inline pattern the set list screen
            // already uses, and the only way to reorder now that dragging is
            // gone from the app entirely.
            orderButton("chevron.up", label: "Move \(score.title ?? score.name) up",
                        id: "arr-up-\(score.slug)", enabled: number > 1) {
                move(score.slug, by: -1)
            }
            orderButton("chevron.down", label: "Move \(score.title ?? score.name) down",
                        id: "arr-down-\(score.slug)",
                        enabled: number < piece.arrangements.count) {
                move(score.slug, by: 1)
            }

            // §8.1's own mitigation: a ☰ here pushes straight to the
            // arrangement's screen, so filing is two pushes rather than three.
            RowMenuButton(identifier: "row-menu-\(score.slug)",
                          label: "Manage \(score.title ?? score.name)") {
                push(.arrangement(score.slug))
            }
        }
        .padding(.horizontal, Theme.Metric.s20)
        .padding(.vertical, 9)
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

    private var deleteWarning: String {
        let n = piece.arrangements.count
        return n == 0
            ? "Delete \(piece.name)?"
            : "Delete \(piece.name) and its \(n) arrangement\(n == 1 ? "" : "s")?"
    }

    private var sourceSummary: String {
        let count = piece.arrangements.compactMap { slug in
            state.manifest?.scores.first { $0.slug == slug }?.sources?.count
        }.reduce(0, +)
        return count == 0 ? "No other editions imported."
                          : "\(count) read-only source\(count == 1 ? "" : "s")."
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
        Screen(title: "", backLabel: "Back",
               subtitle: placement, onBack: onBack,
               trailing: {
                   PanelButton(title: "Open", kind: .primary, action: onOpen)
                       .accessibilityIdentifier("arrangement-open")
               }) {
            VStack(alignment: .leading, spacing: 0) {
                EditableTitle(text: score.title ?? score.name, role: .title,
                              identifier: "arrangement-title") { name in
                    Task { _ = await state.renameScore(slug: score.slug, name: name) }
                }
                .padding(.horizontal, Theme.Metric.s20)
                .padding(.top, Theme.Metric.s12)
                .padding(.bottom, Theme.Metric.s8)

                BandHeader("Do")
                ScreenRow(title: "Move to piece", value: pieceName ?? "unfiled",
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

                BandHeader("Look at")
                ScreenRow(title: "Versions", value: "\(score.versions.count)",
                          identifier: "edit-versions-\(score.slug)") {
                    push(.versions(score.slug))
                }
                ScreenRow(title: "Parts and ranges",
                          identifier: "arrangement-parts-\(score.slug)") {
                    push(.parts(score.slug))
                }
                ScreenRow(title: "Details", identifier: "row-details-\(score.slug)") {
                    push(.details(score.slug))
                }

                BandHeader("Careful")
                if confirmingDelete {
                    ConfirmDeleteStrip(what: deleteWarning,
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

    private var setlistSummary: String {
        let holding = (state.manifest?.setlists ?? [])
            .filter { $0.arrangements.contains(score.slug) }
        if holding.isEmpty { return "none" }
        return holding.count == 1 ? holding[0].name : "\(holding.count) set lists"
    }

    private var deleteWarning: String {
        let n = score.versions.count
        return "Delete \(score.title ?? score.name) and its \(n) version"
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
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isOpen ? Theme.Accent.clayStrong : Theme.Ink.ink2)
                // A BUTTON, like every other icon in the app. It was a naked
                // glyph sitting in the row's trailing edge, so the one control
                // a row carries did not look like a control at all.
                .frame(width: RowMenuButton.side, height: RowMenuButton.side)
                .background(isOpen ? Theme.Accent.clayTint : Theme.Surface.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(isOpen ? Theme.Accent.clay : Theme.Line.line2,
                                lineWidth: 1)
                }
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
