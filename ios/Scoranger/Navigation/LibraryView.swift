import SwiftUI

/// My Library (NAVIGATION_SYSTEM.md §4.2–4.3).
///
/// Segmented Pieces/Setlists, search, sort, filter, Edit, the A–Z rail and a
/// FAB. The rail is shown only under name sort -- under any other order the
/// letters would not agree with the rows, so it hides rather than lies.
struct LibraryView: View {
    @EnvironmentObject var state: AppState
    @Binding var segment: LibrarySegment
    @Binding var search: String
    @Binding var sort: LibrarySort
    @Binding var filters: Set<LibraryFilter>
    @Binding var editing: Bool
    var onOpenPiece: (String) -> Void
    var onOpenArrangement: (String) -> Void
    var onOpenSetlist: (SetlistDoc) -> Void
    var onNew: () -> Void
    var onImport: () -> Void
    var onRowAction: (LibraryRow, RowAction) -> Void

    @State private var showSort = false
    @State private var showFilter = false
    @State private var scrollTo: String?
    @State private var dropTarget: String?
    @State private var addMenuOpen = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                segmented
                    .padding(.top, Theme.Metric.s12)
                header
                controlBar
                Divider().overlay(Theme.Line.line)
                list
            }
            .background(Theme.Surface.ground)

            fab
                .padding(.trailing, Theme.Metric.s20)
                .padding(.bottom, Theme.Metric.s20)
        }
    }

    // MARK: - Chrome

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(LibrarySegment.allCases, id: \.self) { option in
                Button { segment = option } label: {
                    Text(option.title)
                        .typeRole(.row)
                        .foregroundStyle(segment == option ? Theme.Accent.clayStrong
                                                           : Theme.Ink.ink2)
                        .padding(.horizontal, Theme.Metric.s20)
                        .padding(.vertical, Theme.Metric.s6)
                        .background(segment == option ? Theme.Accent.clayTint : Color.clear)
                        .overlay {
                            if segment == option {
                                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                                    .stroke(Theme.Accent.clay, lineWidth: 1)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("segment-\(option.rawValue)")
                .accessibilityAddTraits(segment == option ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(Theme.Surface.well)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rPanel))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metric.rPanel)
                .stroke(Theme.Line.line2, lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Metric.s8) {
            Text("My library").typeRole(.title).foregroundStyle(Theme.Ink.ink)
            Text("\(rows.count)").typeRole(.data).foregroundStyle(Theme.Ink.ink3)
            Spacer()
        }
        .padding(.horizontal, Theme.Metric.s20)
        .padding(.top, Theme.Metric.s12)
    }

    private var controlBar: some View {
        VStack(spacing: Theme.Metric.s8) {
            SearchField(placeholder: "Search \(segment.title.lowercased())…",
                        text: $search, identifier: "library-search")
            HStack(spacing: Theme.Metric.s8) {
                Button { showSort.toggle(); showFilter = false } label: {
                    controlLabel("Sort: \(sort.label)")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("library-sort")

                Button { showFilter.toggle(); showSort = false } label: {
                    controlLabel(filters.isEmpty ? "Filter"
                                 : "Filter · \(filters.count)")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("library-filter")

                Spacer()
                Button { editing.toggle() } label: {
                    controlLabel(editing ? "Done" : "Edit", active: editing)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("library-edit")
            }
            if showSort { sortOptions }
            if showFilter { filterOptions }
        }
        .padding(.horizontal, Theme.Metric.s20)
        .padding(.vertical, Theme.Metric.s12)
    }

    private func controlLabel(_ text: String, active: Bool = false) -> some View {
        Text(text)
            .typeRole(.meta)
            .foregroundStyle(active ? Theme.Accent.clayStrong : Theme.Ink.ink2)
            .padding(.horizontal, Theme.Metric.s8)
            .padding(.vertical, 4)
            .background(active ? Theme.Accent.clayTint : Theme.Surface.panel)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                    .stroke(active ? Theme.Accent.clay : Theme.Line.line2, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
    }

    private var sortOptions: some View {
        HStack(spacing: Theme.Metric.s6) {
            ForEach(LibrarySort.allCases, id: \.self) { option in
                Button { sort = option; showSort = false } label: {
                    controlLabel(option.label, active: sort == option)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sort-\(option.rawValue)")
            }
            Spacer()
        }
    }

    private var filterOptions: some View {
        HStack(spacing: Theme.Metric.s6) {
            ForEach(LibraryFilter.allCases, id: \.self) { option in
                Button {
                    if filters.contains(option) { filters.remove(option) }
                    else { filters.insert(option) }
                } label: {
                    controlLabel(option.label, active: filters.contains(option))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("filter-\(option.rawValue)")
            }
            Spacer()
        }
    }

    // MARK: - The list

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if rows.isEmpty { empty } else { grouped }
            }
            .padding(.bottom, 90)
        }
    }

    @ViewBuilder
    private var grouped: some View {
        // Letter headers only under name sort: under any other order they
        // would disagree with the rows. The rail that used to sit beside them
        // is gone (0.4.1 §5) -- search covers "jump to L", and the trailing
        // edge goes back to the chevrons.
        if sort.showsAlphabetRail {
            ForEach(LibraryModel.grouped(rows), id: \.letter) { group in
                Section {
                    ForEach(group.rows) { row in rowView(row) }
                } header: {
                    Text(group.letter)
                        .typeRole(.label)
                        .foregroundStyle(Theme.Accent.clayStrong)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Metric.s20)
                        .padding(.vertical, Theme.Metric.s4)
                        .background(Theme.Surface.band)
                        .id("letter-\(group.letter)")
                }
            }
        } else {
            ForEach(rows) { row in rowView(row) }
        }
    }

    private func rowView(_ row: LibraryRow) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                LRow(row: row, identifier: "row-\(row.id)", action: { open(row) }) {
                    RowContextMenu(row: row,
                                   isPiece: isPiece(row),
                                   isSetlist: segment == .setlists) { action in
                        onRowAction(row, action)
                    }
                }
                // A set list's own "+": choosing which arrangements are in it,
                // which is the other direction from an arrangement's "add to
                // set list" and answers a different question.
                if segment == .setlists {
                    Button { onRowAction(row, .addToSetlist) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.Accent.clayStrong)
                            .frame(width: Theme.Metric.hitTarget,
                                   height: Theme.Metric.hitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("add-to-setlist-\(row.id)")
                    .accessibilityLabel("Add arrangements to \(row.title)")
                    .padding(.trailing, Theme.Metric.s12)
                }
            }
            if editing { editingActions(row) }
            Divider().overlay(Theme.Line.line)
        }
        // Drag to file, which the sidebar carried (§8): an arrangement onto a
        // piece files it there, onto a set list adds it to the running order.
        // A drop target only exists where a drop MEANS something, so a piece
        // never accepts a piece.
        .draggable(row.id) { LRow(row: row, identifier: "drag-\(row.id)", action: {}) }
        .dropDestination(for: String.self) { items, _ in
            guard let dropped = items.first, dropped != row.id else { return false }
            return accept(dropped, onto: row)
        } isTargeted: { targeted in
            dropTarget = targeted ? row.id : (dropTarget == row.id ? nil : dropTarget)
        }
        .background(dropTarget == row.id ? Theme.Accent.clayTint : Color.clear)
    }

    /// What a drop means, which depends entirely on what it landed on.
    private func accept(_ dropped: String, onto row: LibraryRow) -> Bool {
        if segment == .setlists {
            Task { _ = await state.addToSetlist(setlist: row.id, score: dropped) }
            return true
        }
        // onto a piece: file the arrangement under it
        if isPiece(row) {
            state.assignToPiece(scoreSlug: dropped, piece: row.id)
            return true
        }
        // onto another arrangement of the same piece: reorder
        if let piece = (state.manifest?.pieces ?? []).first(where: {
            $0.arrangements.contains(row.id) && $0.arrangements.contains(dropped)
        }), let from = piece.arrangements.firstIndex(of: dropped),
           let to = piece.arrangements.firstIndex(of: row.id) {
            var order = piece.arrangements
            order.remove(at: from)
            order.insert(dropped, at: to)
            state.reorderPiece(piece: piece.slug, order: order)
            return true
        }
        return false
    }

    private func isPiece(_ row: LibraryRow) -> Bool {
        (state.manifest?.pieces ?? []).contains { $0.slug == row.id }
    }

    /// Edit mode puts the same actions on screen as buttons.
    ///
    /// A context menu is a long press, which is invisible to Switch Control and
    /// undiscoverable to anyone who has not been told -- so every action it
    /// carries also has a plain button here. This is the same rule the page-turn
    /// zones follow (§6.6): a gesture may be the fast way, never the only way.
    private func editingActions(_ row: LibraryRow) -> some View {
        HStack(spacing: Theme.Metric.s6) {
            if segment == .pieces {
                editButton("Versions", id: "edit-versions-\(row.id)") {
                    onRowAction(row, .versions)
                }
                editButton("Set lists", id: "edit-setlists-\(row.id)") {
                    onRowAction(row, .addToSetlist)
                }
            }
            editButton("Rename", id: "edit-rename-\(row.id)") { onRowAction(row, .rename) }
            editButton("Delete", id: "edit-delete-\(row.id)") { onRowAction(row, .delete) }
            Spacer()
        }
        .padding(.horizontal, Theme.Metric.s20)
        .padding(.bottom, Theme.Metric.s8)
    }

    private func editButton(_ title: String, id: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) { controlLabel(title) }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
    }

    private var empty: some View {
        Text(search.isEmpty && filters.isEmpty
             ? "Nothing here yet. Use + to add something."
             : "No matches.")
            .typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
            .padding(Theme.Metric.s20)
            .accessibilityIdentifier("library-empty")
    }

    /// The `+`, and the two things it can make (0.4.1 §4).
    ///
    /// There was no way to import from the library at all -- import lived only
    /// on Home -- so the `+` now says what it can do instead of assuming.
    private var fab: some View {
        VStack(alignment: .trailing, spacing: Theme.Metric.s8) {
            if addMenuOpen { addMenu }
            Button {
                withAnimation(.easeOut(duration: 0.14)) { addMenuOpen.toggle() }
            } label: {
                Image(systemName: addMenuOpen ? "xmark" : "plus")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(addMenuOpen ? Theme.Accent.clayStrong
                                                 : Theme.Surface.paper)
                    .frame(width: 54, height: 54)
                    .background(addMenuOpen ? Theme.Surface.panel : Theme.Accent.clayPress)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rPanel))
                    .overlay {
                        if addMenuOpen {
                            RoundedRectangle(cornerRadius: Theme.Metric.rPanel)
                                .stroke(Theme.Accent.clay, lineWidth: 1)
                        }
                    }
                    .shadow(color: Color(hex: 0x1A1917).opacity(0.18), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("library-add")
            .accessibilityLabel(addMenuOpen ? "Close" : "Add")
        }
    }

    private var addMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            addRow(title: segment == .pieces ? "New" : "New set list",
                   detail: segment == .pieces
                       ? "A blank arrangement, filed under a new piece"
                       : "An empty running order to fill",
                   glyph: "square", id: "fab-new") { onNew() }
            Divider().overlay(Theme.Line.line)
            addRow(title: "Import",
                   detail: "PDF, MusicXML, MIDI — a PDF goes through OMR",
                   glyph: "arrow.down.to.line", id: "fab-import") { onImport() }
        }
        .frame(width: 250)
        .background(Theme.Surface.panel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rPanel))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metric.rPanel)
                .stroke(Theme.Line.line2, lineWidth: 1)
        }
        .shadow(color: Color(hex: 0x1A1917).opacity(0.14), radius: 10, y: 4)
    }

    private func addRow(title: String, detail: String, glyph: String, id: String,
                        action: @escaping () -> Void) -> some View {
        Button {
            addMenuOpen = false
            action()
        } label: {
            HStack(spacing: Theme.Metric.s8) {
                Image(systemName: glyph).font(.system(size: 14))
                    .foregroundStyle(Theme.Accent.clayStrong).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                    Text(detail).typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Metric.s12)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(id)
    }

    // MARK: - Data

    private var rows: [LibraryRow] {
        guard let manifest = state.manifest else { return [] }
        var base = segment == .pieces
            ? LibraryModel.pieceRows(manifest: manifest)
                + LibraryModel.unfiledRows(manifest: manifest)
            : LibraryModel.setlistRows(manifest: manifest)
        base = applyFilters(base, manifest: manifest)
        return LibraryModel.sorted(LibraryModel.searched(base, query: search), by: sort)
    }

    /// Derived filters, computed from the manifest -- not a tag store (§7).
    private func applyFilters(_ rows: [LibraryRow], manifest: Manifest) -> [LibraryRow] {
        guard !filters.isEmpty else { return rows }
        let inSetlist = Set((manifest.setlists ?? []).flatMap(\.arrangements))
        let piecesWithSetlisted = Set((manifest.pieces ?? [])
            .filter { !$0.arrangements.filter(inSetlist.contains).isEmpty }
            .map(\.slug))
        return rows.filter { row in
            filters.allSatisfy { filter in
                switch filter {
                case .unfiled:
                    return row.chips.contains { $0.text == "UNFILED" }
                case .omrDrafts:
                    return row.chips.contains { $0.text == "OMR DRAFT" }
                case .hasSources:
                    return row.chips.contains { $0.text.hasSuffix("SOURCE") }
                case .inASetlist:
                    return piecesWithSetlisted.contains(row.id) || inSetlist.contains(row.id)
                }
            }
        }
    }

    private func open(_ row: LibraryRow) {
        if segment == .setlists,
           let setlist = (state.manifest?.setlists ?? []).first(where: { $0.slug == row.id }) {
            RecentSetlists.opened(setlist.slug)
            onOpenSetlist(setlist)
            return
        }
        // A piece is not openable (§2): opening one means opening one of its
        // arrangements. One arrangement goes straight there; several put the
        // choice on screen.
        if (state.manifest?.pieces ?? []).contains(where: { $0.slug == row.id }) {
            onOpenPiece(row.id)
        } else {
            onOpenArrangement(row.id)
        }
    }
}
