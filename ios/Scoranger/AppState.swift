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
    @Published var modelCatalog: ModelCatalog?

    // chat, kept per score slug
    @Published var chatMessages: [String: [ChatDisplayMessage]] = [:]
    @Published var chatBusy = false
    var chatHistory: [String: String] = [:]

    @AppStorage("engineURL") var engineURLString = "http://localhost:8765"
    @AppStorage("chatModel") var chatModel = ""

    private var pollTask: Task<Void, Never>?
    private var renderedKey: String?

    var client: EngineClient { EngineClient(baseURLString: engineURLString) }

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
            let m = try await client.manifest()
            manifest = m
            engineOK = true
            if modelCatalog == nil {
                modelCatalog = try? await client.models()
                if chatModel.isEmpty, let def = modelCatalog?.default { chatModel = def }
            }
            await renderIfNeeded()
        } catch {
            engineOK = false
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
            let data = try await client.exportPDF(score: score.slug, version: vid)
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

    func select(slug: String) {
        selectedSlug = slug
        pinnedVersion = nil
        Task { await renderIfNeeded() }
    }

    func transpose(semitones: Int) {
        guard let slug = selectedScore?.slug else { return }
        Task {
            do {
                try await client.transpose(score: slug, semitones: semitones)
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
                let resp = try await client.chat(score: slug, message: message,
                                                 model: chatModel.isEmpty ? nil : chatModel,
                                                 history: chatHistory[slug])
                chatHistory[slug] = resp.history
                chatMessages[slug, default: []].append(.init(role: .agent, text: resp.reply))
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
