import SwiftUI

import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var showChat = true
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var didSetInitialChat = false
    /// Piece rows are expanded by default; track only the collapsed ones.
    @State private var collapsedPieces: Set<String> = []
    /// Setlist rows are expanded by default; track only the collapsed ones.
    @State private var collapsedSetlists: Set<String> = []
    /// Version prompt-groups are collapsed by default; track the expanded ones.
    @State private var expandedVersionGroups: Set<String> = []
    @State private var pendingDelete: ScoreDoc?
    @State private var infoScore: ScoreDoc?
    /// Score awaiting a "New piece…" name (drives the naming alert).
    @State private var newPieceTarget: ScoreDoc?
    @State private var newPieceName = ""
    /// Piece the file importer should file its result under (set by a piece's
    /// "Import a file into this piece"); nil = the toolbar's unfiled import.
    @State private var importTargetPiece: String?

    private static let scoreTypes: [UTType] = ([
        UTType(filenameExtension: "musicxml"),
        UTType(filenameExtension: "mxl"),
        UTType(filenameExtension: "xml"),
        UTType(filenameExtension: "mid"),
        UTType(filenameExtension: "midi"),
    ].compactMap { $0 }) + [.pdf]

    /// Which column shows in compact width — set to .detail to open a score.
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar

    /// Build identity, composed at runtime from the bundle so the number shown
    /// here is exactly CFBundleVersion, i.e. the build number App Store Connect
    /// records. Only the git sha is baked in (it isn't in Info.plist).
    static let buildStamp: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let sha = (Bundle.main.url(forResource: "build-sha", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) })?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "v\(version) · b\(build)" + (sha.map { " · \($0)" } ?? "")
    }()

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            sidebar
        } detail: {
            detail
        }
        .task {
            state.startPolling()
        }
    }

    private func openScore(_ slug: String, version: String? = nil) {
        state.select(slug: slug, version: version)
        compactColumn = .detail
    }

    // MARK: sidebar

    // The sidebar is the app's statement of the hierarchy: setlists hold
    // pieces, pieces hold numbered arrangements, arrangements hold versions.
    // Split into per-section builders — as one expression the SwiftUI type
    // checker gives up on it.
    private var sidebar: some View {
        // Plain List — no selection binding: the system's row selection fought
        // the per-row buttons (eaten taps, three competing highlight colors).
        // Highlight is ours alone; navigation goes through openScore.
        List {
            statusSection
            setlistsSection
            piecesSection
            unfiledSection
            versionsSection
        }
        .navigationTitle("Scoranger")
        .safeAreaInset(edge: .bottom) {
            // always-visible build identity (baked at build time)
            Text(Self.buildStamp)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Circle()
                    .fill(state.engineOK ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                    .accessibilityLabel(state.engineOK ? "Engine connected" : "Engine unreachable")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if state.useLocalEngine {
                    Button {
                        importTargetPiece = nil
                        showImporter = true
                    } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Import an arrangement")
                }
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $infoScore) { ScoreInfoView(score: $0) }
        .alert(
            "Delete \(pendingDelete?.name ?? "arrangement")?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let score = pendingDelete { state.deleteScore(slug: score.slug) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This removes the arrangement and all its versions. The piece and its other arrangements are untouched.")
        }
        .alert("New piece", isPresented: Binding(
            get: { newPieceTarget != nil },
            set: { if !$0 { newPieceTarget = nil } }
        )) {
            TextField("Piece name", text: $newPieceName)
            Button("OK") {
                let name = newPieceName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let score = newPieceTarget, !name.isEmpty {
                    state.createPieceAndAssign(name: name, scoreSlug: score.slug)
                }
                newPieceTarget = nil
            }
            Button("Cancel", role: .cancel) { newPieceTarget = nil }
        } message: {
            Text("File “\(newPieceTarget?.name ?? "this arrangement")” under a new piece.")
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: Self.scoreTypes) { result in
            let piece = importTargetPiece
            importTargetPiece = nil
            // receiveFile routes by type: PDFs -> cloud OMR, scores -> direct import
            if case .success(let url) = result {
                state.receiveFile(at: url, intoPiece: piece)
            }
        }
        .alert("Scoranger", isPresented: Binding(
            get: { state.notice != nil },
            set: { if !$0 { state.notice = nil } }
        )) {
            Button("OK", role: .cancel) { state.notice = nil }
        } message: {
            Text(state.notice ?? "")
        }
    }

    /// Engine startup and in-flight PDF conversions.
    @ViewBuilder
    private var statusSection: some View {
        Section {
            if state.manifest == nil {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("starting engine…")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            ForEach(state.pendingImports) { pending in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(pending.name)
                        Spacer()
                        if pending.fraction == nil {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    if let fraction = pending.fraction {
                        ProgressView(value: fraction)
                            .controlSize(.small)
                    }
                    Text(pending.stage)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Setlists: ordered groups of pieces; tapping a piece expands it under
    /// Pieces and opens its first arrangement.
    @ViewBuilder
    private var setlistsSection: some View {
        if !state.setlistSections.isEmpty {
            Section("Setlists") {
                ForEach(state.setlistSections, id: \.setlist.slug) { section in
                    setlistRow(section.setlist)
                    if !collapsedSetlists.contains(section.setlist.slug) {
                        ForEach(section.pieces) { piece in
                            setlistPieceRow(piece)
                        }
                    }
                }
            }
        }
    }

    /// Each piece is an expandable row whose children are its numbered
    /// arrangements. Plain rows with an explicit chevron button instead of
    /// DisclosureGroup: buttons inside DisclosureGroup labels get swallowed by
    /// the disclosure tap target on iPad sidebar lists.
    @ViewBuilder
    private var piecesSection: some View {
        if !state.pieceSections.isEmpty {
            Section("Pieces") {
                ForEach(state.pieceSections, id: \.piece.slug) { section in
                    pieceRow(section)
                    if !collapsedPieces.contains(section.piece.slug) {
                        // .onMove would fight the rows' onDrag (used for filing
                        // onto pieces), so reordering is offered via the rows'
                        // context menu instead.
                        ForEach(Array(section.arrangements.enumerated()),
                                id: \.element.slug) { index, score in
                            arrangementRow(score, number: index + 1, inPiece: section)
                        }
                    }
                }
            }
        }
    }

    /// Arrangements not filed under any piece. Same row design as filed ones,
    /// but no number: "#N" is defined within a piece, and that is exactly what
    /// chat prompts refer to.
    @ViewBuilder
    private var unfiledSection: some View {
        if !state.unfiledScores.isEmpty {
            Section((state.manifest?.pieces ?? []).isEmpty
                    ? "Arrangements" : "Unfiled arrangements") {
                ForEach(state.unfiledScores) { score in
                    arrangementRow(score)
                }
            }
        }
    }

    /// Version history of the open arrangement; tapping a version opens the
    /// score pinned to it. Versions made by one chat prompt collapse into an
    /// expandable group faced by the prompt's final state.
    /// Follows whatever the score pane shows: now that a row tap opens the
    /// arrangement, "previewed" and "open" are the same thing, so this can no
    /// longer end up describing some unrelated arrangement's history.
    @ViewBuilder
    private var versionsSection: some View {
        if let score = state.selectedScore {
            let slug = score.slug
            Section(versionsSectionTitle(slug: slug, name: score.name)) {
                // explicit caret buttons (DisclosureGroup labels swallow button
                // taps on iPad sidebar lists)
                ForEach(state.versionGroups(for: score)) { group in
                    if group.subs.isEmpty {
                        versionRow(score, group.face)
                    } else {
                        versionGroupRow(score, group)
                        if expandedVersionGroups.contains(group.id) {
                            ForEach(group.subs.reversed()) { v in
                                versionRow(score, v)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
    }

    private func versionsSectionTitle(slug: String, name: String) -> String {
        if let placement = state.placement(of: slug) {
            return "Versions of #\(placement.number) \(name)"
        }
        return "Versions of \(name)"
    }

    /// Piece currently under a drag, for the drop highlight.
    @State private var dropTargetPiece: String?

    /// Piece title row: an explicit caret button (expand/collapse), the drop
    /// zone for filing dragged arrangements, and a menu of ways to add an
    /// arrangement to the piece. Highlights while a drag hovers over it.
    private func pieceRow(_ section: (piece: PieceDoc, arrangements: [ScoreDoc])) -> some View {
        let piece = section.piece
        let collapsed = collapsedPieces.contains(piece.slug)
        return HStack(spacing: 4) {
            Button {
                withAnimation {
                    if collapsed { collapsedPieces.remove(piece.slug) }
                    else { collapsedPieces.insert(piece.slug) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(piece.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("\(section.arrangements.count) arrangement"
                             + (section.arrangements.count == 1 ? "" : "s"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .tint(.primary)
            .accessibilityLabel("\(collapsed ? "Expand" : "Collapse") \(piece.name)")
            addArrangementMenu(section)
        }
        .padding(.vertical, 4)
        .listRowBackground(dropTargetPiece == piece.slug
                           ? Color.orange.opacity(0.3) : nil)
        .onDrop(of: [.plainText],
                isTargeted: Binding(
                    get: { dropTargetPiece == piece.slug },
                    set: { dropTargetPiece = $0 ? piece.slug : nil }
                )) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let slug = object as? String else { return }
                Task { @MainActor in
                    state.assignToPiece(scoreSlug: slug, piece: piece.slug)
                }
            }
            return true
        }
    }

    /// The three ways to add an arrangement to a piece. Blank-then-chat is the
    /// core workflow; duplicating an existing arrangement is the usual starting
    /// point in practice ("a string quartet version of #1").
    private func addArrangementMenu(
        _ section: (piece: PieceDoc, arrangements: [ScoreDoc])) -> some View {
        Menu {
            Button {
                Task {
                    if let slug = await state.createArrangement(pieceSlug: section.piece.slug,
                                                                name: "New arrangement") {
                        openScore(slug)
                        showChat = true
                    }
                }
            } label: {
                Label("New blank arrangement", systemImage: "doc")
            }
            if !section.arrangements.isEmpty {
                Menu {
                    ForEach(Array(section.arrangements.enumerated()),
                            id: \.element.slug) { index, score in
                        Button("#\(index + 1)  \(score.name)") {
                            Task {
                                if let slug = await state.duplicateScore(
                                    slug: score.slug, name: "\(score.name) copy") {
                                    openScore(slug)
                                    showChat = true
                                }
                            }
                        }
                    }
                } label: {
                    Label("Duplicate an arrangement", systemImage: "plus.square.on.square")
                }
            }
            Button {
                importTargetPiece = section.piece.slug
                showImporter = true
            } label: {
                Label("Import a file into this piece", systemImage: "square.and.arrow.down")
            }
        } label: {
            Image(systemName: "plus.circle")
                .foregroundStyle(.secondary)
                .frame(minWidth: 32, minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Add an arrangement to \(section.piece.name)")
    }

    /// Setlist title row: explicit caret, like pieces.
    private func setlistRow(_ setlist: SetlistDoc) -> some View {
        let collapsed = collapsedSetlists.contains(setlist.slug)
        return Button {
            withAnimation {
                if collapsed { collapsedSetlists.remove(setlist.slug) }
                else { collapsedSetlists.insert(setlist.slug) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                Image(systemName: "music.note.list")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(setlist.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(collapsed ? "Expand" : "Collapse") setlist \(setlist.name)")
    }

    /// A piece inside a setlist: tap expands the piece in Pieces and opens its
    /// first arrangement, matching tap-to-open everywhere else.
    private func setlistPieceRow(_ piece: PieceDoc) -> some View {
        let arrangements = state.pieceSections
            .first { $0.piece.slug == piece.slug }?.arrangements ?? []
        return Button {
            collapsedPieces.remove(piece.slug)
            if let first = arrangements.first { openScore(first.slug) }
        } label: {
            HStack {
                Text(piece.name)
                Spacer()
                Text("\(arrangements.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.leading, 16)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
    }

    /// An arrangement row. `number`/`inPiece` are set for rows inside a piece:
    /// the number shows as the prominent "#N" badge chat prompts refer to, and
    /// the piece enables Move up/down in the context menu.
    /// Tapping anywhere on the row opens the arrangement in the score pane.
    private func arrangementRow(_ score: ScoreDoc, number: Int? = nil,
                                inPiece section: (piece: PieceDoc, arrangements: [ScoreDoc])? = nil) -> some View {
        HStack(spacing: 8) {
            Button {
                openScore(score.slug)
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    if let number {
                        // the handle the user types in chat ("from #3"): big,
                        // accent-colored, and deliberately unlike the small
                        // grey version/part counts underneath
                        Text("#\(number)")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.accentColor)
                            .frame(minWidth: 38, alignment: .leading)
                            .accessibilityLabel("Arrangement number \(number)")
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(score.name)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(arrangementSubtitle(score))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            // .borderless tints its whole label with the accent color, which
            // would make the name compete with the #N badge; the badge sets its
            // accent explicitly, so neutralise the inherited tint here.
            .tint(.primary)
            .accessibilityIdentifier("arrangement-\(score.slug)")
            rowIcon("info.circle", label: "Arrangement details") { infoScore = score }
        }
        // one highlight system only: warm attention color on the open row.
        // selectedScore, not selectedSlug: at launch the detail pane falls back
        // to the most recent arrangement without anything being tapped, and the
        // sidebar has to agree with what the score pane is showing.
        .listRowBackground(
            state.selectedScore?.slug == score.slug ? Color.orange.opacity(0.22) : nil)
        // long-press-drag an arrangement onto a piece row to file it
        // (NSItemProvider pairs with the onDrop handler on piece rows)
        .onDrag { NSItemProvider(object: score.slug as NSString) }
        .contextMenu {
            // Move up/down renumbers the arrangement, i.e. changes the #N chat
            // refers to, so it is worth the explicit labels.
            if let section, let number {
                let index = number - 1
                let slugs = section.arrangements.map(\.slug)
                if index > 0 {
                    Button {
                        var order = slugs
                        order.swapAt(index, index - 1)
                        state.reorderPiece(piece: section.piece.slug, order: order)
                    } label: {
                        Label("Move up (become #\(number - 1))", systemImage: "arrow.up")
                    }
                }
                if index < slugs.count - 1 {
                    Button {
                        var order = slugs
                        order.swapAt(index, index + 1)
                        state.reorderPiece(piece: section.piece.slug, order: order)
                    } label: {
                        Label("Move down (become #\(number + 1))", systemImage: "arrow.down")
                    }
                }
            }
            Button {
                Task { await state.duplicateScore(slug: score.slug,
                                                  name: "\(score.name) copy") }
            } label: {
                Label("Duplicate arrangement", systemImage: "plus.square.on.square")
            }
            Menu("Move to piece") {
                // full manifest list, including pieces with no arrangements yet
                ForEach(state.manifest?.pieces ?? []) { piece in
                    Button {
                        state.assignToPiece(scoreSlug: score.slug, piece: piece.slug)
                    } label: {
                        if score.piece == piece.slug {
                            Label(piece.name, systemImage: "checkmark")
                        } else {
                            Text(piece.name)
                        }
                    }
                }
                Divider()
                Button("New piece…") {
                    newPieceName = ""
                    newPieceTarget = score
                }
            }
            if score.piece != nil {
                Button("Remove from piece") {
                    state.assignToPiece(scoreSlug: score.slug, piece: nil)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            // non-destructive role: the row shouldn't vanish before the
            // confirmation alert is answered
            Button { pendingDelete = score } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    /// Trailing per-row icon button; borderless so it doesn't hijack the row
    /// tap, sized for a comfortable finger target.
    private func rowIcon(_ systemName: String, label: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundStyle(.secondary)
                .frame(minWidth: 32, minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    /// What distinguishes one arrangement of a piece from another: what it is
    /// scored for, then how far it has been worked (versions) and what it has
    /// to draw on (sources).
    private func arrangementSubtitle(_ score: ScoreDoc) -> String {
        var bits: [String] = []
        let parts = (score.versions.first { $0.id == score.latest }
                     ?? score.versions.last)?.parts ?? []
        if !parts.isEmpty {
            let names = parts.map(\.name)
            bits.append(names.count <= 3
                        ? names.joined(separator: ", ")
                        : names.prefix(2).joined(separator: ", ") + " +\(names.count - 2) more")
        }
        bits.append("\(score.versions.count) version\(score.versions.count == 1 ? "" : "s")")
        if let n = score.sources?.count, n > 0 {
            bits.append("\(n) source\(n == 1 ? "" : "s")")
        }
        return bits.joined(separator: " · ")
    }

    /// A single version row: id + op, eye on the displayed version.
    private func versionRow(_ score: ScoreDoc, _ v: VersionDoc) -> some View {
        Button {
            openScore(score.slug, version: v.id == score.latest ? nil : v.id)
        } label: {
            HStack {
                Text(v.id).font(.system(.caption, design: .monospaced))
                Text(v.op).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if score.slug == state.selectedScore?.slug,
                   v.id == state.displayedVersionID {
                    Image(systemName: "eye").font(.caption2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// The face row of a prompt group: an explicit caret button expands the
    /// group's step versions; tapping the rest opens the score at the group's
    /// final version. The eye shows when any of its versions is displayed.
    private func versionGroupRow(_ score: ScoreDoc, _ group: AppState.VersionGroup) -> some View {
        let expanded = expandedVersionGroups.contains(group.id)
        return HStack(spacing: 4) {
            Button {
                withAnimation {
                    if expanded { expandedVersionGroups.remove(group.id) }
                    else { expandedVersionGroups.insert(group.id) }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(minWidth: 24, minHeight: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(expanded ? "Collapse" : "Expand") versions of this prompt")
            Button {
                openScore(score.slug,
                          version: group.face.id == score.latest ? nil : group.face.id)
            } label: {
                HStack {
                    Text(group.face.id).font(.system(.caption, design: .monospaced))
                    Text(group.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if score.slug == state.selectedScore?.slug,
                       group.subs.contains(where: { $0.id == state.displayedVersionID }) {
                        Image(systemName: "eye").font(.caption2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: detail

    @ViewBuilder
    private var detail: some View {
        if let score = state.selectedScore {
            Group {
                if hSize == .compact {
                    // iPhone: chat replaces the score pane instead of squeezing it
                    if showChat { ChatView() } else { scorePane(score) }
                } else {
                    HStack(spacing: 0) {
                        scorePane(score)
                        if showChat {
                            Divider()
                            ChatView()
                                .frame(width: 360)
                        }
                    }
                }
            }
            .onAppear {
                if !didSetInitialChat {
                    didSetInitialChat = true
                    if hSize == .compact { showChat = false }
                }
            }
            .navigationTitle(score.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { detailTitle(score) }
            .toolbar { detailToolbar }
        } else {
            ContentUnavailableView(
                "No arrangement open",
                systemImage: "music.quarternote.3",
                description: Text(!state.engineOK && !state.useLocalEngine
                    ? "Engine unreachable — check the URL in Settings and that `scor serve` is running on your Mac."
                    : "Pick an arrangement in the sidebar, or tap + to import a MusicXML, MIDI, or PDF file."))
        }
    }

    /// The open arrangement's place in the hierarchy, carried into the title
    /// bar: piece above, "#N name" below. Without this the detail pane gives no
    /// clue which piece the score on screen belongs to.
    @ToolbarContentBuilder
    private func detailTitle(_ score: ScoreDoc) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            let placement = state.placement(of: score.slug)
            VStack(spacing: 0) {
                if let placement {
                    Text(placement.piece.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    if let placement {
                        Text("#\(placement.number)")
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(score.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func scorePane(_ score: ScoreDoc) -> some View {
        ZStack {
            if let doc = state.pdfDocument, let vid = state.displayedVersionID {
                if hSize == .compact {
                    // iPhone: zoomable read-only view; pencil markup is iPad-only
                    ScoreZoomView(document: doc)
                } else {
                    ScorePagesView(document: doc, annotationKey: "\(score.slug)/\(vid)")
                }
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
            versionsMenu
            gearMenu
            Button { showChat.toggle() } label: {
                Label("Chat", systemImage: showChat ? "sidebar.trailing" : "bubble.left.and.text.bubble.right")
            }
        }
    }

    /// Version picker mirroring the sidebar's Versions section, so version
    /// hopping works without opening the sidebar (essential on iPhone).
    /// Prompt groups appear as one entry (tap = the group's final version)
    /// with a nested menu of the step versions.
    @ViewBuilder
    private var versionsMenu: some View {
        if let score = state.selectedScore {
            Menu {
                ForEach(state.versionGroups(for: score)) { group in
                    if group.subs.isEmpty {
                        versionMenuButton(score, group.face, title: group.title)
                    } else {
                        Menu {
                            ForEach(group.subs.reversed()) { v in
                                versionMenuButton(score, v, title: v.op)
                            }
                        } label: {
                            if group.subs.contains(where: { $0.id == state.displayedVersionID }) {
                                Label("\(group.face.id) · \(shortTitle(group.title))",
                                      systemImage: "checkmark")
                            } else {
                                Text("\(group.face.id) · \(shortTitle(group.title))")
                            }
                        } primaryAction: {
                            pinVersion(group.face, in: score)
                        }
                    }
                }
            } label: {
                Text(state.displayedVersionID ?? "")
                    .font(.system(.caption, design: .monospaced))
            }
            .accessibilityLabel("Versions")
        }
    }

    private func versionMenuButton(_ score: ScoreDoc, _ v: VersionDoc,
                                   title: String) -> some View {
        Button {
            pinVersion(v, in: score)
        } label: {
            if v.id == state.displayedVersionID {
                Label("\(v.id) · \(shortTitle(title))", systemImage: "checkmark")
            } else {
                Text("\(v.id) · \(shortTitle(title))")
            }
        }
    }

    private func pinVersion(_ v: VersionDoc, in score: ScoreDoc) {
        state.pinnedVersion = (v.id == score.latest) ? nil : v.id
        Task { await state.renderIfNeeded() }
    }

    private func shortTitle(_ title: String) -> String {
        title.count > 40 ? title.prefix(40).trimmingCharacters(in: .whitespaces) + "…" : title
    }

    private var gearMenu: some View {
        Menu {
            Button { state.transpose(semitones: 1) } label: {
                Label("Transpose up a semitone", systemImage: "arrow.up")
            }
            Button { state.transpose(semitones: -1) } label: {
                Label("Transpose down a semitone", systemImage: "arrow.down")
            }
            Toggle("Use flats", isOn: Binding(
                get: { state.useFlats[state.selectedScore?.slug ?? "", default: true] },
                set: { newValue in
                    if let slug = state.selectedScore?.slug {
                        state.useFlats[slug] = newValue
                    }
                    state.respell(preferFlats: newValue)
                }
            ))
            if hSize != .compact {
                Button {
                    if let score = state.selectedScore, let vid = state.displayedVersionID {
                        DrawingStore.shared.clear(prefix: "\(score.slug)/\(vid)")
                        // force page reload to drop canvases' in-memory drawings
                        Task { await state.renderIfNeeded(force: true) }
                    }
                } label: {
                    Label("Clear markup", systemImage: "pencil.slash")
                }
            }
        } label: {
            Label("Score options", systemImage: "gearshape")
        }
    }
}
