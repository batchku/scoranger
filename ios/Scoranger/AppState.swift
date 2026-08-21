import Foundation
import PDFKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var manifest: Manifest?
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

    /// Pencil-highlighted measure range on the displayed score (v1 estimate
    /// from stroke geometry). Injected into chat context so "the highlighted
    /// passage" resolves to these bars.
    @Published var highlightedBars: ClosedRange<Int>?
    /// Where the highlight came from (e.g. "pencil highlight on page 2").
    @Published var highlightNote: String?
    /// Highlight-capture mode. Lives here, not in the score pane, because the
    /// score's gear menu turns it on and the pane only reacts.
    @Published var highlightMode = false
    /// The drawn highlight band per page index, in unit (0…1) page coordinates,
    /// so the yellow band stays visible (across zoom levels) while a highlight
    /// is active. Cleared together with `highlightedBars`.
    @Published var highlightBands: [Int: CGRect] = [:]

    /// Drop the active highlight and its drawn bands.
    func clearHighlight() {
        highlightedBars = nil
        highlightNote = nil
        highlightBands = [:]
    }

    /// PDFs currently being converted in the cloud — shown greyed out in the
    /// scores list with a live stage until they become real scores (or fail).
    struct PendingImport: Identifiable, Equatable {
        let id = UUID()
        let name: String
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

    /// Sidebar setlists: each setlist with its pieces resolved to PieceDocs.
    var setlistSections: [(setlist: SetlistDoc, pieces: [PieceDoc])] {
        guard let m = manifest, let setlists = m.setlists else { return [] }
        return setlists.map { s in
            (setlist: s,
             pieces: s.pieces.compactMap { slug in (m.pieces ?? []).first { $0.slug == slug } })
        }
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

    var selectedScore: ScoreDoc? {
        guard let scores = manifest?.scores else { return nil }
        if let slug = selectedSlug, let s = scores.first(where: { $0.slug == slug }) { return s }
        // default: most recently updated
        return scores.max { ($0.versions.last?.time ?? "") < ($1.versions.last?.time ?? "") }
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
            _ = try await local.call(op: "assign-setlist",
                                     args: ["setlist": "Test setlist", "piece": pieceName])
            print("SCORANGER-SEED imported \(files.count) sample score(s)")
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
        scanInbox()
        #if DEBUG
        scanChatInbox()
        #endif
        do {
            let m = useLocalEngine ? try await local.manifest() : try await client.manifest()
            manifest = m
            engineOK = true
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
        renderedKey = key
        loadingPDF = true
        defer { loadingPDF = false }
        do {
            let data: Data
            if useLocalEngine {
                let path = try await local.versionFilePath(score: score.slug, version: vid)
                data = try await VerovioRenderer.shared.renderPDF(musicXMLPath: path)
            } else {
                data = try await client.exportPDF(score: score.slug, version: vid)
            }
            if renderedKey == key {  // selection may have moved while fetching
                pdfDocument = PDFDocument(data: data)
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
        omrBusy = true
        let pending = PendingImport(name: name)
        pendingImports.append(pending)
        Task {
            defer {
                omrBusy = false
                pendingImports.removeAll { $0.id == pending.id }
            }
            do {
                // stored key if present, baked-in default otherwise; a 401
                // self-heals below by falling back to the baked key
                let bakedKey = (Bundle.main.url(forResource: "omr-default-key", withExtension: "txt")
                    .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                var apiKey = KeychainStore.omrKey.isEmpty ? bakedKey : KeychainStore.omrKey

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
                            for: request, from: pdfData, delegate: progressDelegate)
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
                notice = "PDF conversion of “\(name)” failed: \(error.localizedDescription)"
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
        if slug != selectedSlug {
            // a highlight describes bars of the previously shown score
            clearHighlight()
        }
        selectedSlug = slug
        previewedSlug = slug
        pinnedVersion = version
        Task { await renderIfNeeded() }
    }

    /// Rename an arrangement. Label only: the slug stays, so version artifacts,
    /// the piece's ordering and any 'arr:' chat references keep working, and no
    /// new version is created because the notation is untouched.
    @discardableResult
    func renameScore(slug: String, name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            _ = try await local.call(op: "rename-score",
                                     args: ["score": slug, "name": trimmed])
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

    /// Create an empty setlist.
    @discardableResult
    func createSetlist(name: String) async -> Bool {
        await runSetlistOp(op: "create-setlist", args: ["name": name])
    }

    /// Add a piece to a setlist (no-op if already a member).
    @discardableResult
    func addPieceToSetlist(setlist: String, piece: String) async -> Bool {
        await runSetlistOp(op: "assign-setlist",
                           args: ["setlist": setlist, "piece": piece])
    }

    /// Drop a piece from a setlist. The piece itself is untouched.
    @discardableResult
    func removePieceFromSetlist(setlist: String, piece: String) async -> Bool {
        await runSetlistOp(op: "unassign-setlist",
                           args: ["setlist": setlist, "piece": piece])
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

    /// Persist a piece's arrangement order (the sidebar numbering).
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

    /// Chat context plus the active pencil highlight, if any, so prompts can
    /// say "the highlighted passage" and mean those measures.
    func chatContextWithHighlight(for slug: String) -> String? {
        var pieces: [String] = []
        if let base = chatContext(for: slug) { pieces.append(base) }
        if let bars = highlightedBars {
            pieces.append("A highlight is ACTIVE on measures \(bars.lowerBound)–\(bars.upperBound). "
                + "Apply every operation ONLY to that range: pass "
                + "from_measure=\(bars.lowerBound) and to_measure=\(bars.upperBound) to tools "
                + "that accept them (transpose, respell, octave_shift), and refuse or ask "
                + "before making whole-piece changes while the highlight is active. Requests "
                + "referring to 'the highlighted passage/selection' mean exactly those measures.")
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: " ")
    }

    /// Create a new piece by name and file the score under it (assign-piece
    /// creates missing pieces).
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
    func deleteScore(slug: String) {
        Task {
            do {
                try await local.deleteScore(slug)
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
