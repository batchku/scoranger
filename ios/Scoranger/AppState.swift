import Foundation
import PDFKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var manifest: Manifest?
    @Published var selectedSlug: String?
    /// nil = follow the score's latest version
    @Published var pinnedVersion: String?
    @Published var pdfDocument: PDFDocument?
    @Published var loadingPDF = false
    @Published var engineOK = false
    @Published var lastError: String?
    /// One-shot user-facing message shown as an alert (share-sheet receipts etc.)
    @Published var notice: String?
    @Published var omrBusy = false

    /// PDFs currently being converted in the cloud — shown greyed out in the
    /// scores list until they become real scores (or fail).
    struct PendingImport: Identifiable, Equatable {
        let id = UUID()
        let name: String
    }
    @Published var pendingImports: [PendingImport] = []
    @Published var modelCatalog: ModelCatalog?

    // chat, kept per score slug
    @Published var chatMessages: [String: [ChatDisplayMessage]] = [:]
    @Published var chatBusy = false
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

    var selectedScore: ScoreDoc? {
        guard let scores = manifest?.scores else { return nil }
        if let slug = selectedSlug, let s = scores.first(where: { $0.slug == slug }) { return s }
        // default: most recently updated
        return scores.max { ($0.versions.last?.time ?? "") < ($1.versions.last?.time ?? "") }
    }

    var displayedVersionID: String? {
        guard let score = selectedScore else { return nil }
        if let pin = pinnedVersion, score.versions.contains(where: { $0.id == pin }) { return pin }
        return score.latest
    }

    var displayedVersion: VersionDoc? {
        selectedScore?.versions.first { $0.id == displayedVersionID }
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

    func refresh() async {
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
    func receiveFile(at url: URL) {
        if url.pathExtension.lowercased() == "pdf" {
            convertPDF(at: url)
        } else {
            importScore(from: url)
        }
    }

    /// PDF -> MusicXML via the cloud OMR service (Audiveris on Cloud Run),
    /// then import. Falls back to saving into Documents/intake when no
    /// service is configured.
    private func convertPDF(at url: URL) {
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
                var request = URLRequest(url: endpoint.appending(path: "omr"))
                request.httpMethod = "POST"
                request.timeoutInterval = 600
                request.setValue(KeychainStore.omrKey, forHTTPHeaderField: "X-API-Key")
                request.setValue("application/pdf", forHTTPHeaderField: "Content-Type")

                // Cloud Run can kill an idle instance right as a request lands
                // (502, ~2s). Retry transient failures; give up on 4xx.
                // Each attempt gets a FRESH session: retrying on the pooled
                // HTTP/2 connection re-hits the same dead backend forever.
                var data = Data()
                var attempt = 0
                while true {
                    attempt += 1
                    do {
                        let session = URLSession(configuration: .ephemeral)
                        defer { session.finishTasksAndInvalidate() }
                        let (d, response) = try await session.upload(for: request, from: pdfData)
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        if code == 200 { data = d; break }
                        let detail = (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["error"] as? String
                        if code >= 500, attempt < 3 {
                            try await Task.sleep(for: .seconds(3))
                            continue
                        }
                        throw LocalEngineError.engine(detail ?? "OMR service error (HTTP \(code))")
                    } catch let e as LocalEngineError {
                        throw e
                    } catch where attempt < 3 {
                        try await Task.sleep(for: .seconds(3))
                    }
                }
                let tmp = FileManager.default.temporaryDirectory.appending(path: "\(name).mxl")
                try? FileManager.default.removeItem(at: tmp)
                try data.write(to: tmp)
                let slug = try await local.importScore(fileURL: tmp, name: name)
                try? FileManager.default.removeItem(at: tmp)
                selectedSlug = slug
                pinnedVersion = nil
                await refresh()
            } catch {
                notice = "PDF conversion of “\(name)” failed: \(error.localizedDescription)"
            }
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
    func importScore(from url: URL) {
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let tmp = FileManager.default.temporaryDirectory
                    .appending(path: url.lastPathComponent)
                try? FileManager.default.removeItem(at: tmp)
                try FileManager.default.copyItem(at: url, to: tmp)
                let name = url.deletingPathExtension().lastPathComponent
                let slug = try await local.importScore(fileURL: tmp, name: name)
                try? FileManager.default.removeItem(at: tmp)
                selectedSlug = slug
                pinnedVersion = nil
                await refresh()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func select(slug: String) {
        selectedSlug = slug
        pinnedVersion = nil
        Task { await renderIfNeeded() }
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

    func sendChat(_ text: String) {
        guard let slug = selectedScore?.slug, !chatBusy else { return }
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        chatMessages[slug, default: []].append(.init(role: .user, text: message))
        chatBusy = true
        Task {
            defer { chatBusy = false }
            do {
                if useLocalEngine {
                    let turn = try await LocalChat().run(
                        slug: slug, message: message,
                        modelAlias: chatModel.isEmpty ? nil : chatModel,
                        historyJSON: chatHistory[slug],
                        apiKey: KeychainStore.openRouterKey)
                    chatHistory[slug] = turn.historyJSON
                    chatMessages[slug, default: []].append(.init(role: .agent, text: turn.reply))
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
