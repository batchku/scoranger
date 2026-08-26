import SwiftUI

/// Where the old sidebar's management went (NAVIGATION_SYSTEM.md §8).
///
/// The sidebar carried rename, delete, filing, setlist membership, version
/// browsing and "add an arrangement to this piece" on expandable rows. The new
/// IA has no sidebar, so those did not move by themselves -- and a redesign
/// that quietly drops working features is a regression wearing new chrome.
/// Each one has a home here.
enum RowAction: Equatable {
    case open, versions, details, rename, addToSetlist, delete, newArrangement
}

/// The context menu every library row carries. This is §8's "row context
/// menus", and it is where four of the five homeless features landed.
struct RowContextMenu: View {
    let row: LibraryRow
    let isPiece: Bool
    let isSetlist: Bool
    var perform: (RowAction) -> Void

    var body: some View {
        Group {
            Button { perform(.open) } label: {
                Label(isSetlist ? "Play from the top" : "Open", systemImage: "arrow.right")
            }
            if !isSetlist {
                Button { perform(.versions) } label: {
                    Label("Versions…", systemImage: "clock.arrow.circlepath")
                }
                Button { perform(.details) } label: {
                    Label("Arrangement details", systemImage: "info.circle")
                }
                Button { perform(.addToSetlist) } label: {
                    Label("Add to set list…", systemImage: "text.badge.plus")
                }
            }
            if isPiece {
                Button { perform(.newArrangement) } label: {
                    Label("New arrangement of this piece", systemImage: "plus")
                }
            }
            Button { perform(.rename) } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Button(role: .destructive) { perform(.delete) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// Choosing which set lists an arrangement belongs to (§8).
///
/// The old sidebar reached this from a row's context menu; so does the new one.
/// It shows membership rather than only offering to add, because "is this in
/// Friday's set?" is the question people actually have.
struct SetlistPicker: View {
    @EnvironmentObject var state: AppState
    let score: ScoreDoc
    var onDone: () -> Void

    var body: some View {
        PanelSheet(title: "Set lists", onDone: onDone) {
            VStack(alignment: .leading, spacing: 0) {
                BandHeader("\(score.title ?? score.name) belongs to")
                ForEach(state.manifest?.setlists ?? []) { setlist in
                    let member = setlist.arrangements.contains(score.slug)
                    Button {
                        Task {
                            if member {
                                _ = await state.removeFromSetlist(setlist: setlist.slug,
                                                                  score: score.slug)
                            } else {
                                _ = await state.addToSetlist(setlist: setlist.slug,
                                                             score: score.slug)
                            }
                        }
                    } label: {
                        HStack(spacing: Theme.Metric.s8) {
                            Image(systemName: member ? "checkmark.square.fill" : "square")
                                .foregroundStyle(member ? Theme.Accent.clayStrong
                                                        : Theme.Ink.ink3)
                            Text(setlist.name).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                            Spacer()
                            Text("\(setlist.arrangements.count)").typeRole(.data)
                                .foregroundStyle(Theme.Ink.ink3)
                        }
                        .padding(.horizontal, Theme.Metric.panelPadding)
                        .padding(.vertical, Theme.Metric.sheetRowVertical)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chooser-\(setlist.slug)")
                }
                if (state.manifest?.setlists ?? []).isEmpty {
                    Text("No set lists yet. Make one with + in the Setlists tab.")
                        .typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                        .padding(Theme.Metric.panelPadding)
                }
            }
        }
    }
}

/// The arrangements of a piece, their versions, and what you can do to them
/// (§4.4). This is where the sidebar's expandable rows went.
struct ArrangementSheet: View {
    @EnvironmentObject var state: AppState
    let piece: PieceDoc
    var onOpen: (String, String?) -> Void
    var onNewArrangement: () -> Void
    var onImportArrangement: () -> Void
    var onRenamePiece: () -> Void
    var onDone: () -> Void
    var onArrangementAction: (ScoreDoc, RowAction) -> Void

    @State private var expanded: Set<String> = []

    var body: some View {
        PanelSheet(title: piece.name, onDone: onDone) {
            VStack(alignment: .leading, spacing: 0) {
                BandHeader("Arrangements")
                ForEach(Array(piece.arrangements.enumerated()), id: \.offset) { index, slug in
                    if let score = state.manifest?.scores.first(where: { $0.slug == slug }) {
                        arrangementRow(score, number: index + 1)
                        if expanded.contains(slug) { versionList(score) }
                    }
                }
                BandHeader("Sources")
                Text(sourceSummary).typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                    .padding(.horizontal, Theme.Metric.panelPadding)
                    .padding(.bottom, Theme.Metric.s8)

                HStack(spacing: Theme.Metric.s8) {
                    Menu {
                        Button { onNewArrangement() } label: {
                            Label("New blank arrangement", systemImage: "square")
                        }
                        Button { onImportArrangement() } label: {
                            Label("Import a file…", systemImage: "arrow.down.to.line")
                        }
                    } label: {
                        Text("New arrangement of this piece")
                            .typeRole(.control)
                            .foregroundStyle(Theme.Surface.paper)
                            .padding(.horizontal, Theme.Metric.s12)
                            .padding(.vertical, Theme.Metric.s6)
                            .background(Theme.Accent.clayPress)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
                    }
                    .accessibilityIdentifier("sheet-new-arrangement")
                    PanelButton(title: "Rename piece", action: onRenamePiece)
                        .accessibilityIdentifier("sheet-rename-piece")
                    Spacer()
                }
                .padding(Theme.Metric.panelPadding)
            }
        }
    }

    private func arrangementRow(_ score: ScoreDoc, number: Int) -> some View {
        HStack(spacing: Theme.Metric.s12) {
            Button { onOpen(score.slug, nil) } label: {
                HStack(spacing: Theme.Metric.s12) {
                    NumeralBadge(number: number)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(score.title ?? score.name).typeRole(.titleS)
                            .foregroundStyle(Theme.Ink.ink)
                        Text("\(score.versions.count) versions").typeRole(.meta)
                            .foregroundStyle(Theme.Ink.ink3)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("arrangement-choice-\(score.slug)")
            .contextMenu {
                RowContextMenu(row: LibraryRow(id: score.slug,
                                               title: score.title ?? score.name,
                                               subtitle: "", chips: [], meta: "",
                                               sortName: score.name, composer: "",
                                               changed: "", arrangementCount: 1),
                               isPiece: false, isSetlist: false) { action in
                    onArrangementAction(score, action)
                }
            }

            // Per-row version browsing, which the sidebar used to carry (§8).
            Button {
                if expanded.contains(score.slug) { expanded.remove(score.slug) }
                else { expanded.insert(score.slug) }
            } label: {
                Image(systemName: expanded.contains(score.slug) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Ink.ink2)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("versions-toggle-\(score.slug)")
            .accessibilityLabel("Versions of arrangement number \(number)")
        }
        .padding(.horizontal, Theme.Metric.panelPadding)
        .padding(.vertical, Theme.Metric.sheetRowVertical)
    }

    private func versionList(_ score: ScoreDoc) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(score.versions.reversed(), id: \.id) { version in
                Button { onOpen(score.slug, version.id == score.latest ? nil : version.id) } label: {
                    HStack(spacing: Theme.Metric.s8) {
                        Text(version.id).typeRole(.data).foregroundStyle(Theme.Ink.ink2)
                        Text(version.op).typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                        Spacer()
                    }
                    .padding(.leading, Theme.Metric.versionIndent)
                    .padding(.trailing, Theme.Metric.panelPadding)
                    .padding(.vertical, Theme.Metric.versionRowVertical)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("version-\(score.slug)-\(version.id)")
            }
        }
        .background(Theme.Surface.well)
    }

    private var sourceSummary: String {
        let count = piece.arrangements.compactMap { slug in
            state.manifest?.scores.first { $0.slug == slug }?.sources?.count
        }.reduce(0, +)
        return count == 0 ? "No other editions imported."
                          : "\(count) read-only source\(count == 1 ? "" : "s")."
    }
}


/// The other half of set-list membership: standing in a SET LIST and choosing
/// which arrangements are in it.
///
/// The sidebar had both directions -- a "+" on a set list, and "add to set
/// list" on an arrangement -- and they answer different questions. Building
/// only the per-arrangement one would have quietly halved the feature, which is
/// exactly the kind of loss this rehoming exists to prevent.
struct SetlistArrangementPicker: View {
    @EnvironmentObject var state: AppState
    let setlist: SetlistDoc
    var onDone: () -> Void

    var body: some View {
        PanelSheet(title: setlist.name, onDone: onDone) {
            VStack(alignment: .leading, spacing: 0) {
                BandHeader("In this set list")
                ForEach(state.manifest?.scores ?? []) { score in
                    let member = current.arrangements.contains(score.slug)
                    Button {
                        Task {
                            if member {
                                _ = await state.removeFromSetlist(setlist: setlist.slug,
                                                                  score: score.slug)
                            } else {
                                _ = await state.addToSetlist(setlist: setlist.slug,
                                                             score: score.slug)
                            }
                        }
                    } label: {
                        HStack(spacing: Theme.Metric.s8) {
                            Image(systemName: member ? "checkmark.square.fill" : "square")
                                .foregroundStyle(member ? Theme.Accent.clayStrong
                                                        : Theme.Ink.ink3)
                            if let placement = state.placement(of: score.slug) {
                                Text("\(placement.piece.name) #\(placement.number)")
                                    .typeRole(.row).foregroundStyle(Theme.Ink.ink)
                            } else {
                                Text(score.title ?? score.name)
                                    .typeRole(.row).foregroundStyle(Theme.Ink.ink)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, Theme.Metric.panelPadding)
                        .padding(.vertical, Theme.Metric.sheetRowVertical)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        member ? "picker-remove-\(score.slug)" : "picker-add-\(score.slug)")
                }
            }
        }
    }

    /// Read membership live: the sheet edits the set list it is showing.
    private var current: SetlistDoc {
        state.manifest?.setlists?.first { $0.slug == setlist.slug } ?? setlist
    }
}
