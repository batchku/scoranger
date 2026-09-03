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
    /// Why the RENDER failed, and nothing else.
    ///
    /// Its one reader is the "Render failed" placeholder in `ContentView`,
    /// which is on screen only when a score is open and no page could be
    /// drawn -- so it shows a Verovio failure with the build stamp, in mono,
    /// where the failure happened. Forty other failures used to be written
    /// here too and were therefore silent: an Import Book that died on a
    /// missing Python module set this from the LIBRARY, where nothing renders
    /// it, and looked exactly like a button that did nothing.
    ///
    /// Everything that is not a render failure goes to `notice` through
    /// `report(_:_:)`. `check_error_reporting.py` fails the build if a new
    /// write appears here.
    @Published var lastError: String?

    /// The engine failure already spoken. `refresh` polls every two seconds;
    /// without this the notice would come back a second after dismissal.
    private var reportedEngineFailure: String?

    /// Say so.
    ///
    /// `action` is the verb phrase as the reader would say it -- "rename that
    /// part", not the op's name. This is the ONLY route a non-render failure
    /// takes to the screen: `notice`, which `NoticeBar` renders over both the
    /// library and an open score.
    func report(_ action: String, _ error: Error) {
        notice = OperationReport.failure(action, error: error)
    }
    /// One-shot user-facing message shown as an alert (share-sheet receipts etc.)
    @Published var notice: String?
    @Published var omrBusy = false
    /// The transcription in flight, so a control that OFFERS OMR can show what
    /// OMR is doing rather than a bare "busy". Both paths in -- the More
    /// screen's switch and the transport's button -- read it.
    @Published private(set) var omrPendingID: UUID?

    var omrStage: String? { pendingImports.first { $0.id == omrPendingID }?.stage }
    var omrFraction: Double? { pendingImports.first { $0.id == omrPendingID }?.fraction }
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
    /// What each chord symbol already carries, by address — the chip's starting
    /// point, so a nudge builds on the file rather than on the default.
    @Published var chordAdjustments: [ScoreAddress: ChordAdjustments.Adjustment] = [:]
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

    @Published var currentSetlist: String?
    /// Which pages are on screen, reported by the canvas. Feeds the counters
    /// and the thumbnail strip's "you are here" (NAVIGATION_SYSTEM.md 12.11).
    /// The page unit on screen. The canvas shows this one page (or this pair
    /// with the spread on) and nothing else exists -- turning changes the
    /// index rather than scrolling a stack (NAV_MODAL_FREE_0.4.2 §6).
    @Published var pageIndex: Int = 0
    @Published var visiblePageIndices: [Int] = [0]
    /// Per page index, the slice of that page currently on screen, in PAGE
    /// (SVG user) coordinates. Reported by each page so the bar readout can say
    /// which bar the reader is actually looking at rather than which page they
    /// are on -- at 4x zoom those are very different answers.
    @Published var visibleBarRects: [Int: CGRect] = [:]
    // pageBoundaries is gone with the stack it described: a turn changes an
    // index now, so there is no offset to compute or preserve.
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

    // MARK: - Adjusting a chord symbol's size and position
    //
    // Taps accumulate here and commit ONCE, when the reader leaves the element.
    // The notation is versioned, so committing per tap would spend a version on
    // every button press. See docs/size-and-position-spec.md, "Committing".

    /// The adjustment in progress, or nil when nothing adjustable is selected.
    @Published var adjustSession: ChordAdjustSession?
    /// The element the session belongs to, so selecting another commits the
    /// first rather than silently retargeting it.
    @Published private(set) var adjustTarget: ScoreAddress?
    /// Groups the versions one sitting produces, the way a chat turn's steps
    /// are grouped -- four nudges should read as one adjustment, not four
    /// unrelated versions.
    private var adjustTurnID: String?
    private var adjustIdleTask: Task<Void, Never>?

    /// Three seconds of no further taps counts as leaving the element.
    static let adjustIdleCommit: Duration = .seconds(3)

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
        // Leaving the element is what commits it. Dropping the selection with
        // an uncommitted nudge would throw the reader's work away silently.
        commitAdjustment()
        selection = nil
        selectionPaths = [:]
        selectionKey = nil
        combineMode = .replace
    }

    // MARK: - The adjustment session

    /// Point the session at whatever is selected now, committing whatever the
    /// last element had pending.
    ///
    /// Called whenever the selection changes. Selecting a second chord symbol
    /// while the first has an uncommitted nudge must WRITE the first, not
    /// retarget the pending values onto the new one.
    func retargetAdjustment() {
        guard let selection = activeSelection, selection.isAdjustable,
              let address = selection.addresses.first else {
            commitAdjustment()
            closeAdjustTurn()
            adjustSession = nil
            adjustTarget = nil
            return
        }
        if adjustTarget == address { return }
        commitAdjustment()
        closeAdjustTurn()
        adjustSession = ChordAdjustSession(
            size: chordSize(at: address) ?? ChordAdjustSession.defaultSize,
            committedDX: chordOffset(at: address).dx,
            committedDY: chordOffset(at: address).dy)
        adjustTarget = address
        adjustTurnID = nil
    }

    /// A tap on one of the chip's buttons: change the pending value, redraw
    /// locally, and restart the idle timer. Nothing reaches the engine here.
    func adjust(_ change: (inout ChordAdjustSession) -> Void) {
        guard var session = adjustSession else { return }
        change(&session)
        adjustSession = session
        scheduleAdjustCommit()
    }

    private func scheduleAdjustCommit() {
        adjustIdleTask?.cancel()
        adjustIdleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.adjustIdleCommit)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.commitAdjustment() }
        }
    }

    /// Write the pending adjustment, as ONE op. Safe to call when there is
    /// nothing pending -- an empty commit would still cost a version.
    func commitAdjustment() {
        adjustIdleTask?.cancel()
        adjustIdleTask = nil
        guard var session = adjustSession, let address = adjustTarget,
              let commit = session.commit(),
              let slug = selectedScore?.slug,
              let part = partName(forStaff: address.staff) else { return }
        adjustSession = session   // the commit clears what was pending
        // Group this sitting's versions the way a chat turn's steps are
        // grouped, using the SAME mechanism rather than a parallel one -- four
        // nudges should read as one adjustment in the version list, not as four
        // unrelated versions.
        let openTurn = adjustTurnID == nil
        adjustTurnID = adjustTurnID ?? UUID().uuidString
        let what = "Adjusted the chord symbol in bar \(address.measure)"
        Task {
            if openTurn {
                _ = try? await local.call(op: "begin-turn",
                                          args: ["score": slug, "prompt": what])
            }
            var args: [String: Any] = ["score": slug, "part": part,
                                       "kind": "harm",
                                       "measure": address.measure,
                                       "ordinal": address.ordinal]
            if commit.reset {
                args["reset"] = true
            } else {
                if let size = commit.size { args["size"] = size }
                if let x = commit.offsetX { args["offset_x"] = x }
                if let y = commit.offsetY { args["offset_y"] = y }
            }
            do {
                _ = try await local.call(op: "adjust-element", args: args)
                await refresh()
                await renderIfNeeded(force: true)
            } catch {
                report("move that chord symbol", error)
            }
        }
    }

    // MARK: - The part-wide default

    /// The size new chord symbols inherit. Per-element overrides are absolute
    /// points in the notation, so they survive this changing.
    @Published var chordDefaultSize: Int = ChordAdjustSession.defaultSize

    func canStepChordDefault(_ step: ChordAdjustSession.SizeStep) -> Bool {
        var probe = ChordAdjustSession(size: chordDefaultSize)
        return probe.canResize(step)
    }

    /// Set the part-wide default outright, which is what tapping a rung of the
    /// size ladder does. The stepper walks the same ladder one rung at a time.
    func setChordDefault(_ size: Int) {
        guard ChordAdjustSession.sizeLadder.contains(size),
              size != chordDefaultSize else { return }
        chordDefaultSize = size
        applyChordDefault()
    }

    func stepChordDefault(_ step: ChordAdjustSession.SizeStep) {
        var probe = ChordAdjustSession(size: chordDefaultSize)
        guard probe.canResize(step) else { return }
        probe.resize(step)
        chordDefaultSize = probe.pending.size
        applyChordDefault()
    }

    /// One op over every chord symbol in the part.
    private func applyChordDefault() {
        guard let slug = selectedScore?.slug, let part = chordPartName() else { return }
        Task {
            do {
                _ = try await local.call(op: "adjust-element",
                                         args: ["score": slug, "part": part,
                                                "kind": "harm", "all": true,
                                                "size": chordDefaultSize])
                await refresh()
                await renderIfNeeded(force: true)
            } catch { report("resize the chord symbols", error) }
        }
    }

    /// Put every chord symbol in the part back to the inherited size and no
    /// offset. The way out of a part someone has nudged ten symbols in.
    func resetAllChordAdjustments() {
        guard let slug = selectedScore?.slug, let part = chordPartName() else { return }
        chordDefaultSize = ChordAdjustSession.defaultSize
        Task {
            do {
                _ = try await local.call(op: "adjust-element",
                                         args: ["score": slug, "part": part,
                                                "kind": "harm", "all": true,
                                                "reset": true])
                await refresh()
                await renderIfNeeded(force: true)
            } catch { report("put the chord symbols back", error) }
        }
    }

    /// The part carrying chord symbols -- the selected one where the reader has
    /// picked a symbol, else the first part that has any.
    ///
    /// Internal, not private: the Options screen NAMES the part it is about to
    /// resize every chord symbol in. The size control was reported as doing
    /// nothing, and a part-wide op that says nothing about which part it hit
    /// is indistinguishable from one that did not run.
    func chordPartName() -> String? {
        if let address = adjustTarget, let named = partName(forStaff: address.staff) {
            return named
        }
        return selectedScore?.versions.last?.parts?.first?.name
    }

    /// End the grouping once the reader has moved on, so the NEXT element's
    /// adjustments are their own group rather than joining this one.
    private func closeAdjustTurn() {
        guard adjustTurnID != nil else { return }
        adjustTurnID = nil
        Task { _ = try? await local.call(op: "end-turn", args: [:]) }
    }

    /// The part a staff belongs to, which is what the op is addressed by.
    private func partName(forStaff staff: Int) -> String? {
        let parts = selectedScore?.versions.last?.parts ?? []
        guard staff >= 1, staff <= parts.count else { return parts.first?.name }
        return parts[staff - 1].name
    }

    /// What the notation already carries for this symbol, so the session starts
    /// from the truth rather than from the default.
    private func chordSize(at address: ScoreAddress) -> Int? {
        chordAdjustments[address]?.size.map { Int($0.rounded()) }
    }

    private func chordOffset(at address: ScoreAddress) -> (dx: Int, dy: Int) {
        let adjustment = chordAdjustments[address]
        return (Int((adjustment?.dx ?? 0).rounded()), Int((adjustment?.dy ?? 0).rounded()))
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
        // Selecting a different symbol WRITES whatever the last one had
        // pending, rather than carrying the pending values onto it.
        retargetAdjustment()
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
        /// Which list this row belongs in. A book is not an arrangement and
        /// its progress must not appear under Pieces (ImportProgress).
        var target: ImportTarget = .arrangement
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
    /// How the score is laid out: one page, a spread, or continuous.
    ///
    /// One page by default: on one page the music is twice the size, which is
    /// what you want while playing. Stored as a string so a fourth layout
    /// costs nothing, and read through `layout` below.
    @AppStorage("scoreLayout") private var storedLayout = ScoreLayout.page.rawValue
    /// The spread preference this replaced. Read ONCE, to carry a reader who
    /// already had the spread on into the new setting; never written again.
    @AppStorage("twoPageSpread") private var legacySpread = false
    @AppStorage("didMigrateScoreLayout") private var didMigrateScoreLayout = false

    var layout: ScoreLayout {
        get { ScoreLayout(rawValue: storedLayout) ?? .page }
        set { storedLayout = newValue.rawValue }
    }

    /// Kept so the twelve places that ask "is this a spread?" still can. It is
    /// DERIVED: setting it chooses between the two page layouts and can no
    /// longer disagree with `layout`.
    var twoPageSpread: Bool {
        get { layout == .spread }
        set { layout = newValue ? .spread : .page }
    }

    /// Carries the old boolean over the first time the new build runs.
    func migrateScoreLayout() {
        guard !didMigrateScoreLayout else { return }
        didMigrateScoreLayout = true
        if legacySpread, layout == .page { layout = .spread }
    }
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

    /// Which engraving `pdfDocument` currently holds, as a string the canvas
    /// can key its rasters by.
    ///
    /// NOT the `PDFPage`'s object identity, which is what a raster cache would
    /// otherwise reach for: a page freed when the version changes can be
    /// replaced at the same address, and the canvas would then draw the
    /// previous score's music. NOT `renderedKey` either -- a forced re-render
    /// keeps that string and changes the pages under it -- so a stamp is
    /// added, allocated where the ENGRAVING is made. It therefore changes
    /// exactly when the pages change, and stays put when a held engraving is
    /// shown again, which is what keeps that engraving's rasters valid.
    ///
    /// Deliberately not `@Published`: it is set immediately before
    /// `pdfDocument`, whose publish is what rebuilds the canvas, so the canvas
    /// always reads the value belonging to the document it was handed. A second
    /// publish here would only invalidate the views this exists to spare.
    private(set) var engravingKey: String = ""
    private var engravingCount = 0

    /// An engraving and the stamp that names it.
    ///
    /// The stamp is allocated ONCE, when the engraving is made, and travels
    /// with it. That is what lets the two caches compose: coming back to an
    /// engraving already held gives back the same `engravingKey`, so the
    /// canvas rasters drawn from it are still valid. Stamping on every render
    /// instead -- which is what a plain counter did -- made returning to a
    /// held engraving free of Verovio and then redrew every one of its tiles,
    /// 101 rasters over six layout switches that should have needed none.
    struct HeldEngraving {
        let engraving: VerovioRenderer.Engraving
        let stamp: Int
    }

    /// Engravings already made, by "<slug>/<version>/<layout>".
    ///
    /// A version is IMMUTABLE -- every op writes a new one -- so an engraving
    /// of it can never go stale, and the only reason to throw one away is the
    /// memory it holds. Which is little: an eleven-page quartet's PDF is a
    /// couple of megabytes, against 3.1 s of Verovio and SwiftDraw to make it
    /// again.
    ///
    /// Four of them, roughly, at 24MB. Enough to hold both layouts of the
    /// version being read and both of the one before it, which is the pattern
    /// a reader comparing two versions actually makes.
    static let engravings = MemoCache<String, HeldEngraving>(budget: 24 << 20)

    /// What an engraving costs to hold. The PDF is nearly all of it; the
    /// geometry is a few thousand small structs, charged at a flat rate rather
    /// than walked, because walking it to size it would cost more than the
    /// entry is worth.
    static func engravingBytes(_ held: HeldEngraving) -> Int {
        held.engraving.pdf.count + 64 * 1024
    }

    var client: EngineClient { EngineClient(baseURLString: engineURLString) }
    let local = LocalEngine()
    /// Pencil markup state. Lives here because the pill drives it and the score
    /// pane only reacts, the same reason highlightMode moved up in build 116.
    let annotation = AnnotationController()
    /// Sound. Lives here for the same reason: the transport drives it and the
    /// canvas only follows the play head.
    let playback = PlaybackEngine()

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

    /// The folder import a reader is looking at before deciding to run it.
    @Published var folderImportPlan: FolderImportPlan?
    @Published var folderImportBusy = false
    /// Pieces the reader has deselected on the plan screen. A whole exported
    /// library usually holds something that does not belong -- a fake book, a
    /// lyrics sheet -- and taking it out at import is easier than unpicking it
    /// afterwards.
    @Published var folderImportExcluded: Set<String> = []
    /// What the last run actually did, so the screen can report rather than
    /// just closing and leaving the reader to count rows.
    @Published var folderImportResult: String?

    /// Read a folder and work out the pieces and arrangements in it. Writes
    /// nothing.
    @discardableResult
    func previewFolderImport(at url: URL) async -> Bool {
        folderImportBusy = true
        defer { folderImportBusy = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // Listed HERE, inside the scope the picker granted: Python cannot
        // enumerate a file-provider folder (FolderScan).
        let files = FolderScan.relativePaths(in: url)
        guard !files.isEmpty else {
            notice = "Nothing to import from \u{201C}\(url.lastPathComponent)\u{201D} \u{2014} "
                   + "the folder looks empty. If it lives in iCloud Drive, open it "
                   + "in Files and download it first."
            return false
        }
        do {
            let payload = try await local.bulkImport(folder: url, files: files,
                                                     commit: false)
            guard let plan = FolderImportPlan.decode(payload, folder: url) else {
                notice = "That folder could not be read as a library."
                return false
            }
            guard !plan.isEmpty else {
                notice = "No scores in \u{201C}\(url.lastPathComponent)\u{201D}: "
                       + "\(files.count) file\(files.count == 1 ? "" : "s") found, "
                       + "none of them notation or PDF."
                return false
            }
            folderImportPlan = plan
            folderImportExcluded = []
            folderImportResult = nil
            return true
        } catch {
            notice = "That folder could not be imported: \(error.localizedDescription)"
            return false
        }
    }

    /// Run the plan the reader just approved.
    func commitFolderImport() async {
        guard let plan = folderImportPlan else { return }
        folderImportBusy = true
        defer { folderImportBusy = false }
        let scoped = plan.folder.startAccessingSecurityScopedResource()
        defer { if scoped { plan.folder.stopAccessingSecurityScopedResource() } }
        do {
            let payload = try await local.bulkImport(
                folder: plan.folder,
                files: FolderScan.relativePaths(in: plan.folder), commit: true,
                exclude: Array(folderImportExcluded))
            let result = payload["result"] as? [String: Any]
            let imported = (result?["imported"] as? [Any])?.count ?? 0
            let failed = (result?["failed"] as? [Any])?.count ?? 0
            folderImportResult = failed == 0
                ? "Imported \(imported) arrangements."
                : "Imported \(imported); \(failed) could not be read."
            await refresh()
        } catch {
            report("import that folder", error)
        }
    }

    /// Notation or a scan. Read from the artifact's own filename, so it is
    /// right even for a library written before scans existed.
    var displayedArtifact: ScoreArtifact.Kind {
        ScoreArtifact.kind(ofFile: displayedVersion?.file ?? "")
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

    func startPolling() {
        // A measurement run asks for the readings in the log (-perfDump);
        // nothing happens without it.
        PerfMetrics.shared.startConsoleDumpIfRequested()
        // The rasters the canvas holds are the first thing worth giving back
        // under pressure: every one of them can be drawn again, and being
        // killed cannot be undone. The engravings go with them -- 24MB is
        // worth handing back even at 3 s to make one again, when the
        // alternative is the app disappearing under the reader.
        CanvasRasters.observeMemoryWarnings { Self.engravings.clear() }
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

    /// Test fixture: one PDF arrangement, on request.
    ///
    /// Deliberately NOT part of `seedLibraryIfEmpty`: dozens of tests assert
    /// against that library's shape, and adding an arrangement to it would
    /// change counts and row order under all of them. It is also outside that
    /// function's empty-library guard, because the suite relaunches into an
    /// already-seeded library and the guard would skip this every time.
    func seedScanArrangementIfRequested() async {
        guard useLocalEngine,
              ProcessInfo.processInfo.arguments.contains("-seedScanArrangement")
        else { return }
        do {
            let existing = try await local.manifest().scores
            guard !existing.contains(where: { $0.slug.hasPrefix("scanned-score") }) else {
                return          // already there; importing again would stack copies
            }
            guard let seed = Bundle.main.resourceURL?.appending(path: "samples-seed"),
                  let scan = ((try? FileManager.default.contentsOfDirectory(
                    at: seed, includingPropertiesForKeys: nil)) ?? [])
                    .filter({ $0.pathExtension.lowercased() == "pdf" })
                    .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                    .first else { return }
            _ = try await local.call(op: "import-pdf",
                                     args: ["path": scan.path,
                                            "name": "Scanned score",
                                            "piece": "Scanned score"])
            await refresh()
        } catch {
            print("SCORANGER-SEED scan failed: \(error.localizedDescription)")
        }
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
            // Chord symbols to nudge. Neither sample score carries any, and
            // the chip's position-and-size row only appears for a selection of
            // adjustable elements -- so without this there is nothing to test
            // it against.
            if ProcessInfo.processInfo.arguments.contains("-seedChordChart"),
               let first = (try await local.manifest()).scores
                    .sorted(by: { $0.slug < $1.slug }).first {
                // "#0" targets the first part by INDEX. Reading a name out of
                // the manifest's parts snapshot made the fixture depend on when
                // that projection is populated, and it silently added nothing.
                let chart = (1...8).map { ["measure": $0,
                                           "symbol": ["C", "Dm7", "G7", "Am"][($0 - 1) % 4]] }
                do {
                    _ = try await local.call(op: "set-chords",
                                             args: ["score": first.slug,
                                                    "part": "#0",
                                                    "chords": chart])
                    print("SCORANGER-SEED chord chart on \(first.slug)")
                } catch {
                    print("SCORANGER-SEED chord chart FAILED: \(error)")
                }
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
            let manifestSpan = PerfMetrics.shared.begin(PerfMetrics.Name.manifest)
            let m = useLocalEngine ? try await local.manifest() : try await client.manifest()
            manifestSpan?.end()
            // Only publish a manifest that differs. The poll runs every 1.5s,
            // and republishing an identical library rebuilt the whole sidebar
            // — including any open context menu — twice a second, which is why
            // a long-press could keep the app from ever going idle.
            if manifest != m { manifest = m }
            engineOK = true
            reportedEngineFailure = nil   // a later outage speaks again
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
            // Once per failure, not once per poll. `refresh` runs every two
            // seconds, so reporting each one would put the bar back a second
            // after it was dismissed -- and staying silent is how a Python
            // import error at launch became "the app does nothing".
            if useLocalEngine {
                let said = OperationReport.failure("reach the score engine", error: error)
                if reportedEngineFailure != said {
                    reportedEngineFailure = said
                    notice = said
                }
            }
        }
    }

    /// Re-fetch the PDF when the displayed (score, version) changes.
    func renderIfNeeded(force: Bool = false) async {
        guard let score = selectedScore, let vid = displayedVersionID else { return }
        // The LAYOUT is part of the key: continuous is a different engraving of
        // the same music, so switching to it has to re-engrave. The slug is
        // still the first component, so RenderTransition reads this as the
        // same score and keeps the current pages up until the new ones arrive
        // rather than blanking the canvas (#44).
        let key = "\(score.slug)/\(vid)/\(layout.rawValue)"
        guard force || key != renderedKey else { return }
        // A forced render is asked for when the FILE behind the key changed
        // under it, which is the one thing the cache cannot see.
        if force { Self.engravings.forget(key) }
        // Nothing, rather than the wrong thing -- but only when the thing has
        // actually changed.
        //
        // The document was only swapped once the new engrave arrived, so the
        // PREVIOUS score stayed on screen until then: opening an arrangement
        // showed the last one you had open, then flipped. A blank canvas for a
        // moment is honest about a score you have not opened yet.
        //
        // It is NOT honest about the score you are editing. Every op makes a
        // version, so this branch also fired on "transpose these bars up a
        // tone" -- blanking the whole page, throwing away which page the reader
        // was on, and clearing the selection the op had just been run on, which
        // `carrySelection` was then unable to carry because there was nothing
        // left to carry (#44). The previous engraving of the same music is the
        // best thing to show until the next one is ready.
        let transition = RenderTransition.between(previous: renderedKey, next: key)
        if transition.blanksTheCanvas {
            pageIndex = 0
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
        let renderSpan = PerfMetrics.shared.begin(PerfMetrics.Name.render)
        defer { renderSpan?.end() }
        do {
            let data: Data
            var model: ScoreGeometry?
            var engravedAdjustments: [ScoreAddress: ChordAdjustments.Adjustment] = [:]
            /// Which engraving this is, for the canvas's raster keys. Bumped
            /// only where a new one is actually made.
            var stamp = 0
            if useLocalEngine {
                let path = try await local.versionFilePath(score: score.slug, version: vid)
                if ScoreArtifact.kind(ofFile: path) == .scan {
                    // A PDF the reader brought in. There is nothing to engrave:
                    // the artifact IS the pages, so it is shown exactly as it
                    // arrived. No geometry, which is what makes selection and
                    // chat editing unavailable until OMR turns it into
                    // notation -- see ScoreArtifact.
                    data = try Data(contentsOf: URL(fileURLWithPath: path))
                    model = nil
                } else {
                    // one engrave: the pages drawn and the model hit-tested are
                    // the same Verovio load, or a lasso would select from a
                    // stale page
                    //
                    // ...and the same engrave twice is one engrave. `key`
                    // names the slug, the version AND the layout, so a reader
                    // toggling page / continuous / page paid three full
                    // engraves for two pictures -- and an engrave is the
                    // largest single cost in the app, 3.1 s median in a
                    // RELEASE build. Held here rather than inside the renderer
                    // because the actor is a toolkit, not a memory.
                    let held = try await Self.engravings.asyncValue(
                        for: key, cost: Self.engravingBytes,
                        make: {
                            let made = try await VerovioRenderer.shared.engrave(
                                musicXMLPath: path, layout: layout)
                            engravingCount += 1
                            return HeldEngraving(engraving: made,
                                                 stamp: engravingCount)
                        })
                    data = held.engraving.pdf
                    model = held.engraving.geometry
                    engravedAdjustments = held.engraving.chordAdjustments
                    stamp = held.stamp
                }
            } else {
                data = try await client.exportPDF(score: score.slug, version: vid)
            }
            if renderedKey == key {  // selection may have moved while fetching
                rendered = true
                // Before the document, so the canvas the publish rebuilds
                // reads the key belonging to the pages it is handed.
                if stamp == 0 { engravingCount += 1; stamp = engravingCount }
                engravingKey = "\(key)#\(stamp)"
                pdfDocument = PDFDocument(data: data)
                // The reader's page is kept across an op, and an op can make
                // the score shorter -- an index past the end renders as no
                // pages at all, which is the blank canvas this was avoiding.
                pageIndex = PagedCanvas.clampedIndex(pageIndex,
                                                     pageCount: pdfDocument?.pageCount ?? 0)
                geometry = model
                chordAdjustments = engravedAdjustments
                let previousKey = geometryKey
                geometryKey = key
                carrySelection(from: previousKey, to: key, into: model)
                // the addresses survived the re-render, so the session follows
                // them: nudge, commit, nudge again on the same symbol
                retargetAdjustment()
                // The sound is NOT carried over. A selection survives an op
                // because it still points at the same music; a performance
                // does not -- the op changed the notes. Rebuilding it is the
                // reader's next press of play, not this render's business.
                invalidatePlaybackIfStale()
                lastError = nil
            }
        } catch let e as EngineError {
            lastError = e.error
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Playback

    /// The version being listened to, which must be the version being LOOKED
    /// at. Audio from a version the reader has moved off is a lie the ear has
    /// no way to catch.
    private var playbackKey: String? {
        guard let slug = selectedScore?.slug, let vid = displayedVersionID else { return nil }
        return "\(slug)/\(vid)"
    }

    /// Is the mixer on screen, and where is it parked.
    ///
    /// Here rather than in the view because the transport opens it and the
    /// canvas draws it, the same reason the ink controller lives here.
    @Published var mixerOpen = false
    @Published var mixerCorner = MixerLayout.Corner.bottomTrailing

    /// Who is deciding which page is shown while the music plays.
    @Published var pageFollow = PageFollow()

    /// True while the engine is writing the MIDI. A long score takes a moment
    /// and a dead play button reads as a dead app.
    @Published var playbackPreparing = false

    /// Whether the arrangement on screen can be played at all.
    ///
    /// A scan cannot: there is no notation behind it until OMR has run, which
    /// is the same reason selection and chat editing are unavailable on one.
    /// The remote engine cannot either -- `playback` is a bridge op, and
    /// `scor serve` has no route for it -- and the transport says so rather
    /// than offering a button that does nothing.
    var playbackAvailability: PlaybackAvailability {
        .of(artifact: displayedArtifact, omrBusy: omrBusy, localEngine: useLocalEngine)
    }

    /// The remedy the transport is offering, performed.
    ///
    /// The transport is a second way in, not a replacement: "Make editable" in
    /// the More screen still does the same thing, and keeping it is the rule --
    /// never remove the current access path in the build that adds a new one.
    func resolvePlaybackAvailability() {
        switch playbackAvailability {
        case .needsTranscription: makeEditable()
        // Settings belongs to the view that owns the screen stack; ContentView
        // handles that case before calling this.
        case .needsLocalEngine:   break
        case .available, .transcribing: break
        }
    }

    /// Build the performance for the version on screen, unless it is already
    /// built.
    ///
    /// Never awaited by `renderIfNeeded`, and never started by it: opening a
    /// score must not wait on music21 writing a MIDI file. This runs when the
    /// reader shows the transport or presses play, which is the first moment
    /// anyone wants the sound.
    func preparePlayback() async {
        guard playbackAvailability.canPlay, let key = playbackKey,
              let score = selectedScore else { return }
        guard playback.loadedKey != key, !playbackPreparing else { return }
        playbackPreparing = true
        defer { playbackPreparing = false }
        do {
            let performance = try await local.playback(score: score.slug,
                                                       version: displayedVersionID)
            // The reader may have moved to another version while music21 was
            // writing. Loading it now would put the previous arrangement under
            // the play head, which is exactly the lie this key exists to stop.
            guard playbackKey == key else { return }
            try playback.load(midi: performance.midi, timeline: performance.timeline,
                              key: key)
            playback.report(unavailable: nil)
        } catch {
            // Said in the TRANSPORT, which is where someone who just pressed
            // play is looking, and not also in a notice: one failure, one
            // report. A failure to build the audio graph used to leave a play
            // button that did nothing and a voice list with nothing in it.
            playback.report(unavailable: OperationReport.reason(error))
        }
    }

    /// Press play. Prepares first when nothing is loaded, so the reader's
    /// first press is the only thing they have to do.
    func togglePlayback() {
        if playback.isPlaying { playback.stop(); return }
        if playback.canPlay, playback.loadedKey == playbackKey {
            playback.play()
            return
        }
        Task {
            await preparePlayback()
            if playback.canPlay { playback.play() }
        }
    }

    /// Drop a performance that no longer matches the page.
    ///
    /// Every op makes a version, so this fires on "transpose these bars up a
    /// tone" as well as on switching arrangement -- and it should. The sound
    /// belonged to music that is no longer on screen.
    /// The reader turned a page themselves. Following yields until they ask
    /// for it back; the music is untouched.
    func readerTurnedPage() {
        guard playback.isPlaying, pageFollow.isFollowing else { return }
        pageFollow.readerTurnedPage()
    }

    func invalidatePlaybackIfStale() {
        guard let loaded = playback.loadedKey else { return }
        guard loaded != playbackKey else { return }
        playback.forget()
    }

    /// Run OMR on the scan being read, and add the transcription as the next
    /// version of the SAME arrangement.
    ///
    /// Only meaningful for a scan: notation is already editable.
    func makeEditable() {
        guard let slug = selectedSlug,
              let version = displayedVersion,
              ScoreArtifact.kind(ofFile: version.file) == .scan else { return }
        // Claimed HERE, not inside convertPDF: fetching the artifact's path is
        // a round trip to the engine, and until this was set both ways in --
        // the More screen's switch and the transport's button -- read as idle
        // and a second tap started a second run on the same page.
        guard !omrBusy else { return }
        omrBusy = true
        Task {
            do {
                let path = try await local.versionFilePath(score: slug, version: version.id)
                convertPDF(at: URL(fileURLWithPath: path), intoScore: slug)
            } catch {
                omrBusy = false
                notice = "That scan could not be opened for transcription: "
                       + OperationReport.reason(error)
            }
        }
    }

    /// Take a page range out of a book as a new arrangement.
    ///
    /// Returns the slug so the caller can open what it just made. The book is
    /// unchanged: the pages are copied.
    @discardableResult
    func extractFromBook(_ book: String, from: Int, to: Int, name: String,
                         piece: String?) async -> String? {
        do {
            let slug = try await local.extractFromBook(book, from: from, to: to,
                                                       name: name, piece: piece)
            await refresh()
            return slug
        } catch {
            // Said out loud, like the import above it. BookScreen shows a note
            // when it works and showed NOTHING when it did not.
            let reason = OperationReport.reason(error)
            notice = BookImportStage.extractionFailure(name: name, reason: reason)
            return nil
        }
    }

    /// Import a PDF as a BOOK: a collection to take arrangements out of.
    ///
    /// It says so on screen while it runs and says so when it fails. Both were
    /// missing: a fake book is a big file and the copy alone takes a while, so
    /// a silent Task looked exactly like a broken one -- and the failure it
    /// was actually hitting (pypdf was not vendored into the app) landed in
    /// `lastError`, which the library does not display.
    func importBook(at url: URL) {
        let name = url.deletingPathExtension().lastPathComponent
        let pending = PendingImport(name: name, target: .book,
                                    stage: BookImportStage.copying)
        pendingImports.append(pending)
        Task {
            defer { pendingImports.removeAll { $0.id == pending.id } }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let tmp = FileManager.default.temporaryDirectory
                    .appending(path: url.lastPathComponent)
                try? FileManager.default.removeItem(at: tmp)
                try FileManager.default.copyItem(at: url, to: tmp)
                updatePending(pending.id, stage: BookImportStage.reading, fraction: nil)
                _ = try await local.importBook(fileURL: tmp, name: name)
                try? FileManager.default.removeItem(at: tmp)
                await refresh()
            } catch {
                let reason = OperationReport.reason(error)
                notice = BookImportStage.failure(name: name, reason: reason)
            }
        }
    }

    /// A file handed to us by the system (share sheet / "Open in").
    /// `piece` files the resulting arrangement under that piece (the sidebar's
    /// per-piece import); nil leaves it unfiled.
    func receiveFile(at url: URL, intoPiece piece: String? = nil) {
        if url.pathExtension.lowercased() == "pdf" {
            // A PDF comes in AS A PDF: it opens and takes markup immediately,
            // offline, with no service involved. It used to go straight to
            // cloud OMR, which meant a reader could not open their own scan
            // without a network and a wait, and got an imperfect transcription
            // instead of the page they know. `convertPDF` is kept: it is what
            // the explicit "make this editable" action will call.
            importPDF(at: url, intoPiece: piece)
        } else {
            importScore(from: url, intoPiece: piece)
        }
    }

    /// Import a PDF as a scan arrangement.
    func importPDF(at url: URL, intoPiece piece: String? = nil) {
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let tmp = FileManager.default.temporaryDirectory
                    .appending(path: url.lastPathComponent)
                try? FileManager.default.removeItem(at: tmp)
                try FileManager.default.copyItem(at: url, to: tmp)
                let name = url.deletingPathExtension().lastPathComponent
                let slug = try await local.importPDF(fileURL: tmp, name: name, piece: piece)
                try? FileManager.default.removeItem(at: tmp)
                selectedSlug = slug
                previewedSlug = slug
                pinnedVersion = nil
                await refresh()
            } catch {
                report("open that PDF", error)
            }
        }
    }

    /// PDF -> MusicXML via the cloud OMR service (Audiveris on Cloud Run),
    /// then import. Falls back to saving into Documents/intake when no
    /// service is configured.
    /// PDF -> MusicXML through the cloud OMR service.
    ///
    /// `intoScore` is OMR ON DEMAND: the transcription becomes the next
    /// version of that arrangement rather than a new one, so the scan the
    /// reader knows stays as v001 and the two can be compared with the version
    /// control. Without it, this is the old share-sheet path: a new
    /// arrangement from a PDF handed to the app from outside.
    private func convertPDF(at url: URL, intoPiece piece: String? = nil,
                            intoScore: String? = nil) {
        let scoped = url.startAccessingSecurityScopedResource()
        let pdfData = try? Data(contentsOf: url)
        let name = url.deletingPathExtension().lastPathComponent
        if scoped { url.stopAccessingSecurityScopedResource() }
        guard let pdfData else {
            omrBusy = false
            notice = "Couldn't read the PDF."
            return
        }
        guard let endpoint = URL(string: omrURLString), !omrURLString.isEmpty else {
            omrBusy = false
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
        omrPendingID = pending.id
        Task {
            defer {
                omrBusy = false
                omrPendingID = nil
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
                let slug: String
                if let intoScore {
                    // Prove it can be DRAWN before it becomes a version.
                    //
                    // OMR output is a draft and some of it cannot be engraved
                    // at all. Adding such a version made the arrangement open
                    // on "Render failed" with no way back -- and on a scan
                    // that is a strict loss, because the PDF the reader
                    // imported was perfectly readable a moment earlier. A
                    // transcription that cannot be drawn is not offered.
                    do {
                        _ = try await VerovioRenderer.shared.engrave(musicXMLPath: tmp.path)
                    } catch {
                        try? FileManager.default.removeItem(at: tmp)
                        notice = "That page could not be read into notation. "
                            + "The PDF is unchanged."
                        return
                    }
                    // the transcription joins the scan's own history
                    _ = try await local.addVersion(from: tmp, score: intoScore,
                                                   recordedAs: "omr")
                    slug = intoScore
                } else {
                    slug = try await local.importScore(fileURL: tmp, name: name, piece: piece)
                }
                try? FileManager.default.removeItem(at: tmp)
                selectedSlug = slug
                previewedSlug = slug
                // follow the newest version, which is the transcription
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
                report("import that file", error)
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
        } catch {
            report("save those details", error)
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

    /// Where a moved arrangement went. A pushed screen holds the slug it was
    /// opened with, and moving the arrangement is something you do ON that
    /// screen -- without this the screen and everything above it resolve to
    /// nothing the instant the move lands.
    @Published var movedSlugs: [String: String] = [:]

    /// Follows a chain of moves to whatever the slug is called now.
    func currentSlug(for slug: String) -> String {
        var now = slug
        var hops = 0
        while let next = movedSlugs[now], hops < 8 { now = next; hops += 1 }
        return now
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
                movedSlugs[slug] = now
                DrawingStore.shared.rename(fromPrefix: slug, toPrefix: now)
                if selectedSlug == slug { selectedSlug = now }
                if previewedSlug == slug { previewedSlug = now }
                renderedKey = nil   // the render is keyed by slug/version
            }
            await refresh()
            return now
        } catch {
            report("change that arrangement's short name", error)
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
        } catch {
            report("rename that part", error)
        }
        return false
    }

    /// Bring the Newzik metadata across, once.
    ///
    /// The library arrived as a folder of PDFs, which carry none: the composer,
    /// the tags and the corrected spellings lived in Newzik and reached the
    /// export only as folder names. This matches them back onto the pieces by
    /// name (`MetadataMigration`) and writes what is missing.
    ///
    /// It fills in; it does not overwrite. A piece that already carries a
    /// composer or tags keeps them, so running it again after importing more
    /// pieces does the new ones and leaves the rest alone. The flag is only
    /// there to keep it off the startup path forever.
    @discardableResult
    func applyBundledMetadataIfNeeded(force: Bool = false) async -> Int {
        let key = "newzik-metadata-applied"
        if !force && UserDefaults.standard.bool(forKey: key) { return 0 }
        let entries = MetadataMigration.bundled()
        guard !entries.isEmpty else { return 0 }
        guard let pieces = manifest?.pieces, !pieces.isEmpty else { return 0 }

        let plan = MetadataMigration.plan(entries: entries, pieces: pieces)
        var written = 0
        for action in plan.actions {
            do {
                if let rename = action.rename {
                    _ = try await local.call(op: "rename-piece",
                                             args: ["piece": action.slug, "name": rename])
                }
                var args: [String: Any] = ["piece": action.slug]
                if !action.composer.isEmpty { args["composer"] = action.composer }
                if !action.arranger.isEmpty { args["arranger"] = action.arranger }
                if !action.tags.isEmpty { args["tags"] = action.tags }
                if args.count > 1 {
                    _ = try await local.call(op: "set-piece-metadata", args: args)
                }
                written += 1
            } catch {
                // INTERNAL, deliberately silent. One piece failing is not a
                // reason to abandon the other 39, and this migration is not
                // something the reader asked for -- a bar apiece, forty times,
                // over work nobody requested, is worse than saying nothing.
                // What it did NOT write stays visibly blank on the piece.
                print("SCORANGER-MIGRATE piece \(action.slug): \(error)")
            }
        }
        UserDefaults.standard.set(true, forKey: key)
        if written > 0 { await refresh() }
        return written
    }

    /// Set a piece's own composer, arranger and tags.
    @discardableResult
    func setPieceMetadata(_ slug: String, composer: String? = nil,
                          arranger: String? = nil, tags: [String]? = nil) async -> Bool {
        var args: [String: Any] = ["piece": slug]
        if let composer { args["composer"] = composer }
        if let arranger { args["arranger"] = arranger }
        if let tags { args["tags"] = tags }
        do {
            _ = try await local.call(op: "set-piece-metadata", args: args)
            await refresh()
            return true
        } catch {
            report("save that piece's details", error)
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
        } catch {
            report("rename that piece", error)
        }
        return false
    }

    /// Duplicate an arrangement into a new independent copy (new slug, its own
    /// history, filed under the same piece). Returns the copy's slug.
    @discardableResult
    /// Write an arrangement out as a file the user can share.
    ///
    /// The file is named for the arrangement, not for its version id, because
    /// it is about to leave the app: "v003.musicxml" tells nobody anything once
    /// it is sitting in Files. A PINNED version is named too, since that is
    /// part of what the file is.
    ///
    /// PDF is engraved HERE rather than in the bridge. That is the one thing to
    /// keep straight in this function: chord-symbol adjustments and whistle
    /// fingerings are applied in the Swift render pass, so a PDF from anywhere
    /// else would not match the page on screen. `bridge.py` refuses PDF for the
    /// same reason.
    func exportFile(slug: String, version: String?,
                    format: ScoreExport.Format) async -> URL? {
        guard let score = manifest?.scores.first(where: { $0.slug == slug }) else {
            notice = "Couldn't export: there is no arrangement '\(slug)'."
            return nil
        }
        let name = ScoreExport.filename(title: score.title ?? score.name,
                                        version: version, format: format)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("export", isDirectory: true)
            .appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            if format.isRenderedOnDevice {
                guard useLocalEngine else {
                    let data = try await client.exportPDF(score: slug, version: version)
                    try data.write(to: dest)
                    return dest
                }
                let source = try await local.versionFilePath(score: slug, version: version)
                let data = try await VerovioRenderer.shared.renderPDF(musicXMLPath: source)
                try data.write(to: dest)
            } else {
                let produced = try await local.exportFile(score: slug, version: version,
                                                          format: format.rawValue)
                try FileManager.default.copyItem(at: URL(fileURLWithPath: produced), to: dest)
            }
            return dest
        } catch {
            report("export that arrangement", error)
        }
        return nil
    }

    func duplicateScore(slug: String, name: String? = nil) async -> String? {
        do {
            var args: [String: Any] = ["score": slug]
            if let name { args["name"] = name }
            let r = try await local.call(op: "duplicate", args: args)
            await refresh()
            return r["score"] as? String
        } catch {
            report("duplicate that arrangement", error)
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
            } catch {
                report("file that arrangement", error)
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
        } catch {
            report("create the arrangement", error)
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
        } catch {
            report("create that set list", error)
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
        } catch {
            report("change that set list", error)
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
            } catch {
                report("move that arrangement", error)
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
        } catch {
            report("reorder that set list", error)
        }
        return false
    }

    func reorderPiece(piece: String, order: [String]) {
        Task {
            do {
                _ = try await local.call(op: "reorder-piece",
                                         args: ["piece": piece, "order": order])
                await refresh()
            } catch {
                report("reorder that piece", error)
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
        } catch {
            report("create that piece", error)
        }
        return nil
    }

    func createPieceAndAssign(name: String, scoreSlug: String) {
        Task {
            do {
                _ = try await local.call(op: "assign-piece",
                                         args: ["score": scoreSlug, "piece": name])
                await refresh()
            } catch {
                report("file that arrangement under a new piece", error)
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
            } catch {
                report("delete that piece", error)
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
            } catch {
                report("delete that arrangement", error)
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
            } catch {
                report("transpose the score", error)
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
            } catch {
                report("respell the score", error)
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
