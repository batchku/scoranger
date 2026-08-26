import Foundation
import PDFKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var manifest: Manifest?
    /// Whether the library has been looked for yet.
    ///
    /// Distinct from "the library is empty": at launch the manifest is nil and
    /// the engine has not answered, which looked exactly like a user with no
    /// scores -- so the empty state flashed up for a moment before the library
    /// arrived, and on the remote-engine path it was the alarming one ("Engine
    /// unreachable"). Nil means unknown; this says whether we have looked.
    @Published private(set) var libraryLoaded = false
    @Published var selectedSlug: String?
    /// Sidebar preview: the score whose versions the sidebar shows. Set by a
    /// plain row tap; does NOT navigate (that's `select(slug:)`).
    @Published var previewedSlug: String?
    /// nil = follow the score's latest version
    @Published var pinnedVersion: String?
    @Published var pdfDocument: PDFDocument?
    @Published var loadingPDF = false
    @Published var engineOK = false
    @Published var lastError: String?
    /// One-shot user-facing message shown as an alert (share-sheet receipts etc.)
    @Published var notice: String?
    @Published var omrBusy = false
    /// Per-score enharmonic preference backing the gear menu's "Use flats"
    /// toggle; flipping it applies a respell op. Defaults to flats.
    @Published var useFlats: [String: Bool] = [:]

    /// What the lasso caught, held by durable address so it survives the
    /// re-render every engine op triggers. This replaces the yellow-band
    /// highlight, which inferred bar numbers from where a stroke landed across
    /// the page — an estimate that was wrong as often as it was right.
    @Published var selection: ScoreSelection?
    /// Which "<slug>/<version>" the current selection was made on, and which
    /// one the loaded geometry describes.
    ///
    /// Ali saw a selection made in one arrangement appear in its duplicate.
    /// The engine's copy is genuinely independent -- `duplicate` writes a new
    /// slug, a new row and its own v001 -- and every key here is already
    /// slug-scoped, so the mechanism is still unexplained. This makes the
    /// symptom impossible regardless of the cause: a selection is only ever
    /// drawn against the engraving it was made on.
    @Published private(set) var selectionKey: String?
    private var geometryKey: String?

    /// The selection, but only if it belongs to what is on screen now.
    var activeSelection: ScoreSelection? {
        guard let selection, selectionKey != nil, selectionKey == geometryKey else { return nil }
        return selection
    }
    /// The drawn lasso per page index, in unit (0…1) page coordinates, so the
    /// outline survives zoom. Cleared with the selection.
    @Published var selectionPaths: [Int: [CGPoint]] = [:]
    /// The hit-test model for the engraving currently on screen, built from the
    /// same Verovio load that drew it.
    @Published var geometry: ScoreGeometry?
    /// Bumped to ask the UI to open chat, with text for its input: how a
    /// finished lasso shows the user that the selection registered.
    /// The setlist being played, if the score was opened from one. It is what
    /// the transport's prev/next step through -- the one part of the transport
    /// that does something (NAVIGATION_SYSTEM.md §1).
    /// The score view's own chrome state.
    ///
    /// Here rather than in the view because the view is rebuilt whenever this
    /// object publishes -- which is on every scroll, since the page counters
    /// read the visible rect -- and @State inside it was being reset under the
    /// user. A menu that will not open is the visible symptom; the cause is
    /// that the thing remembering "it is open" did not survive the next frame.
    @Published var scoreMode: ScoreMode = .read
    @Published var titleMenuOpen = false
    @Published var moreMenuOpen = false

    @Published var currentSetlist: String?
    /// Which pages are on screen, reported by the canvas. Feeds the counters
    /// and the thumbnail strip's "you are here" (NAVIGATION_SYSTEM.md 12.11).
    @Published var visiblePageIndices: [Int] = [0]
    /// Where each page sits vertically in the content, so a page turn knows
    /// what the next boundary is (§6.4).
    @Published var pageBoundaries: [CGFloat] = []
    @Published var chatOpenRequest = 0
    @Published var pendingChatInsert: String?
    /// How the next lasso combines with what is already selected. Replace until
    /// the user says otherwise; the two-finger add shortcut overrides it for
    /// one stroke without disturbing it.
    @Published var combineMode: SelectionCombine = .replace

    /// Carry a selection across a re-engrave, or drop it.
    ///
    /// An op makes a NEW VERSION of the same score, and the notes the user
    /// selected are still there -- so clearing the selection every time meant
    /// running two operations on the same passage required lassoing it twice.
    /// Addresses are durable by design (staff/measure/layer/kind#ordinal, not a
    /// rendered id), so they are simply looked up again in the new engraving.
    ///
    /// Only within one score: switching arrangement, or to an unrelated
    /// version, is a different subject and the selection goes.
    private func carrySelection(from previous: String?, to key: String,
                                into model: ScoreGeometry?) {
        guard let selection, !selection.isEmpty,
              selectionKey == previous,
              ScoreSelection.survivesReRender(from: previous, to: key,
                                              userPickedVersion: pinnedVersion != nil),
              let model else {
            clearSelection()
            return
        }
        let survived = selection.addresses.filter { model.element(at: $0) != nil }
        guard !survived.isEmpty else {
            clearSelection()
            selectionCarryNote = "The selection is gone: the edit removed everything in it."
            return
        }
        let lost = selection.addresses.count - survived.count
        self.selection = ScoreSelection(addresses: survived)
        selectionKey = key
        selectionPaths = [:]   // the drawn outline described the old engraving
        selectionCarryNote = lost == 0 ? nil
            : "\(lost) of \(selection.addresses.count) selected elements no longer exist."
    }

    /// Said once, on the chip, when an edit did not leave the selection whole.
    @Published var selectionCarryNote: String?

    /// Hand the finished selection to chat. Called by the chip's confirm
    /// button, never by a gesture.
    func confirmSelectionForChat() {
        guard let selection = activeSelection, !selection.isEmpty else { return }
        pendingChatInsert = selection.chatReference
        chatOpenRequest += 1
    }

    /// Drop the active selection and its drawn lasso.
    ///
    /// The mode goes with it: it is meaningless without a selection, and
    /// leaving it set is what trapped the user in Subtract.
    func clearSelection() {
        selection = nil
        selectionPaths = [:]
        selectionKey = nil
        combineMode = .replace
    }

    /// A finished lasso: what it caught, drawn where it was drawn, handed to
    /// chat so the next prompt can refer to it.
    func commitSelection(_ elements: [ScoreElement], path: [CGPoint], page: Int,
                         adding: Bool = false) {
        // the two-finger shortcut adds for this stroke only; the chip's mode is
        // what the user set and is left alone
        let mode: SelectionCombine = adding ? .add : combineMode
        let caught = elements.compactMap(\.address)
        let combined = (selection ?? ScoreSelection(addresses: []))
            .combining(caught, mode: mode)

        switch mode {
        case .replace:
            selectionPaths = [page: path]
        case .add, .subtract:
            // keep the outlines already drawn: they are what the user built up
            selectionPaths = selectionPaths.merging([page: path]) { _, new in new }
        }

        selection = combined.isEmpty ? nil : combined
        selectionKey = combined.isEmpty ? nil : geometryKey
        if combined.isEmpty { selectionPaths = [:] }
        // the chip vanishes with the selection, so a mode left set here could
        // never be changed back
        combineMode = SelectionCombine.modeAfter(combineMode,
                                                 selectionIsEmpty: combined.isEmpty)
        // Nothing is inserted into the chat box here any more (#4c). The user
        // builds the selection up -- lasso, add with a held finger, drop what
        // they did not mean -- and hands it over when it is right, by tapping
        // Use in chat on the chip. Auto-inserting on every lasso appended a
        // line each time and filled the box with references to selections that
        // had already been replaced. Chat is not opened either: a lasso is not
        // a request to start typing.
    }

    /// A Pencil tap on the page. One drops an element, two select the bar on
    /// that staff, three select the bar across all staves (#10b).
    ///
    /// Deliberate, and only deliberate: a bar can no longer be caught by a
    /// lasso or a stray single tap, because bar-like kinds are filtered out of
    /// everything else (#9, #10a). Asking for a bar is the only way to get one.
    @discardableResult
    func handleTap(at point: CGPoint, onPage index: Int, taps: Int,
                   modifierFingerDown: Bool = false) -> Bool {
        switch LassoGate.tap(count: taps) {
        case .dropElement:
            // A held finger turns a tap into "add this one", the same way it
            // turns a drag into "add what I enclose".
            if LassoGate.singleTap(modifierFingerDown: modifierFingerDown) == .addElement {
                return addToSelection(at: point, onPage: index)
            }
            return dropFromSelection(at: point, onPage: index)
        case .selectBar:
            return selectBar(at: point, onPage: index, allStaves: false)
        case .selectBarAllStaves:
            return selectBar(at: point, onPage: index, allStaves: true)
        }
    }

    /// The bar under a point, as a selection of everything in it.
    ///
    /// A bar selection is expressed as the ELEMENTS of the bar, not as the
    /// measure element itself: that is what makes it usable by an op scoped to
    /// addresses, and what keeps the highlight on the notes rather than
    /// painting a block over the system.
    @discardableResult
    private func selectBar(at point: CGPoint, onPage index: Int,
                           allStaves: Bool) -> Bool {
        guard let geometry, let page = geometry.page(index) else { return false }
        let scaled = CGPoint(x: point.x * page.size.width, y: point.y * page.size.height)
        guard let bar = page.element(at: scaled, kinds: ScoreElementKind.barLike)?.address
        else { return false }

        // NOT bar.staff: a <measure> lives outside any <staff> in MEI, so its
        // address carries staff 0 and comparing against it matched no element
        // at all. A double-tap therefore selected nothing, and only the
        // triple-tap (every staff) ever appeared to work. The staff comes from
        // where the Pencil is instead.
        let wanted: Int? = allStaves ? nil
            : ScoreGeometry.staff(at: scaled.y,
                                  among: geometry.staffBands(inMeasure: bar.measure,
                                                             onPage: index))
        if !allStaves && wanted == nil { return false }

        let members = geometry.addresses.filter { address in
            guard address.measure == bar.measure,
                  !ScoreElementKind.barLike.contains(address.kind) else { return false }
            return allStaves || address.staff == wanted
        }
        guard !members.isEmpty else { return false }
        selection = ScoreSelection(addresses: members)
        selectionKey = geometryKey
        selectionPaths = [:]
        combineMode = .replace
        return true
    }

    /// Add the one element under the Pencil to the selection.
    @discardableResult
    func addToSelection(at point: CGPoint, onPage index: Int) -> Bool {
        guard let page = geometry?.page(index) else { return false }
        let scaled = CGPoint(x: point.x * page.size.width, y: point.y * page.size.height)
        guard let hit = page.element(at: scaled)?.address,
              !ScoreElementKind.barLike.contains(hit.kind) else { return false }
        selection = (selection ?? ScoreSelection(addresses: []))
            .combining([hit], mode: .add)
        selectionKey = geometryKey
        return true
    }

    /// Tapping a selected element drops just that one — the single correction
    /// a whole-region subtract is too blunt for.
    /// Returns true when something was dropped, so the caller knows the tap was
    /// used rather than passed through.
    @discardableResult
    func dropFromSelection(at point: CGPoint, onPage index: Int) -> Bool {
        guard let selection, !selection.isEmpty,
              let page = geometry?.page(index) else { return false }
        let scaled = CGPoint(x: point.x * page.size.width, y: point.y * page.size.height)
        guard let hit = page.element(at: scaled)?.address,
              selection.addresses.contains(hit) else { return false }
        let left = selection.dropping(hit)
        self.selection = left.isEmpty ? nil : left
        if left.isEmpty { selectionPaths = [:] }
        selectionKey = left.isEmpty ? nil : selectionKey
        combineMode = SelectionCombine.modeAfter(combineMode,
                                                 selectionIsEmpty: left.isEmpty)
        return true
    }

    /// PDFs currently being converted in the cloud — shown greyed out in the
    /// scores list with a live stage until they become real scores (or fail).
    struct PendingImport: Identifiable, Equatable {
        let id = UUID()
        let name: String
        /// The piece it is going into, so the library can show that piece
        /// filling up rather than the import vanishing (0.4.1 item 9).
        var piece: String?
        var stage: String = "uploading…"
        /// nil = indeterminate (spinner); 0…1 = determinate bar
        var fraction: Double? = nil
    }
    @Published var pendingImports: [PendingImport] = []

    private func updatePending(_ id: UUID, stage: String, fraction: Double?) {
        print("SCORANGER-OMR \(stage)")
        if let i = pendingImports.firstIndex(where: { $0.id == id }) {
            pendingImports[i].stage = stage
            pendingImports[i].fraction = fraction
        }
    }
    @Published var modelCatalog: ModelCatalog?

    // chat, kept per score slug
    @Published var chatMessages: [String: [ChatDisplayMessage]] = [:]
    @Published var chatBusy = false
    /// Live checklist of tool calls for the in-flight chat turn, per slug.
    @Published var activeChatSteps: [String: [ChatStep]] = [:]
    var chatHistory: [String: String] = [:]

    static let defaultEngineURL: String = {
        #if targetEnvironment(simulator)
        return "http://localhost:8765"
        #else
        return (Bundle.main.object(forInfoDictionaryKey: "EngineDefaultURL") as? String)
            ?? "http://localhost:8765"
        #endif
    }()

    @AppStorage("engineURL") var engineURLString = AppState.defaultEngineURL
    @AppStorage("chatModel") var chatModel = ""
    /// true = embedded Python engine + Verovio (no laptop needed);
    /// false = remote `scor serve` over the network.
    @AppStorage("useLocalEngine") var useLocalEngine = true
    /// Guards the one-time rename of the old seeded "Samples" setlist.
    @AppStorage("didMigrateSetlistNames") var didMigrateSetlistNames = false
    /// Two pages side by side, the way a score sits on a stand. Off by
    /// default: on one page the music is twice the size, which is what you
    /// want while arranging and not what you want while playing.
    @AppStorage("twoPageSpread") var twoPageSpread = false
    /// Cloud OMR service base URL (Audiveris on Cloud Run); empty = disabled.
    @AppStorage("omrURL") var omrURLString =
        (Bundle.main.object(forInfoDictionaryKey: "OMRDefaultURL") as? String) ?? ""

    /// Builds 4-5 shipped Cloud Run's "deterministic" hostname, which Google's
    /// edge routes unreliably (the PDF-conversion 502s). Rewrite it to the
    /// canonical a.run.app URL.
    func migrateStaleOMRURL() {
        if omrURLString.contains("789974749678.us-central1.run.app"),
           let canonical = Bundle.main.object(forInfoDictionaryKey: "OMRDefaultURL") as? String {
            omrURLString = canonical
        }
    }

    private var pollTask: Task<Void, Never>?
    private var renderedKey: String?

    var client: EngineClient { EngineClient(baseURLString: engineURLString) }
    let local = LocalEngine()
    /// Pencil markup state. Lives here because the pill drives it and the score
    /// pane only reacts, the same reason highlightMode moved up in build 116.
    let annotation = AnnotationController()

    /// Sidebar grouping: each piece with its arrangements resolved to ScoreDocs
    /// (pieces with no resolvable arrangements are dropped here — the full list,
    /// including empty pieces, stays available via manifest.pieces).
    var pieceSections: [(piece: PieceDoc, arrangements: [ScoreDoc])] {
        guard let m = manifest, let pieces = m.pieces else { return [] }
        return pieces.compactMap { piece in
            let scores = piece.arrangements.compactMap { slug in
                m.scores.first { $0.slug == slug }
            }
            return scores.isEmpty ? nil : (piece: piece, arrangements: scores)
        }
    }

    /// Sidebar setlists: each setlist with its arrangements resolved.
    var setlistSections: [(setlist: SetlistDoc, arrangements: [ScoreDoc])] {
        guard let m = manifest, let setlists = m.setlists else { return [] }
        return setlists.map { s in
            (setlist: s,
             arrangements: s.arrangements.compactMap { slug in
                 m.scores.first { $0.slug == slug }
             })
        }
    }

    /// Arrangements that could still be added to a setlist.
    func arrangementsNotIn(setlist: SetlistDoc) -> [ScoreDoc] {
        let inIt = Set(setlist.arrangements)
        return (manifest?.scores ?? [])
            .filter { !inIt.contains($0.slug) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Where an arrangement sits in the hierarchy: the piece it is filed under
    /// and its 1-based number within that piece. That number is what the UI
    /// shows as "#N" and what chat prompts mean by "#3".
    func placement(of slug: String) -> (piece: PieceDoc, number: Int)? {
        guard let pieces = manifest?.pieces,
              let piece = pieces.first(where: { $0.arrangements.contains(slug) }),
              let index = piece.arrangements.firstIndex(of: slug) else { return nil }
        return (piece, index + 1)
    }

    /// Scores not filed under any piece.
    var unfiledScores: [ScoreDoc] {
        guard let m = manifest else { return [] }
        let filed = Set((m.pieces ?? []).flatMap(\.arrangements))
        return m.scores.filter { !filed.contains($0.slug) }
    }

    /// What is open. Strictly what `selectedSlug` points at: an implicit
    /// "fall back to the most recently updated score" used to make a row the
    /// user never picked render as selected, and nothing could clear it —
    /// moving an arrangement into a piece updates it, so the moved row was the
    /// one that stuck. The convenience it provided (opening on the last score
    /// you touched) now happens as a real selection, in `adoptDefaultSelection`.
    var selectedScore: ScoreDoc? {
        guard let scores = manifest?.scores, let slug = selectedSlug else { return nil }
        return scores.first { $0.slug == slug }
    }

    /// First manifest of the session: open the most recently updated score, as
    /// an explicit selection the user can change or clear.
    private var hasAdoptedDefault = false

    func adoptDefaultSelection() {
        guard !hasAdoptedDefault, selectedSlug == nil,
              let scores = manifest?.scores, !scores.isEmpty else { return }
        hasAdoptedDefault = true
        selectedSlug = scores.max {
            ($0.versions.last?.time ?? "") < ($1.versions.last?.time ?? "")
        }?.slug
    }

    /// The score the sidebar's Versions section describes: the previewed one,
    /// falling back to whatever is open in the detail pane.
    var previewedScore: ScoreDoc? {
        guard let scores = manifest?.scores else { return nil }
        if let slug = previewedSlug, let s = scores.first(where: { $0.slug == slug }) { return s }
        return selectedScore
    }

    var displayedVersionID: String? {
        guard let score = selectedScore else { return nil }
        if let pin = pinnedVersion, score.versions.contains(where: { $0.id == pin }) { return pin }
        return score.latest
    }

    var displayedVersion: VersionDoc? {
        selectedScore?.versions.first { $0.id == displayedVersionID }
    }

    /// One sidebar/menu row of version history: either a single version, or
    /// the run of versions one chat prompt produced (face = its final state).
    struct VersionGroup: Identifiable {
        var id: String
        var title: String
        var face: VersionDoc
        var subs: [VersionDoc]
    }

    /// Consecutive versions stamped with the same turn id collapse into one
    /// group titled by the prompt; unstamped versions stand alone. Newest first.
    func versionGroups(for score: ScoreDoc) -> [VersionGroup] {
        var groups: [VersionGroup] = []
        for v in score.versions {
            if let turn = v.turn,
               var last = groups.last, last.face.turn?.id == turn.id {
                last.subs.append(v)
                last.face = v
                groups[groups.count - 1] = last
            } else {
                groups.append(VersionGroup(id: v.id,
                                           title: v.turn?.prompt ?? v.op,
                                           face: v,
                                           subs: v.turn != nil ? [v] : []))
            }
        }
        return groups.reversed()
    }

    /// Test fixture only, alongside `-resetLibrary`: view preferences outlive
    /// the workspace, so without this a test that turns the two-page spread on
    /// leaves it on for every test that launches after it.
    func resetViewPreferencesForTesting() {
        guard ProcessInfo.processInfo.arguments.contains("-resetLibrary") else { return }
        twoPageSpread = false
        // Pencil marks live in Documents, keyed by score and version, and so
        // outlive the workspace that -resetLibrary throws away. A stroke left
        // by one run turned up on a later run's canvas and read as a drawing
        // leaking between versions.
        DrawingStore.shared.clear(prefix: "")
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
    }

    /// Files -> On My iPad -> Scoranger -> inbox: anything dropped there is
    /// ingested automatically (scores import, PDFs convert via cloud OMR).
    func scanInbox() {
        guard useLocalEngine else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let inbox = docs.appending(path: "inbox")
        let staging = docs.appending(path: ".ingesting")
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let supported = ["musicxml", "mxl", "xml", "mid", "midi", "pdf"]
        for f in (try? FileManager.default.contentsOfDirectory(
            at: inbox, includingPropertiesForKeys: nil)) ?? []
        where supported.contains(f.pathExtension.lowercased()) {
            let staged = staging.appending(path: f.lastPathComponent)
            try? FileManager.default.removeItem(at: staged)
            // atomic move claims the file; skip if Files is still copying it
            guard (try? FileManager.default.moveItem(at: f, to: staged)) != nil else { continue }
            receiveFile(at: staged)
        }
    }

    /// One-time Documents layout: inbox/ for auto-ingest, plus the chat hook
    /// folders. No samples folder: the library is whatever the user imported.
    func prepareDocumentsFolders() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: docs.appending(path: "inbox"),
                                                 withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: docs.appending(path: "inbox-chat"),
                                                 withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: docs.appending(path: "outbox-chat"),
                                                 withIntermediateDirectories: true)
    }

    /// Test fixture only. The app ships with no sample library: a fresh install
    /// starts empty and fills up from what the user imports. UI tests need
    /// deterministic content, so they pass -seedTestLibrary to get it.
    func seedLibraryIfEmpty() async {
        guard useLocalEngine,
              ProcessInfo.processInfo.arguments.contains("-seedTestLibrary") else { return }
        do {
            let m = try await local.manifest()
            guard m.scores.isEmpty else { return }
            guard let seed = Bundle.main.resourceURL?.appending(path: "samples-seed") else { return }
            let files = ((try? FileManager.default.contentsOfDirectory(
                at: seed, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "mxl" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard !files.isEmpty else { return }
            let pieceName = "Sous le ciel de Paris"
            for f in files {
                _ = try await local.call(op: "import",
                                         args: ["path": f.path,
                                                "name": f.deletingPathExtension().lastPathComponent,
                                                "piece": pieceName])
            }
            for score in (try await local.manifest()).scores {
                _ = try await local.call(op: "assign-setlist",
                                         args: ["setlist": "Test setlist",
                                                "score": score.slug])
            }
            print("SCORANGER-SEED imported \(files.count) sample score(s)")
            // A version-less arrangement, for the test that proves such a thing
            // explains itself instead of spinning on "Opening…". It cannot be
            // made through the normal path any more -- create_score rolls back
            // -- so the fixture writes the row directly.
            if ProcessInfo.processInfo.arguments.contains("-seedBrokenArrangement") {
                _ = try? await local.call(op: "debug-orphan-arrangement",
                                          args: ["slug": "broken-arrangement",
                                                 "name": "Morrison's jig"])
            }
            await refresh()
        } catch {
            print("SCORANGER-SEED failed: \(error.localizedDescription)")
        }
    }

    #if DEBUG
    /// Headless chat hook for automated testing: drop {"score", "message",
    /// "model"?} JSON into Documents/inbox-chat; the reply lands in
    /// Documents/outbox-chat/<name>.result.json and the console logs
    /// SCORANGER-CHAT begin/done lines.
    private var chatHookBusy = false
    private func scanChatInbox() {
        guard !chatHookBusy else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let inbox = docs.appending(path: "inbox-chat")
        let outbox = docs.appending(path: "outbox-chat")
        let staging = docs.appending(path: ".ingesting")
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        for f in (try? FileManager.default.contentsOfDirectory(
            at: inbox, includingPropertiesForKeys: nil)) ?? []
        where f.pathExtension.lowercased() == "json" {
            let staged = staging.appending(path: f.lastPathComponent)
            try? FileManager.default.removeItem(at: staged)
            // atomic move claims the file; skip if it's still being copied
            guard (try? FileManager.default.moveItem(at: f, to: staged)) != nil else { continue }
            guard let data = try? Data(contentsOf: staged),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let slug = obj["score"] as? String,
                  let message = obj["message"] as? String else {
                try? FileManager.default.removeItem(at: staged)
                continue
            }
            let model = obj["model"] as? String
            let name = f.lastPathComponent
            let result = outbox.appending(
                path: "\(f.deletingPathExtension().lastPathComponent).result.json")
            chatHookBusy = true
            print("SCORANGER-CHAT begin \(name)")
            Task {
                defer { chatHookBusy = false }
                var payload: [String: Any]
                var okText = "ok=true"
                do {
                    let turn = try await LocalChat().run(
                        slug: slug, message: message, modelAlias: model, historyJSON: nil,
                        context: chatContext(for: slug))
                    payload = ["ok": true, "reply": turn.reply]
                } catch {
                    payload = ["ok": false, "error": error.localizedDescription]
                    okText = "ok=false \(error.localizedDescription)"
                }
                if let d = try? JSONSerialization.data(withJSONObject: payload) {
                    try? d.write(to: result)
                }
                try? FileManager.default.removeItem(at: staged)
                print("SCORANGER-CHAT done \(okText)")
                await refresh()
            }
            break  // one request at a time
        }
    }
    #endif

    func refresh() async {
        // whatever happens below, we will have looked
        defer { libraryLoaded = true }
        scanInbox()
        #if DEBUG
        scanChatInbox()
        #endif
        do {
            let m = useLocalEngine ? try await local.manifest() : try await client.manifest()
            // Only publish a manifest that differs. The poll runs every 1.5s,
            // and republishing an identical library rebuilt the whole sidebar
            // — including any open context menu — twice a second, which is why
            // a long-press could keep the app from ever going idle.
            if manifest != m { manifest = m }
            engineOK = true
            // a selection pointing at a deleted score would otherwise leave the
            // canvas showing nothing with no row highlighted
            if let slug = selectedSlug, !m.scores.contains(where: { $0.slug == slug }) {
                selectedSlug = nil
                pinnedVersion = nil
            }
            adoptDefaultSelection()
            if modelCatalog == nil {
                if useLocalEngine {
                    modelCatalog = ModelCatalog(default: LocalChat.defaultModel,
                                                models: LocalChat.models)
                } else {
                    modelCatalog = try? await client.models()
                }
                if chatModel.isEmpty, let def = modelCatalog?.default { chatModel = def }
            }
            await renderIfNeeded()
        } catch {
            engineOK = false
            if useLocalEngine { lastError = error.localizedDescription }
        }
    }

    /// Re-fetch the PDF when the displayed (score, version) changes.
    func renderIfNeeded(force: Bool = false) async {
        guard let score = selectedScore, let vid = displayedVersionID else { return }
        let key = "\(score.slug)/\(vid)"
        guard force || key != renderedKey else { return }
        // Nothing, rather than the wrong thing.
        //
        // The document was only swapped once the new engrave arrived, so the
        // PREVIOUS score stayed on screen until then -- opening an arrangement
        // showed the last one you had open, then flipped. A blank canvas for a
        // moment is honest; a stale one is not.
        if renderedKey != nil && renderedKey != key {
            pdfDocument = nil
            geometry = nil
            geometryKey = nil
            clearSelection()
        }
        renderedKey = key
        loadingPDF = true
        defer { loadingPDF = false }
        // A render that does not finish must not claim the key. `renderedKey`
        // is set before the work so a second call cannot start the same
        // engrave, but if the work throws, the key names a render that never
        // happened -- and `key != renderedKey` is then false for ever, so the
        // geometry can never refresh. Stale geometry is exactly what a lasso
        // that draws but catches nothing looks like.
        var rendered = false
        defer { if !rendered && renderedKey == key { renderedKey = nil } }
        do {
            let data: Data
            var model: ScoreGeometry?
            if useLocalEngine {
                let path = try await local.versionFilePath(score: score.slug, version: vid)
                // one engrave: the pages drawn and the model hit-tested are the
                // same Verovio load, or a lasso would select from a stale page
                let engraving = try await VerovioRenderer.shared.engrave(musicXMLPath: path)
                data = engraving.pdf
                model = engraving.geometry
            } else {
                data = try await client.exportPDF(score: score.slug, version: vid)
            }
            if renderedKey == key {  // selection may have moved while fetching
                rendered = true
                pdfDocument = PDFDocument(data: data)
                geometry = model
                let previousKey = geometryKey
                geometryKey = key
                carrySelection(from: previousKey, to: key, into: model)
                lastError = nil
            }
        } catch let e as EngineError {
            lastError = e.error
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// A file handed to us by the system (share sheet / "Open in").
    /// `piece` files the resulting arrangement under that piece (the sidebar's
    /// per-piece import); nil leaves it unfiled.
    func receiveFile(at url: URL, intoPiece piece: String? = nil) {
        if url.pathExtension.lowercased() == "pdf" {
            convertPDF(at: url, intoPiece: piece)
        } else {
            importScore(from: url, intoPiece: piece)
        }
    }

    /// PDF -> MusicXML via the cloud OMR service (Audiveris on Cloud Run),
    /// then import. Falls back to saving into Documents/intake when no
    /// service is configured.
    private func convertPDF(at url: URL, intoPiece piece: String? = nil) {
        let scoped = url.startAccessingSecurityScopedResource()
        let pdfData = try? Data(contentsOf: url)
        let name = url.deletingPathExtension().lastPathComponent
        if scoped { url.stopAccessingSecurityScopedResource() }
        guard let pdfData else {
            notice = "Couldn't read the PDF."
            return
        }
        guard let endpoint = URL(string: omrURLString), !omrURLString.isEmpty else {
            saveToIntake(pdfData, filename: url.lastPathComponent)
            return
        }
        // Notation software exports pages OMR cannot read: oversized, vector,
        // no raster layer. Re-render those before they go anywhere.
        let preflight = PDFPreflight.prepare(pdfData)
        let uploadData = preflight.data
        if let note = preflight.note { print("SCORANGER-OMR preflight: \(note)") }

        omrBusy = true
        let pending = PendingImport(name: name, piece: piece)
        pendingImports.append(pending)
        Task {
            defer {
                omrBusy = false
                pendingImports.removeAll { $0.id == pending.id }
            }
            do {
                // stored key if present, baked-in default otherwise; a 401
                // self-heals below by falling back to the baked key
                let bakedKey = Self.bakedOMRKey
                var apiKey = Self.effectiveOMRKey

                // -- 1. submit the job (upload with byte progress) ------------
                var request = URLRequest(url: endpoint.appending(path: "jobs"))
                request.httpMethod = "POST"
                request.timeoutInterval = 120
                request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
                request.setValue("application/pdf", forHTTPHeaderField: "Content-Type")

                let progressDelegate = UploadProgressDelegate { [weak self] sent in
                    Task { @MainActor in
                        self?.updatePending(pending.id, stage: "uploading…", fraction: sent)
                    }
                }

                // Retry transient failures on a FRESH session each attempt:
                // a pooled HTTP/2 connection re-hits the same dead backend.
                var submitted: [String: Any] = [:]
                var attempt = 0
                while true {
                    attempt += 1
                    do {
                        let session = URLSession(configuration: .ephemeral)
                        defer { session.finishTasksAndInvalidate() }
                        let (d, response) = try await session.upload(
                            for: request, from: uploadData, delegate: progressDelegate)
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        let body = (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
                        if code == 202 { submitted = body; break }
                        if code == 401, !bakedKey.isEmpty, apiKey != bakedKey {
                            // stored key is wrong — self-heal with the baked one
                            apiKey = bakedKey
                            KeychainStore.omrKey = bakedKey
                            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
                            continue
                        }
                        // 429 = single-instance service momentarily saturated
                        if code >= 500 || code == 429, attempt < 4 {
                            try await Task.sleep(for: .seconds(code == 429 ? 15 : 3))
                            continue
                        }
                        throw LocalEngineError.engine(
                            body["error"] as? String ?? "OMR service error (HTTP \(code))")
                    } catch let e as LocalEngineError {
                        throw e
                    } catch where attempt < 3 {
                        try await Task.sleep(for: .seconds(3))
                    }
                }
                guard let jobID = submitted["job"] as? String else {
                    throw LocalEngineError.engine("OMR service returned no job id")
                }

                // -- 2. poll for progress ------------------------------------
                let statusURL = endpoint.appending(path: "jobs/\(jobID)")
                var pollFailures = 0
                let pollDeadline = Date().addingTimeInterval(900)
                poll: while Date() < pollDeadline {
                    try await Task.sleep(for: .seconds(2))
                    var statusReq = URLRequest(url: statusURL)
                    statusReq.timeoutInterval = 15
                    statusReq.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
                    do {
                        let (d, _) = try await URLSession.shared.data(for: statusReq)
                        guard let s = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                              let state = s["state"] as? String else {
                            pollFailures += 1
                            if pollFailures > 10 { throw LocalEngineError.engine("lost contact with the OMR service") }
                            continue
                        }
                        pollFailures = 0
                        let page = s["page"] as? Int ?? 0
                        let pages = s["pages"] as? Int ?? 0
                        switch state {
                        case "queued":
                            let queue = s["queue"] as? Int ?? 0
                            updatePending(pending.id,
                                          stage: queue > 0 ? "waiting (\(queue) ahead)…" : "waiting for converter…",
                                          fraction: nil)
                        case "converting":
                            if pages > 0 {
                                updatePending(pending.id,
                                              stage: "reading page \(min(page + 1, pages)) of \(pages)",
                                              fraction: max(0.02, Double(page) / Double(pages)))
                            } else {
                                updatePending(pending.id, stage: "reading the score…", fraction: nil)
                            }
                        case "done":
                            break poll
                        case "failed":
                            throw LocalEngineError.engine(s["error"] as? String ?? "conversion failed")
                        default:
                            break
                        }
                    } catch let e as LocalEngineError {
                        throw e
                    } catch {
                        pollFailures += 1
                        if pollFailures > 10 { throw LocalEngineError.engine("lost contact with the OMR service") }
                    }
                }

                // -- 3. fetch result, import ---------------------------------
                updatePending(pending.id, stage: "downloading…", fraction: nil)
                var resultReq = URLRequest(url: endpoint.appending(path: "jobs/\(jobID)/result"))
                resultReq.timeoutInterval = 60
                resultReq.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
                let (data, resultResp) = try await URLSession.shared.data(for: resultReq)
                guard (resultResp as? HTTPURLResponse)?.statusCode == 200 else {
                    let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                    throw LocalEngineError.engine(detail ?? "couldn't fetch the converted score")
                }

                updatePending(pending.id, stage: "importing…", fraction: nil)
                let tmp = FileManager.default.temporaryDirectory.appending(path: "\(name).mxl")
                try? FileManager.default.removeItem(at: tmp)
                try data.write(to: tmp)
                let slug = try await local.importScore(fileURL: tmp, name: name, piece: piece)
                try? FileManager.default.removeItem(at: tmp)
                selectedSlug = slug
                previewedSlug = slug
                pinnedVersion = nil
                await refresh()
            } catch {
                notice = PDFPreflight.advice(name: name, error: error,
                                             preflight: preflight.note)
            }
        }
    }

    /// Reports upload byte progress for the OMR job submission.
    final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
        let onProgress: (Double) -> Void
        init(onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        didSendBodyData bytesSent: Int64,
                        totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            guard totalBytesExpectedToSend > 0 else { return }
            onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
        }
    }

    private func saveToIntake(_ data: Data, filename: String) {
        let intake = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "intake")
        try? FileManager.default.createDirectory(at: intake, withIntermediateDirectories: true)
        do {
            try data.write(to: intake.appending(path: filename))
            notice = "No OMR service configured (Settings) — PDF saved to Files → Scoranger → intake."
        } catch {
            notice = "Couldn't save the PDF: \(error.localizedDescription)"
        }
    }

    /// Import a MusicXML/MXL/MIDI file picked in the Files UI (local engine only).
    func importScore(from url: URL, intoPiece piece: String? = nil) {
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let tmp = FileManager.default.temporaryDirectory
                    .appending(path: url.lastPathComponent)
                try? FileManager.default.removeItem(at: tmp)
                try FileManager.default.copyItem(at: url, to: tmp)
                let name = url.deletingPathExtension().lastPathComponent
                let slug = try await local.importScore(fileURL: tmp, name: name, piece: piece)
                try? FileManager.default.removeItem(at: tmp)
                selectedSlug = slug
                previewedSlug = slug
                pinnedVersion = nil
                await refresh()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Open a score in the detail pane, optionally pinned to a version
    /// (nil = follow latest).
    // Navigation on compact is driven explicitly by ContentView's
    // preferredCompactColumn — no List-selection tricks needed here.
    func select(slug: String, version: String? = nil) {
        // A selection describes elements of the engraving it was drawn on, so
        // it goes when the subject changes: another arrangement, or a version
        // the user deliberately picked.
        //
        // The distinction #8 needs, and which this is half of: a selection
        // SURVIVES the new version an op produces, because that is the same
        // passage a moment later and the user is likely to run another op on
        // it. It does NOT survive being taken somewhere else. Both arrive as
        // "the version changed"; only this path is the user asking for it.
        if slug != selectedSlug || version != nil {
            clearSelection()
        }
        selectedSlug = slug
        previewedSlug = slug
        pinnedVersion = version
        Task { await renderIfNeeded() }
    }

    /// The OMR key baked in at build time (gitignored .omr-api-key), and the
    /// key the app actually sends: a saved one wins, the built-in one is the
    /// fallback. Settings tests this value rather than whatever is typed in the
    /// field, which is empty precisely when the built-in key is in use.
    static let bakedOMRKey: String =
        (Bundle.main.url(forResource: "omr-default-key", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

    static var effectiveOMRKey: String {
        let stored = KeychainStore.omrKey
        return stored.isEmpty ? bakedOMRKey : stored
    }

    /// The metadata as it stands in the notation of a version -- which is what
    /// engraves on the page. The score doc carries a copy, but only versions
    /// written since the projection landed, so the sheet asks the engine.
    struct ScoreMetadata: Equatable {
        var title: String?
        var composer: String?
        var arranger: String?
    }

    func scoreMetadata(slug: String, version: String? = nil) async -> ScoreMetadata? {
        guard useLocalEngine else { return nil }
        var args: [String: Any] = ["score": slug]
        if let version { args["version"] = version }
        guard let r = try? await local.call(op: "info", args: args) else { return nil }
        return ScoreMetadata(title: r["title"] as? String,
                             composer: r["composer"] as? String,
                             arranger: r["arranger"] as? String)
    }

    /// Edit an arrangement's metadata. The title is one value: the name in the
    /// library and the title engraved at the top of the page. Because the
    /// engraved title lives in the notation, the engine appends a version, so
    /// this clears any pin to put the freshly engraved version on screen.
    /// Pass nil to leave a field alone, "" to clear a credit.
    @discardableResult
    func setScoreMetadata(slug: String, title: String? = nil,
                          composer: String? = nil, arranger: String? = nil) async -> Bool {
        var args: [String: Any] = ["score": slug]
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            args["title"] = trimmed
        }
        if let composer { args["composer"] = composer.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let arranger { args["arranger"] = arranger.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard args.count > 1 else { return false }
        do {
            _ = try await local.call(op: "set-metadata", args: args)
            if slug == selectedSlug { pinnedVersion = nil }
            await refresh()
            return true
        } catch let e as EngineError {
            lastError = e.error
        } catch {
            lastError = error.localizedDescription
        }
        return false
    }

    /// The arrangement's title. Kept as its own call because renaming is what
    /// callers ask for; the work is setScoreMetadata's, so a rename can never
    /// leave the page saying something else.
    @discardableResult
    func renameScore(slug: String, name: String) async -> Bool {
        await setScoreMetadata(slug: slug, title: name)
    }

    /// Change the slug an arrangement is filed under.
    ///
    /// The engine moves the artifacts and rewrites every reference it owns; the
    /// app owns two things keyed by slug — the current selection and the pencil
    /// annotations — and moves those here. Returns the slug actually used (it is
    /// normalized), or nil if the rename was refused.
    @discardableResult
    func renameSlug(slug: String, to newSlug: String) async -> String? {
        let trimmed = newSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let r = try await local.call(op: "rename-slug",
                                        args: ["score": slug, "to": trimmed])
            guard let now = r["score"] as? String else { return nil }
            if now != slug {
                DrawingStore.shared.rename(fromPrefix: slug, toPrefix: now)
                if selectedSlug == slug { selectedSlug = now }
                if previewedSlug == slug { previewedSlug = now }
                renderedKey = nil   // the render is keyed by slug/version
            }
            await refresh()
            return now
        } catch let e as EngineError {
            lastError = e.error
        } catch {
            lastError = error.localizedDescription
        }
        return nil
    }

    /// Rename a part (the staff label, engraved on every system).
    @discardableResult
    func renamePart(slug: String, part: String, name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != part else { return false }
        do {
            _ = try await local.call(op: "rename-part",
                                     args: ["score": slug, "part": part, "name": trimmed])
            if slug == selectedSlug { pinnedVersion = nil }
            await refresh()
            return true
        } catch let e as EngineError {
            lastError = e.error
        } catch {
            lastError = error.localizedDescription
        }
        return false
    }

    /// Rename a piece (the grouping). Its slug is immutable, like a score's.
    @discardableResult
    func renamePiece(piece: String, name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            _ = try await local.call(op: "rename-piece",
                                     args: ["piece": piece, "name": trimmed])
            await refresh()
            return true
        } catch let e as EngineError {
            lastError = e.error
        } catch {
            lastError = error.localizedDescription
        }
        return false
    }

    /// Duplicate an arrangement into a new independent copy (new slug, its own
    /// history, filed under the same piece). Returns the copy's slug.
    @discardableResult
    func duplicateScore(slug: String, name: String? = nil) async -> String? {
        do {
            var args: [String: Any] = ["score": slug]
            if let name { args["name"] = name }
            let r = try await local.call(op: "duplicate", args: args)
            await refresh()
            return r["score"] as? String
        } catch let e as EngineError {
            lastError = e.error
        } catch {
            lastError = error.localizedDescription
        }
        return nil
    }

    /// File a score under a piece (nil = remove from its piece). The piece is
    /// created on the engine side if it doesn't exist yet.
    func assignToPiece(scoreSlug: String, piece: String?) {
        Task {
            do {
                if let piece {
                    _ = try await local.call(op: "assign-piece",
                                             args: ["score": scoreSlug, "piece": piece])
                } else {
                    _ = try await local.call(op: "unassign-piece", args: ["score": scoreSlug])
                }
                await refresh()
            } catch let e as EngineError {
                lastError = e.error
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Create a blank arrangement (one part, one empty 4/4 bar) filed under a
    /// piece. Returns the new score's slug so the caller can open it.
    func createArrangement(pieceSlug: String, name: String? = nil) async -> String? {
        do {
            var args: [String: Any] = ["piece": pieceSlug]
            if let name { args["name"] = name }
            let r = try await local.call(op: "create-arrangement", args: args)
            await refresh()
            return r["score"] as? String
        } catch let e as EngineError {
            lastError = e.error
        } catch {
            lastError = error.localizedDescription
        }
        return nil
    }

    #if DEBUG
    /// Test fixture: run several ops inside one chat turn, so the sidebar has a
    /// prompt group with intermediate steps to expand. Only reachable under
    /// -seedTestLibrary, alongside the rest of the test scaffolding.
    func seedMultiStepTurnIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("-seedTestLibrary"),
              let slug = manifest?.scores.first(where: { $0.versions.count == 1 })?.slug
        else { return }
        do {
            _ = try await local.call(op: "begin-turn",
                                     args: ["score": slug,
                                            "prompt": "transpose up then back down"])
            _ = try await local.call(op: "transpose", args: ["score": slug, "interval": "2"])
            _ = try await local.call(op: "transpose", args: ["score": slug, "interval": "-2"])
            _ = try await local.call(op: "end-turn", args: [:])
            await refresh()
            print("SCORANGER-SEED multi-step turn on \(slug)")
        } catch {
            print("SCORANGER-SEED turn failed: \(error.localizedDescription)")
        }
    }
    #endif

    /// One-time cleanup for devices carrying the setlist the old seeding made.
    /// The samples concept is gone (build 116) but the row it created lives in
    /// the on-device workspace, which app updates do not touch, so it has to be
    /// renamed in place. Exact-name match only, and it runs once.
    func migrateSeededSetlistName() async {
        guard useLocalEngine, !didMigrateSetlistNames else { return }
        guard let setlists = manifest?.setlists else { return }  // retry next refresh
        didMigrateSetlistNames = true
        guard let stale = setlists.first(where: { $0.name == "Samples" }) else { return }
        if await renameSetlist(setlist: stale.slug, name: "Set List 1") {
            print("SCORANGER-MIGRATE renamed setlist 'Samples' -> 'Set List 1'")
        }
    }

    /// Create an empty setlist. Returns the slug the engine filed it under,
    /// which is not always slugify(name) — a second "Gig night" becomes
    /// "gig-night-2", and the caller needs the real one to fill it.
    @discardableResult
    func createSetlist(name: String) async -> String? {
        do {
            let r = try await local.call(op: "create-setlist", args: ["name": name])
            await refresh()
            return r["slug"] as? String
        } catch let e as EngineError {
            lastError = e.error
        } catch {
            lastError = error.localizedDescription
        }
        return nil
    }

    /// Add an arrangement to a setlist (no-op if already in it).
    @discardableResult
    func addToSetlist(setlist: String, score: String) async -> Bool {
        await runSetlistOp(op: "assign-setlist",
                           args: ["setlist": setlist, "score": score])
    }

    /// Drop an arrangement from a setlist. The arrangement itself is untouched.
    @discardableResult
    func removeFromSetlist(setlist: String, score: String) async -> Bool {
        await runSetlistOp(op: "unassign-setlist",
                           args: ["setlist": setlist, "score": score])
    }

    @discardableResult
    func renameSetlist(setlist: String, name: String) async -> Bool {
        await runSetlistOp(op: "rename-setlist", args: ["setlist": setlist, "name": name])
    }

    /// Delete a setlist. Only the grouping goes; pieces and arrangements stay.
    @discardableResult
    func deleteSetlist(_ setlist: String) async -> Bool {
        await runSetlistOp(op: "delete-setlist", args: ["setlist": setlist])
    }

    private func runSetlistOp(op: String, args: [String: Any]) async -> Bool {
        do {
            _ = try await local.call(op: op, args: args)
            await refresh()
            return true
        } catch let e as EngineError {
            lastError = e.error
        } catch {
            lastError = error.localizedDescription
        }
        return false
    }

    /// Drop an arrangement into a piece at a chosen position.
    ///
    /// Filing and ordering are two engine ops, and the second needs the first
    /// to have landed — a drag from another piece that fired them in parallel
    /// reordered a list the arrangement was not in yet, and the row appeared
    /// at the bottom. `order` is built from the piece as it will be, so the
    /// call is correct whether the arrangement is already in this piece or is
    /// arriving from elsewhere.
    ///
    /// `before` is the slug the dragged row should displace; nil appends.
    func placeInPiece(scoreSlug: String, piece: String, before target: String?) {
        Task {
            do {
                // the piece document holds the order; the score list does not
                let current = (manifest?.pieces ?? [])
                    .first { $0.slug == piece }?.arrangements ?? []
                if !current.contains(scoreSlug) {
                    _ = try await local.call(op: "assign-piece",
                                             args: ["score": scoreSlug, "piece": piece])
                }
                var order = current.filter { $0 != scoreSlug }
                let index = target.flatMap { order.firstIndex(of: $0) } ?? order.count
                order.insert(scoreSlug, at: index)
                _ = try await local.call(op: "reorder-piece",
                                         args: ["piece": piece, "order": order])
                await refresh()
            } catch let e as EngineError {
                lastError = e.error
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Persist a piece's arrangement order (the sidebar numbering).
    /// Set a set list's running order. The engine keeps the order on the
    /// setlist document, so this is one reorder op rather than a remove and
    /// re-add, which would lose the position of everything after it.
    @discardableResult
    func reorderSetlist(_ setlist: String, order: [String]) async -> Bool {
        do {
            _ = try await local.call(op: "reorder-setlist",
                                    args: ["setlist": setlist, "order": order])
            await refresh()
            return true
        } catch let e as EngineError {
            lastError = e.error
        } catch {
            lastError = error.localizedDescription
        }
        return false
    }

    func reorderPiece(piece: String, order: [String]) {
        Task {
            do {
                _ = try await local.call(op: "reorder-piece",
                                         args: ["piece": piece, "order": order])
                await refresh()
            } catch let e as EngineError {
                lastError = e.error
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Piece context handed to the chat agent: which piece this arrangement
    /// belongs to and its numbered siblings. The numbers are the "#N" the user
    /// sees in the sidebar and types in prompts; each maps to an 'arr:<slug>'
    /// ref that pull_part accepts.
    func chatContext(for slug: String) -> String? {
        guard let m = manifest,
              let score = m.scores.first(where: { $0.slug == slug }),
              let pieceSlug = score.piece,
              let piece = (m.pieces ?? []).first(where: { $0.slug == pieceSlug }),
              !piece.arrangements.isEmpty else { return nil }
        let numbered = piece.arrangements.enumerated().map { i, s -> String in
            let name = m.scores.first { $0.slug == s }?.name ?? s
            let marker = s == slug ? " (THIS arrangement)" : ""
            return "#\(i + 1) = '\(name)' (ref arr:\(s))\(marker)"
        }
        return "This arrangement belongs to the piece '\(piece.name)'. "
            + "The piece's arrangements are numbered, and the user refers to them "
            + "by number with a '#' prefix: " + numbered.joined(separator: ", ") + ". "
            + "So \"take the violin part from #3\" means pull_part with the arr: ref "
            + "listed for #3. Numbers refer only to arrangements of this piece, never "
            + "to versions or measures."
    }

    /// Chat context plus the active selection, if any, so a prompt can say
    /// "the selection" and mean exactly the elements the user lassoed.
    func chatContextWithHighlight(for slug: String) -> String? {
        var pieces: [String] = []
        if let base = chatContext(for: slug) { pieces.append(base) }
        if let selection = activeSelection, !selection.isEmpty {
            // The addresses themselves, not a bar range.
            //
            // This used to say "pass from_measure/to_measure", which is why
            // Ali selected one chord, asked to move those notes up, and the
            // whole bar moved: the selection was degraded to its bar number
            // before the model ever saw it, and the op did exactly what it was
            // told. The addresses are what the lasso actually caught.
            let list = selection.addressList.joined(separator: ", ")
            pieces.append(
                "The user has selected \(selection.headline)"
                + (selection.placeLine.map { " (\($0))" } ?? "") + ". "
                + "Their addresses are: \(list). "
                + "'The selection', 'these notes' and 'the highlighted passage' mean "
                + "EXACTLY those elements. Use transpose_elements with that exact list "
                + "of addresses. Do NOT use transpose with from_measure/to_measure for a "
                + "selection: that moves every note in the bar, including ones the user "
                + "did not select. Ask before making whole-piece changes while a "
                + "selection is active.")
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: " ")
    }

    /// Create a new piece by name and file the score under it (assign-piece
    /// creates missing pieces).
    /// Create a piece and return its slug.
    ///
    /// It holds nothing for the moment between this and the first arrangement
    /// arriving, which is legitimate and is why the empty-piece sweep runs
    /// where an arrangement LEAVES rather than on every rebuild.
    @discardableResult
    func createPiece(named name: String) async -> String? {
        do {
            let r = try await local.call(op: "create-piece", args: ["name": name])
            await refresh()
            return (r["piece"] as? [String: Any])?["slug"] as? String
                ?? r["slug"] as? String
        } catch let e as EngineError {
            lastError = e.error
        } catch {
            lastError = error.localizedDescription
        }
        return nil
    }

    func createPieceAndAssign(name: String, scoreSlug: String) {
        Task {
            do {
                _ = try await local.call(op: "assign-piece",
                                         args: ["score": scoreSlug, "piece": name])
                await refresh()
            } catch let e as EngineError {
                lastError = e.error
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Irreversibly delete a score and all its versions.
    /// Delete a piece, and its arrangements with it.
    ///
    /// This is what deleting a folder means to the person doing it. The old
    /// path looped over `piece.arrangements` and deleted each -- which for a
    /// piece holding nothing is an empty loop, so the button did nothing at
    /// all. The engine drops the piece document itself.
    func deletePiece(_ slug: String, withArrangements: Bool = true) {
        Task {
            do {
                _ = try await local.call(op: "delete-piece",
                                        args: ["piece": slug,
                                               "with_arrangements": withArrangements])
                await refresh()
            } catch let e as EngineError {
                lastError = e.error
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// What was just deleted and can still be put back (§5.2).
    ///
    /// The engine marks rather than unlinks, so undo is a restore rather than a
    /// re-import. The bar's countdown is cosmetic -- what actually decides is
    /// the engine's window, and the sweep is what reclaims.
    struct UndoableDelete: Identifiable, Equatable {
        let id = UUID()
        let slug: String
        let what: String
        let isSetlist: Bool
    }
    @Published var undoableDelete: UndoableDelete?

    func restoreDeleted() {
        guard let undo = undoableDelete else { return }
        undoableDelete = nil
        Task {
            _ = try? await local.call(op: "restore-score", args: ["score": undo.slug])
            await refresh()
        }
    }

    /// Reclaim anything whose window has passed. On launch, and after a delete.
    func sweepDeleted() async {
        _ = try? await local.call(op: "sweep", args: [:])
    }

    /// Sweep up pieces left holding nothing by a build that had no such rule.
    func tidyPieces() async {
        _ = try? await local.call(op: "tidy-pieces", args: [:])
        await refresh()
    }

    func deleteScore(slug: String, undoable: Bool = true) {
        let name = manifest?.scores.first { $0.slug == slug }
            .map { $0.title ?? $0.name } ?? slug
        Task {
            do {
                try await local.deleteScore(slug)
                if undoable {
                    undoableDelete = UndoableDelete(slug: slug, what: name,
                                                    isSetlist: false)
                }
                if previewedSlug == slug { previewedSlug = nil }
                if selectedSlug == slug {
                    selectedSlug = nil
                    pinnedVersion = nil
                }
                await refresh()
            } catch let e as EngineError {
                lastError = e.error
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func transpose(semitones: Int) {
        guard let slug = selectedScore?.slug else { return }
        Task {
            do {
                if useLocalEngine {
                    try await local.transpose(score: slug, semitones: semitones)
                } else {
                    try await client.transpose(score: slug, semitones: semitones)
                }
                pinnedVersion = nil
                await refresh()
            } catch let e as EngineError {
                lastError = e.error
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Respell the whole score enharmonically (flats vs sharps). Creates a
    /// new version, like any other op.
    func respell(preferFlats: Bool) {
        guard let slug = selectedScore?.slug else { return }
        Task {
            do {
                _ = try await local.call(op: "respell",
                                         args: ["score": slug,
                                                "prefer": preferFlats ? "flats" : "sharps"])
                pinnedVersion = nil
                await refresh()
            } catch let e as EngineError {
                lastError = e.error
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func sendChat(_ text: String) {
        guard let slug = selectedScore?.slug, !chatBusy else { return }
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        chatMessages[slug, default: []].append(.init(role: .user, text: message))
        chatBusy = true
        activeChatSteps[slug] = []
        Task {
            defer {
                chatBusy = false
                activeChatSteps[slug] = nil
            }
            do {
                if useLocalEngine {
                    let turn = try await LocalChat().run(
                        slug: slug, message: message,
                        modelAlias: chatModel.isEmpty ? nil : chatModel,
                        historyJSON: chatHistory[slug],
                        context: chatContextWithHighlight(for: slug),
                        onEvent: { [weak self] event in
                            guard let self else { return }
                            switch event {
                            case .toolStarted(let title):
                                self.activeChatSteps[slug, default: []]
                                    .append(ChatStep(title: title, detail: nil, done: false))
                            case .toolFinished(let detail):
                                if let i = self.activeChatSteps[slug]?.lastIndex(where: { !$0.done }) {
                                    self.activeChatSteps[slug]?[i].done = true
                                    self.activeChatSteps[slug]?[i].detail = detail
                                }
                            }
                        })
                    chatHistory[slug] = turn.historyJSON
                    // keep the checklist in the transcript with the reply
                    let steps = activeChatSteps[slug]
                    chatMessages[slug, default: []].append(
                        .init(role: .agent, text: turn.reply,
                              steps: (steps?.isEmpty == false) ? steps : nil))
                } else {
                    let resp = try await client.chat(score: slug, message: message,
                                                     model: chatModel.isEmpty ? nil : chatModel,
                                                     history: chatHistory[slug])
                    chatHistory[slug] = resp.history
                    chatMessages[slug, default: []].append(.init(role: .agent, text: resp.reply))
                }
                pinnedVersion = nil
                await refresh()
            } catch let e as EngineError {
                chatMessages[slug, default: []].append(.init(role: .error, text: e.error))
            } catch {
                chatMessages[slug, default: []].append(.init(role: .error, text: error.localizedDescription))
            }
        }
    }
}
