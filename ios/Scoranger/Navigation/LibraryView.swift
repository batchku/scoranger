import SwiftUI

/// My Library -- the app (NAVIGATION_SYSTEM.md §4.2-4.3, §4C).
///
/// Home is gone and this is what the app opens on. It gained Home's top row
/// (help, inbox, settings, and the engine chip) and Home's four actions, as a
/// compact row under the search field rather than four large panels; it lost
/// the `+` FAB, which offered exactly what that row now shows permanently.
///
/// Segmented Pieces/Setlists, search, the action row, the A-Z rail. The rail is
/// shown only under name sort -- under any other order the letters would not
/// agree with the rows, so it hides rather than lies.
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
    /// The row's ☰. Pushes to the item's screen, or expands in place, by the
    /// rule in RowMenuBehaviour.
    var onRowMenu: (LibraryRow) -> Void
    /// Naming a new piece or set list, in a band at the top of the list --
    /// not a popup and not a screen, because it is one field (§5.1).
    var onCreate: (String) -> Void
    var onImport: () -> Void
    /// Home's actions, rehomed (§4C). `onAsk` is nil when nothing has been
    /// opened yet, which DISABLES the button rather than hiding it -- a row
    /// that re-flows under a finger is worse than a dimmed button.
    var onAsk: (() -> Void)?
    var onSettings: () -> Void
    var onRowAction: (LibraryRow, RowAction) -> Void
    var onBarAction: (LibraryAction, Set<String>, LibrarySelectionKind) -> Void

    @State private var showSort = false
    @State private var showFilter = false
    @State private var scrollTo: String?
    @State private var creatingName: String?
    @State private var selected: Set<String> = []

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                topRow
                    .padding(.horizontal, Theme.Metric.s20)
                    .padding(.top, Theme.Metric.s12)
                segmented
                    .padding(.top, Theme.Metric.s12)
                header
                controlBar
                Divider().overlay(Theme.Line.line)
                list
            }
            .background(Theme.Surface.ground)
        }
        .overlay(alignment: .bottom) {
            if editing && !selected.isEmpty { actionBar }
        }
        .onChange(of: editing) { _, on in if !on { selected = [] } }
        .onChange(of: segment) { _, _ in selected = [] }
    }

    /// The action bar (§2.2): what you can do to what is highlighted.
    ///
    /// The verbs are scoped by KIND, because they are not interchangeable -- a
    /// piece is a folder and cannot be duplicated or put in a set list. Actions
    /// needing exactly one row grey to 42% rather than vanishing, so the bar
    /// never re-flows under a finger.
    private var actionBar: some View {
        let kind = selectionKind
        return HStack(spacing: Theme.Metric.s8) {
            Text("\(selected.count) selected").typeRole(.data)
                .foregroundStyle(Theme.Ink.ink2)
            Spacer(minLength: Theme.Metric.s8)
            ForEach(LibraryActions.bar(for: kind), id: \.self) { action in
                let on = LibraryActions.isEnabled(action, count: selected.count)
                Button {
                    onBarAction(action, selected, kind)
                    if action == .delete { selected = [] }
                } label: {
                    Text(action.title(count: selected.count, kind: kind))
                        .typeRole(.control)
                        .foregroundStyle(action.isDestructive ? Theme.Surface.paper
                                                              : Theme.Ink.ink)
                        .padding(.horizontal, Theme.Metric.s12)
                        .padding(.vertical, Theme.Metric.s6)
                        .background(action.isDestructive ? Theme.Status.danger
                                                         : Theme.Surface.panel)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                                .stroke(action.isDestructive ? Theme.Status.danger
                                                             : Theme.Line.line2,
                                        lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!on)
                .opacity(on ? 1 : 0.42)
                .accessibilityIdentifier(action.identifier)
            }
        }
        .padding(.horizontal, Theme.Metric.s16)
        .frame(height: 56)
        .background(Theme.Surface.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.Line.line).frame(height: 1) }
        .shadow(color: Color(hex: 0x1A1917).opacity(0.07), radius: 18, y: -6)
        .accessibilityIdentifier("library-actionbar")
    }

    private var selectionKind: LibrarySelectionKind {
        LibraryActions.kind(of: selected,
                            pieces: Set((state.manifest?.pieces ?? []).map(\.slug)),
                            setlists: Set((state.manifest?.setlists ?? []).map(\.slug)))
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

    /// Home's top row, rehomed (§4C): the leading trio and the engine chip
    /// keep their positions, now on the screen the app opens to.
    private var topRow: some View {
        HStack(spacing: Theme.Metric.s8) {
            PanelIconButton(systemName: "questionmark", label: "Help") {}
            inbox
            PanelIconButton(systemName: "gearshape", label: "Settings",
                            action: onSettings)
                .accessibilityIdentifier("library-settings")
            Spacer()
            engineChip
        }
    }

    private var inbox: some View {
        PanelIconButton(systemName: "tray", label: "Inbox") {}
            .overlay(alignment: .topTrailing) {
                if !state.pendingImports.isEmpty {
                    Text("\(state.pendingImports.count)")
                        .typeRole(.meta)
                        .foregroundStyle(Theme.Surface.paper)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Circle().fill(Theme.Accent.clay))
                        .offset(x: 4, y: -4)
                }
            }
    }

    /// The chip prints the mode ONCE. `LED` used to print a word of its own,
    /// and this chip printed the mode beside it, so it read "on-device
    /// on-device" -- and the dot's word was about reachability, not the mode,
    /// so in remote mode it still said "on-device". The dot is a dot now.
    private var engineChip: some View {
        HStack(spacing: Theme.Metric.s6) {
            LED(isOn: state.engineOK)
            Text(state.useLocalEngine ? "on-device" : "remote")
                .typeRole(.data).foregroundStyle(Theme.Ink.ink2)
        }
        .padding(.horizontal, Theme.Metric.s8)
        .padding(.vertical, 5)
        .background(Theme.Surface.panel)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                .stroke(Theme.Line.line2, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("library-engine-chip")
        .accessibilityLabel("Engine: \(state.useLocalEngine ? "on-device" : "remote"), "
                            + (state.engineOK ? "reachable" : "unreachable"))
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

    /// Search, then the action row: the library's own actions on the left, the
    /// list's controls on the right (§4C). One bar, two clusters -- what you
    /// can MAKE, and how you are LOOKING at what you have.
    private var controlBar: some View {
        VStack(spacing: LibraryActionRow.spaceAboveRow) {
            SearchField(placeholder: "Search \(segment.title.lowercased())…",
                        text: $search, identifier: "library-search")
            GeometryReader { geo in
                let compact = LibraryActionRow.isCompact(width: geo.size.width)
                HStack(spacing: LibraryActionRow.gap) {
                    ForEach(LibraryQuickAction.ordered) { action in
                        quickButton(action, compact: compact)
                    }
                    Spacer(minLength: LibraryActionRow.clusterGap)
                    Button { showSort.toggle(); showFilter = false } label: {
                        // Sort keeps its value in compact width: its label is
                        // an ANSWER, not the button's name
                        rowButton("Sort: \(sort.label)", glyph: "arrow.up.arrow.down",
                                  iconOnly: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library-sort")

                    Button { showFilter.toggle(); showSort = false } label: {
                        rowButton(filters.isEmpty ? "Filter" : "Filter · \(filters.count)",
                                  glyph: "line.3.horizontal.decrease",
                                  iconOnly: compact && filters.isEmpty)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library-filter")

                    Button { editing.toggle() } label: {
                        rowButton(editing ? "Done" : "Edit",
                                  glyph: "checkmark.circle",
                                  iconOnly: compact, active: editing)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library-edit")
                }
                .frame(width: geo.size.width, height: LibraryActionRow.height)
            }
            .frame(height: LibraryActionRow.height)
            if showSort { sortOptions }
            if showFilter { filterOptions }
        }
        .padding(.horizontal, LibraryActionRow.sidePadding)
        .padding(.top, Theme.Metric.s12)
        .padding(.bottom, LibraryActionRow.spaceBelowRow)
    }

    @ViewBuilder
    private func quickButton(_ action: LibraryQuickAction, compact: Bool) -> some View {
        let enabled = action != .ask || onAsk != nil
        Button {
            switch action {
            case .importScore: onImport()
            case .new:         creatingName = ""
            case .newSetlist:  segment = .setlists; creatingName = ""
            case .ask:         onAsk?()
            }
        } label: {
            rowButton(action.title, glyph: action.glyph, iconOnly: compact)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.42)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(action.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(action.identifier)
    }

    /// One button of the action row: 32pt, bordered, panel fill, no emphasis.
    /// At four buttons in a bar a clay fill would shout, and the accent belongs
    /// to selection and to `#N` (§4C).
    private func rowButton(_ text: String, glyph: String,
                           iconOnly: Bool, active: Bool = false) -> some View {
        HStack(spacing: Theme.Metric.s6) {
            Image(systemName: glyph).font(.system(size: 13, weight: .medium))
            if !iconOnly {
                // one line, at its natural width: "Sort: recently changed" is
                // the longest label here and it wrapped inside a 32pt button
                Text(text).font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .foregroundStyle(active ? Theme.Accent.clayStrong : Theme.Ink.ink2)
        .padding(.horizontal, iconOnly ? 0 : LibraryActionRow.buttonPadding)
        .frame(width: iconOnly ? LibraryActionRow.buttonHeight : nil,
               height: LibraryActionRow.buttonHeight)
        .background(active ? Theme.Accent.clayTint : Theme.Surface.panel)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                .stroke(active ? Theme.Accent.clay : Theme.Line.line2, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
        .contentShape(Rectangle())
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
                // Naming a new thing happens here, in place: the list moves
                // down, nothing dims, and there is nothing to dismiss.
                if creatingName != nil {
                    InlineRenameRow(text: Binding(get: { creatingName ?? "" },
                                                  set: { creatingName = $0 }),
                                    onSave: {
                                        let name = (creatingName ?? "")
                                            .trimmingCharacters(in: .whitespacesAndNewlines)
                                        creatingName = nil
                                        if !name.isEmpty { onCreate(name) }
                                    },
                                    onCancel: { creatingName = nil })
                    Divider().overlay(Theme.Line.line)
                }

                // Imports in flight, at the top where they cannot be missed.
                //
                // They used to render only in the score screen's library
                // overlay, which the redesign retired -- so an import showed a
                // badge on a Home icon that was not tappable and then could
                // not be found at all (0.4.1 item 9).
                if segment == .pieces {
                    ForEach(state.pendingImports) { pending in importingRow(pending) }
                }
                if rows.isEmpty && state.pendingImports.isEmpty { empty } else { grouped }
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
                if editing { checkbox(row) }
                LRow(row: row, identifier: "row-\(row.id)",
                     action: { editing ? toggle(row) : open(row) },
                     onMenu: editing ? nil : { onRowMenu(row) })
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
    }

    // Dragging is gone from the app entirely. Every use it had has a named
    // screen instead: filing happens at import time or through the
    // arrangement's Move to piece, set-list membership through the set list's
    // Add arrangements, and order through Move up / Move down. A gesture that
    // is the only way to reach a feature was already against the rules here;
    // this removes the gesture rather than adding a second path to it.

    /// The leading checkbox (§2.1). Selecting is what raises the action bar.
    private func checkbox(_ row: LibraryRow) -> some View {
        Button { toggle(row) } label: {
            Image(systemName: selected.contains(row.id) ? "checkmark.square.fill" : "square")
                .font(.system(size: 17))
                .foregroundStyle(selected.contains(row.id) ? Theme.Accent.clayStrong
                                                           : Theme.Ink.ink3)
                .frame(width: Theme.Metric.hitTarget, height: Theme.Metric.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("row-select-\(row.id)")
        .accessibilityLabel("Select \(row.title)")
        .accessibilityAddTraits(selected.contains(row.id) ? [.isSelected] : [])
        .padding(.leading, Theme.Metric.s8)
    }

    private func toggle(_ row: LibraryRow) {
        if selected.contains(row.id) { selected.remove(row.id) }
        else { selected.insert(row.id) }
    }

    /// A piece filling up. It sits in the list from the moment the file is
    /// chosen, so "where did it go?" never has to be asked.
    private func importingRow(_ pending: AppState.PendingImport) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Metric.s12) {
                PageThumb()
                VStack(alignment: .leading, spacing: 3) {
                    Text(pieceName(for: pending) ?? pending.name)
                        .typeRole(.titleS).foregroundStyle(Theme.Ink.ink)
                    Text(pending.stage).typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                    if let fraction = pending.fraction {
                        ProgressView(value: fraction)
                            .tint(Theme.Accent.clay)
                            .frame(maxWidth: 180)
                    }
                }
                Spacer(minLength: Theme.Metric.s8)
                Text("IMPORTING").typeRole(.meta)
                    .foregroundStyle(Color(hex: 0x8A5A12))
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Color(hex: 0xFBF2E6))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                            .stroke(Color(hex: 0xE8CFA6), lineWidth: 1)
                    }
            }
            .padding(.horizontal, Theme.Metric.s20)
            .padding(.vertical, 9)
            .frame(minHeight: 56)
            Divider().overlay(Theme.Line.line)
        }
        .accessibilityIdentifier("importing-\(pending.id.uuidString)")
        .accessibilityLabel("\(pieceName(for: pending) ?? pending.name), importing, \(pending.stage)")
    }

    private func pieceName(for pending: AppState.PendingImport) -> String? {
        guard let slug = pending.piece else { return nil }
        return (state.manifest?.pieces ?? []).first { $0.slug == slug }?.name
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

    /// The empty library is the app's FIRST screen now, so it carries the
    /// welcome -- and the action row stays above it, which is what the words
    /// point at (§4C).
    private var empty: some View {
        Text(search.isEmpty && filters.isEmpty
             ? "Nothing here yet — import a score, or make a blank arrangement "
               + "and ask for what you want."
             : "No matches.")
            .typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
            .padding(Theme.Metric.s20)
            .accessibilityIdentifier("library-empty")
    }

    // The `+` FAB and its New/Import band are gone (§4C). They offered
    // exactly what the action row now shows permanently, which makes the row
    // the de-duplication rather than a second way in.

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
