import SwiftUI

/// My Library -- the app (NAVIGATION_SYSTEM.md §4.2-4.3, §4C).
///
/// Home is gone and this is what the app opens on. It took Home's actions as a
/// compact row under the search field rather than four large panels, and lost
/// the `+` FAB, which offered exactly what that row shows permanently.
///
/// Its top row is the gear alone. Help, the inbox and the engine chip came
/// across from Home and went again at Ali's word (#48-#50): two of them did
/// nothing when tapped, and the third restates a settled question on the screen
/// he reads music from.
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
    /// A shared set list, by its Firestore id. Defaulted so every existing
    /// construction of this view still compiles.
    var onOpenSharedSetlist: (String) -> Void = { _ in }
    /// Share the set list with this slug: promote it if it is not shared yet,
    /// then hand over the link. Defaulted for the same reason.
    var onShareSetlist: (String) -> Void = { _ in }
    /// A book opens its own screen: you do not read a book here, you take
    /// arrangements out of it.
    var onOpenBook: (String) -> Void = { _ in }
    /// The row's ☰. Pushes to the item's screen, or expands in place, by the
    /// rule in RowMenuBehaviour.
    var onRowMenu: (LibraryRow) -> Void
    /// Naming a new piece or set list, in a band at the top of the list --
    /// not a popup and not a screen, because it is one field (§5.1).
    var onCreate: (String) -> Void
    var onImport: () -> Void
    /// A whole exported library: one folder per piece. Planned before it is run.
    var onImportPhotos: () -> Void = {}
    var onImportFolder: () -> Void = {}
    /// A collection to take arrangements out of, rather than a piece.
    var onImportBook: () -> Void = {}
    var onSettings: () -> Void
    var onRowAction: (LibraryRow, RowAction) -> Void
    var onBarAction: (LibraryAction, Set<String>, LibrarySelectionKind) -> Void

    /// Slugs of set lists that have already been promoted.
    ///
    /// From the MANIFEST, not from Firestore: `shareId` is a field on the
    /// local document (§6A.1), so a row knows it is shared without a network
    /// round trip and without being signed in.
    private var sharedSetlistIds: Set<String> {
        Set((state.manifest?.setlists ?? [])
            .filter(\.isShared).map(\.slug))
    }

    @State private var showSort = false
    @State private var showFilter = false
    /// The two verb bands (§14.3). Mutually exclusive with Sort and Filter,
    /// which is what makes them the pattern this row already had rather than
    /// a new one.
    @State private var showImport = false
    @State private var showNew = false
    @Environment(\.dynamicTypeSize) private var typeSize

    /// How tall the row's own slot is. It holds one line normally, two when
    /// the layout has run out of labels to give up, and as many as there are
    /// controls at an accessibility size -- so it is asked rather than fixed.
    private var rowHeight: CGFloat {
        let labels = LibraryBarMetrics.labels(sort: sort, filters: filters.count,
                                              editing: editing, size: typeSize)
        let fit = LibraryBarLayout.fit(width: measuredRowWidth, labels: labels,
                                       accessibilitySize: typeSize.isAccessibilitySize)
        let line = max(LibraryActionRow.height, labels.iconButton + 12)
        if fit.list { return line * 5 + LibraryActionRow.gap * 4 }
        if fit.wraps { return line * 2 + LibraryActionRow.gap }
        return line
    }

    /// The width the row was last given, measured by the row itself.
    @State private var measuredRowWidth: CGFloat = 0
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
                Theme.Rule()
                list
            }
            .background(Theme.Surface.band)
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
                                                             : Color.clear,
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
        .overlay(alignment: .top) { Theme.Rule() }
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
    }

    /// The library's top row: the gear, and nothing else (#48-#50).
    ///
    /// Help and the inbox were drawn and inert -- a "?" that opened nothing and
    /// a tray whose count was the only true thing about it. The engine chip
    /// went with them at Ali's word: which engine is running is a settled
    /// question he does not want restated on the screen he reads music from,
    /// and Settings still says it (and says it properly, with the mode and the
    /// reachability separated).
    private var topRow: some View {
        HStack(spacing: Theme.Metric.s8) {
            PanelIconButton(systemName: "gearshape", label: "Settings",
                            action: onSettings)
                .accessibilityIdentifier("library-settings")
            Spacer()
        }
        // Centred on the ROW rather than placed in it, so the gear's width
        // does not push it off centre -- and as an overlay it cannot make the
        // row taller either.
        .overlay { BuildStampLine() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Metric.s8) {
            Text("My library").typeRole(.title).foregroundStyle(Theme.Ink.ink)
            // a phrase, not a bare number: "My library 1" names nothing, and
            // "My library 0" is a count where a new reader needs a sentence
            Text(LibraryModel.countPhrase(segment: segment, rows: rows))
                .typeRole(.data).foregroundStyle(Theme.Ink.ink3)
                .accessibilityIdentifier("library-count")
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
                // What the row can DRAW, measured at the text size in force.
                // It used to strip five labels below 700pt and then draw
                // whatever was left, however wide -- so a phone got five
                // unlabelled squares AND an overflow off both edges (§14).
                let labels = LibraryBarMetrics.labels(
                    sort: sort, filters: filters.count, editing: editing,
                    size: typeSize)
                let fit = LibraryBarLayout.fit(
                    width: geo.size.width, labels: labels,
                    accessibilitySize: typeSize.isAccessibilitySize)
                actionRow(fit, labels: labels)
                    .frame(width: geo.size.width, alignment: .leading)
                    .onAppear { measuredRowWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, new in
                        measuredRowWidth = new
                    }
            }
            .frame(height: rowHeight)

            if showImport { RevealBand { importOptions } }
            if showNew { RevealBand { newOptions } }
            if showSort { RevealBand { sortOptions } }
            if showFilter { RevealBand { filterOptions } }
        }
        .padding(.horizontal, LibraryActionRow.sidePadding)
        .padding(.top, Theme.Metric.s12)
        .padding(.bottom, LibraryActionRow.spaceBelowRow)
    }

    /// The row, in whatever shape it fits.
    ///
    /// Five of the seven controls were two verbs (§14.2): three flavours of
    /// Import and two of New, drawn at compact width as five unlabelled
    /// squares -- two of whose glyphs, a plain square and three lines, name
    /// nothing at all. They collapse into `Import ▾` and `New ▾`, each opening
    /// a band beneath the row that lists its variants in words. That is the
    /// pattern Sort and Filter already use IN THIS ROW, so it costs no new
    /// concept, no scroll, no menu and no permanent second row.
    @ViewBuilder
    private func actionRow(_ fit: LibraryBarLayout.Fit,
                           labels: LibraryBarLayout.Labels) -> some View {
        let controls = [LibraryVerb.importing, .creating]
        if fit.list {
            // §6.3 rule 4: at an accessibility size a row of more than three
            // controls is a vertical list.
            VStack(alignment: .leading, spacing: LibraryActionRow.gap) {
                ForEach(controls) { verb in verbButton(verb, labelled: true, labels: labels) }
                sortButton(fit, labels: labels)
                filterButton(fit, labels: labels)
                editButton(fit, labels: labels)
            }
        } else if fit.wraps {
            // The FLOOR, not the fix: every label has yielded and it still
            // does not fit.
            VStack(alignment: .leading, spacing: LibraryActionRow.gap) {
                HStack(spacing: LibraryActionRow.gap) {
                    ForEach(controls) { verb in verbButton(verb, labelled: false, labels: labels) }
                    Spacer(minLength: 0)
                }
                HStack(spacing: LibraryActionRow.gap) {
                    sortButton(fit, labels: labels)
                    filterButton(fit, labels: labels)
                    editButton(fit, labels: labels)
                    Spacer(minLength: 0)
                }
            }
        } else {
            HStack(spacing: LibraryActionRow.gap) {
                verbButton(.importing, labelled: fit.importLabelled, labels: labels)
                verbButton(.creating, labelled: fit.newLabelled, labels: labels)
                Spacer(minLength: LibraryActionRow.clusterGap)
                sortButton(fit, labels: labels)
                filterButton(fit, labels: labels)
                editButton(fit, labels: labels)
            }
        }
    }

    private func verbButton(_ verb: LibraryVerb, labelled: Bool,
                            labels: LibraryBarLayout.Labels) -> some View {
        Button {
            switch verb {
            case .importing: toggle(.importing)
            case .creating:  toggle(.creating)
            }
        } label: {
            rowButton(verb.title, glyph: verb.glyph, iconOnly: !labelled,
                      active: verb == .importing ? showImport : showNew,
                      icon: labels.iconButton)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(verb.identifier)
        .accessibilityLabel(verb.title)
    }

    private func sortButton(_ fit: LibraryBarLayout.Fit,
                            labels: LibraryBarLayout.Labels) -> some View {
        Button { toggle(.sort) } label: {
            rowButton(sortTitle(fit.sort), glyph: "arrow.up.arrow.down",
                      iconOnly: false, icon: labels.iconButton)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library-sort")
    }

    private func sortTitle(_ style: LibraryBarLayout.SortStyle) -> String {
        switch style {
        case .full:  return "Sort: \(sort.buttonLabel)"
        case .short: return "Sort: \(sort.shortButtonLabel)"
        case .bare:  return "Sort"
        }
    }

    private func filterButton(_ fit: LibraryBarLayout.Fit,
                              labels: LibraryBarLayout.Labels) -> some View {
        Button { toggle(.filter) } label: {
            rowButton(filters.isEmpty ? "Filter" : "Filter · \(filters.count)",
                      glyph: "line.3.horizontal.decrease",
                      iconOnly: !fit.filterLabelled, icon: labels.iconButton)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library-filter")
    }

    private func editButton(_ fit: LibraryBarLayout.Fit,
                            labels: LibraryBarLayout.Labels) -> some View {
        Button { editing.toggle() } label: {
            rowButton(editing ? "Done" : "Edit", glyph: "checkmark.circle",
                      iconOnly: !fit.editLabelled, active: editing,
                      icon: labels.iconButton)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library-edit")
    }

    private enum Band { case importing, creating, sort, filter }

    /// Open one band, closing the rest.
    ///
    /// The four are mutually exclusive, as Sort and Filter always were: one
    /// answer open at a time, and no floating menus
    /// (NAV_MODAL_FREE_0.4.2). Written as ONE function that clears everything
    /// and then opens the one asked for -- the first version toggled the band
    /// and then called a closer that cleared it again, so Sort opened and shut
    /// in the same tap and its band never appeared.
    private func toggle(_ band: Band) {
        let wasOpen: Bool
        switch band {
        case .importing: wasOpen = showImport
        case .creating:  wasOpen = showNew
        case .sort:      wasOpen = showSort
        case .filter:    wasOpen = showFilter
        }
        showImport = false
        showNew = false
        showSort = false
        showFilter = false
        guard !wasOpen else { return }
        switch band {
        case .importing: showImport = true
        case .creating:  showNew = true
        case .sort:      showSort = true
        case .filter:    showFilter = true
        }
    }

    /// What `Import ▾` reveals: the three things it can take, in words. Three
    /// glyphs a reader has to guess become three names.
    private var importOptions: some View {
        // ROWS, not a line of chips (§15). Each carries the one line that says
        // what it takes -- and that line is what keeps Score findable for a
        // picture already in Files, now that a picture has no row of its own.
        VStack(alignment: .leading, spacing: 0) {
            ForEach(LibraryQuickAction.imports) { action in
                Button { showImport = false; run(action) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.bandTitle).typeRole(.row)
                            .foregroundStyle(Theme.Ink.ink)
                        Text(action.bandSubtitle).typeRole(.meta)
                            .foregroundStyle(Theme.Ink.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.Metric.s6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(action.identifier)
                // The rule after Photos IS the meaning: above it, one
                // arrangement out of one thing; below it, a collection.
                if action == LibraryQuickAction.importsDividerAfter {
                    Rectangle().fill(Theme.Line.line)
                        .frame(height: 1)
                        .padding(.vertical, Theme.Metric.s6)
                }
            }
        }
    }

    private var newOptions: some View {
        HStack(spacing: Theme.Metric.s6) {
            ForEach(LibraryQuickAction.creations) { action in
                Button { showNew = false; run(action) } label: {
                    controlLabel(action.bandTitle)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(action.identifier)
            }
            Spacer()
        }
    }

    private func run(_ action: LibraryQuickAction) {
        switch action {
        case .importScore:  onImport()
        case .importPhotos: onImportPhotos()
        case .importFolder: onImportFolder()
        case .importBook:   onImportBook()
        case .new:          creatingName = ""
        case .newSetlist:   segment = .setlists; creatingName = ""
        }
    }

    /// One button of the action row: 32pt, bordered, panel fill, no emphasis.
    /// At four buttons in a bar a clay fill would shout, and the accent belongs
    /// to selection and to `#N` (§4C).
    private func rowButton(_ text: String, glyph: String,
                           iconOnly: Bool, active: Bool = false,
                           icon: CGFloat = LibraryActionRow.buttonHeight) -> some View {
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
        // The icon square is SCALED (`LibraryBarMetrics.iconButton`): a flat
        // 32 clips the glyph inside it at an accessibility size, and told the
        // row's arithmetic the button never changes width while its content
        // did (§6.3 rule 2).
        .frame(width: iconOnly ? icon : nil)
        .frame(minHeight: icon)
        .background(active ? Theme.Accent.clayTint : Theme.Surface.panel)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                .stroke(active ? Theme.Accent.clay : Color.clear, lineWidth: 1.5)
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
                    .stroke(active ? Theme.Accent.clay : Color.clear, lineWidth: 1.5)
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
            // The content column is CAPPED AND CENTRED, the same rule `Screen`
            // applies to every pushed screen (L34, and A-B of
            // design/IPHONE_0.6.14.md). Full-bleed rows put a title and its own
            // chevron 1200pt apart on a landscape phone and 1300 on a 13-inch
            // iPad, and at that distance a row stops reading as one thing.
            //
            // The library was the one list that never got it, and the test that
            // caught that -- LandscapeFits.testTheLibraryFitsInLandscape --
            // arrived with the landscape work asserting behaviour nobody had
            // written: it fails on dev too, not only here.
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
                    Theme.Rule()
                }

                // Imports in flight, at the top where they cannot be missed.
                //
                // They used to render only in the score screen's library
                // overlay, which the redesign retired -- so an import showed a
                // badge on a Home icon that was not tappable and then could
                // not be found at all (0.4.1 item 9).
                // ...and each in the list it is making something FOR: a book
                // being read is not an arrangement arriving (ImportProgress).
                ForEach(pendingHere) { pending in importingRow(pending) }
                // Loading is not emptiness (#42): the manifest is nil until the
                // engine answers, and claiming "No music yet" in that window
                // flashed the empty state on every launch of a full library.
                // No shared-set-list band. §6A.1: there is ONE kind of set
                // list and sharing is a field on it, so a shared set list is
                // an ordinary row in this list -- it does not move, and it is
                // not listed twice.
                switch LibraryModel.listState(loaded: state.libraryLoaded,
                                              rows: rows.count,
                                              pendingImports: pendingHere.count,
                                              isFiltered: !search.isEmpty || !filters.isEmpty) {
                case .rows:      grouped
                case .loading:   loading
                case .empty, .noMatches: empty
                }
            }
            // FULL WIDTH. The reading-column cap was a deliberate design and
            // Ali reversed it on 2026-09-10 with a screenshot: two thirds of an
            // iPad landscape screen empty either side of the list, every row's
            // subtitle truncated at "..." in the middle. The list is a list,
            // not a page of prose; it gets the width it is given.
            .frame(maxWidth: .infinity)
            .padding(.bottom, 90)
            // The build stamp used to end this scroll view. It is in the top
            // row now: a tester should not have to scroll past their whole
            // library to say which build they are on (#53).
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
                    // BandHeader rather than a hand-rolled Text: it was a tiny
                    // lowercase "s" on an unruled 18pt strip, which is not what
                    // a section header looks like anywhere else in the app
                    // (§12.6). One component, so it cannot drift again.
                    BandHeader(title: group.letter, role: .titleS) { EmptyView() }
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
                // The ☰ stays in EDIT mode too. It was swapped for a chevron
                // there, which undoes the rule the row was just given (L14):
                // the ☰ is the one control a row carries, and a chevron beside
                // a checkbox is a second thing pretending to be one.
                LRow(row: row, identifier: "row-\(row.id)",
                     action: { editing ? toggle(row) : open(row) },
                     onMenu: { onRowMenu(row) },
                     // Set lists ONLY. Books and sources have no share path
                     // at all -- guard rails 3 and 4 stand unamended (§8.2),
                     // so this is absent rather than disabled for them.
                     onShare: segment == .setlists && !editing
                              ? { onShareSetlist(row.id) } : nil,
                     isShared: sharedSetlistIds.contains(row.id))
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
            Theme.Rule()
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
                .frame(width: Theme.Metric.checkboxGutter,
                       height: Theme.Metric.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("row-select-\(row.id)")
        .accessibilityLabel("Select \(row.title)")
        .accessibilityAddTraits(selected.contains(row.id) ? [.isSelected] : [])
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
            Theme.Rule()
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
    // Edit mode no longer repeats each row's actions underneath it (L22).
    // Versions / Set lists / Delete were drawn per row AND in the action bar
    // at the bottom, which is the same verbs twice with different scope: the
    // bar acts on everything ticked, the row buttons on one row. The division
    // is the one the row already states -- the action bar owns what you have
    // selected, the ☰ owns the row it sits on -- and the ☰ is now present in
    // both modes, so nothing lost a way in.

    /// Still looking. It says so quietly and takes the same room the list will,
    /// so the screen does not jump when the rows arrive.
    private var loading: some View {
        StateView(systemImage: "music.note.list",
                  title: "Opening your library…",
                  identifier: "library-loading")
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Metric.s32)
    }

    /// The empty library is the app's FIRST screen now (§4C), so it is a STATE
    /// rather than a sentence in the top-left corner: centred glyph, title,
    /// one line of help, and the one button that resolves it.
    ///
    /// The action row stays above it either way -- the state's Import and the
    /// row's Import are the same action, and a new reader should find it
    /// wherever they look first.
    @ViewBuilder
    private var empty: some View {
        if search.isEmpty && filters.isEmpty {
            let empty = LibraryModel.emptyState(segment: segment)
            StateView(systemImage: empty.systemImage,
                      title: empty.title,
                      message: empty.message,
                      actionTitle: empty.actionTitle,
                      actionKind: .primary,
                      identifier: "library-empty",
                      action: {
                          switch segment {
                          case .pieces:   onImport()
                          case .books:    onImportBook()
                          case .setlists: creatingName = ""
                          }
                      })
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Metric.s32)
        } else {
            StateView(systemImage: "magnifyingglass",
                      title: "No matches",
                      message: "Nothing here matches what you are looking for.",
                      identifier: "library-empty")
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Metric.s32)
        }
    }

    // The `+` FAB and its New/Import band are gone (§4C). They offered
    // exactly what the action row now shows permanently, which makes the row
    // the de-duplication rather than a second way in.

    // MARK: - Data

    /// The imports in flight that belong to the segment on screen.
    private var pendingHere: [AppState.PendingImport] {
        state.pendingImports.filter { $0.target.segment == segment }
    }

    private var rows: [LibraryRow] {
        guard let manifest = state.manifest else { return [] }
        var base: [LibraryRow]
        switch segment {
        case .pieces:
            base = LibraryModel.pieceRows(manifest: manifest)
                + LibraryModel.unfiledRows(manifest: manifest)
        case .setlists:
            base = LibraryModel.setlistRows(manifest: manifest)
        case .books:
            base = LibraryModel.bookRows(manifest: manifest)
        }
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
        if segment == .books {
            onOpenBook(row.id)
            return
        }
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
