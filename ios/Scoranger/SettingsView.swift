import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var urlDraft = ""
    @State private var selfTestResult = ""
    @State private var selfTestRunning = false
    @State private var apiKeyDraft = ""
    @State private var omrURLDraft = ""
    @State private var omrKeyDraft = ""
    @State private var omrTestResult = ""
    @State private var omrTestRunning = false

    /// Send a tiny non-PDF body: 415 back = URL and key both good
    /// (the request passed auth and reached content validation).
    static func testOMR(urlString: String, key: String) async -> String {
        guard let url = URL(string: urlString), !urlString.isEmpty else {
            return "✗ enter the service URL first"
        }
        var req = URLRequest(url: url.appending(path: "omr"))
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue(key, forHTTPHeaderField: "X-API-Key")
        do {
            let (_, resp) = try await URLSession(configuration: .ephemeral)
                .upload(for: req, from: Data("ping".utf8))
            switch (resp as? HTTPURLResponse)?.statusCode ?? 0 {
            case 415: return "✓ service reachable, key accepted"
            case 401: return "✗ service reachable but the key is wrong"
            case let code: return "✗ unexpected response (HTTP \(code))"
            }
        } catch {
            return "✗ can't reach the service: \(error.localizedDescription)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BandHeader("On-device engine")
            VStack(alignment: .leading, spacing: Theme.Metric.s12) {
                HStack(spacing: Theme.Metric.s12) {
                    PanelToggle(title: "Use on-device engine", isOn: $state.useLocalEngine)
                }
                LED(isOn: state.engineOK)
                PanelField(placeholder: "OpenRouter API key (sk-or-…)",
                           text: $apiKeyDraft, isSecure: true)
                    .onChange(of: apiKeyDraft) { _, value in
                        KeychainStore.openRouterKey = value
                    }
                PanelNote(text: "On: scores live on this iPad; no laptop needed. Off: connect to scor serve on your Mac.")
                HStack {
                    PanelButton(title: selfTestRunning ? "Running…" : "Run engine self-test") {
                        runSelfTest()
                    }
                    .disabled(selfTestRunning)
                    Spacer()
                }
                if !selfTestResult.isEmpty {
                    WellBlock(text: selfTestResult,
                              tint: selfTestResult.contains("failed") ? Theme.Status.danger
                                                                     : Theme.Status.ok)
                }
            }
            .padding(Theme.Metric.panelPadding)

            if !state.useLocalEngine {
                BandHeader("Remote engine")
                VStack(alignment: .leading, spacing: Theme.Metric.s12) {
                    PanelField(placeholder: "http://your-mac.local:8765",
                               text: $urlDraft, isMono: true)
                        .onChange(of: urlDraft) { _, value in
                            state.engineURLString = value.trimmingCharacters(in: .whitespaces)
                        }
                    PanelNote(text: "Run engine/.venv/bin/scor serve on your Mac, and use its hostname so the iPad can reach it over the local network.")
                }
                .padding(Theme.Metric.panelPadding)
            }

            BandHeader("PDF conversion (OMR)")
            VStack(alignment: .leading, spacing: Theme.Metric.s12) {
                PanelField(placeholder: "https://scoranger-omr-….run.app",
                           text: $omrURLDraft, isMono: true)
                    .onChange(of: omrURLDraft) { _, value in
                        state.omrURLString = value.trimmingCharacters(in: .whitespaces)
                    }
                PanelField(placeholder: "OMR service API key",
                           text: $omrKeyDraft, isSecure: true)
                    .onChange(of: omrKeyDraft) { _, value in
                        KeychainStore.omrKey = value
                    }
                HStack {
                    PanelButton(title: omrTestRunning ? "Testing…" : "Test connection & key") {
                        omrTestRunning = true
                        omrTestResult = ""
                        Task {
                            omrTestResult = await Self.testOMR(
                                urlString: omrURLDraft.trimmingCharacters(in: .whitespaces),
                                key: omrKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                            omrTestRunning = false
                        }
                    }
                    .disabled(omrTestRunning)
                    Spacer()
                }
                if !omrTestResult.isEmpty {
                    WellBlock(text: omrTestResult,
                              tint: omrTestResult.hasPrefix("✓") ? Theme.Status.ok
                                                                 : Theme.Status.danger)
                }
                PanelNote(text: "Share a PDF into Scoranger and Audiveris converts it in the cloud. Leave empty to collect PDFs in Files → Scoranger → intake.")
            }
            .padding(Theme.Metric.panelPadding)

            BandHeader("Chat model")
            VStack(alignment: .leading, spacing: Theme.Metric.s8) {
                if let catalog = state.modelCatalog {
                    ForEach(catalog.models.keys.sorted(), id: \.self) { alias in
                        Button {
                            state.chatModel = alias
                        } label: {
                            HStack(spacing: Theme.Metric.s8) {
                                Image(systemName: state.chatModel == alias
                                      ? "circle.fill" : "circle")
                                    .font(.system(size: 9))
                                    .foregroundStyle(state.chatModel == alias
                                                     ? Theme.Accent.clay : Theme.Ink.ink3)
                                Text(alias).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                                Text(catalog.models[alias] ?? "").typeRole(.data)
                                    .foregroundStyle(Theme.Ink.ink3).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 30)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    PanelNote(text: "The model list loads once the engine is reachable.")
                }
            }
            .padding(Theme.Metric.panelPadding)
        }
        .onAppear {
            urlDraft = state.engineURLString
            apiKeyDraft = KeychainStore.openRouterKey
            omrURLDraft = state.omrURLString
            omrKeyDraft = KeychainStore.omrKey
        }
        .onDisappear { Task { await state.refresh() } }
    }

    private func runSelfTest() {
        selfTestRunning = true
        selfTestResult = ""
        Task {
            let started = await PythonEngine.shared.start()
            var lines: [String] = []
            if case .ready(let py, let m21) = started {
                lines.append("Python \(py) · music21 \(m21)")
                let r = await PythonEngine.shared.call(op: "selftest")
                if let ok = r["ok"] as? Bool, ok,
                   let result = r["result"] as? [String: Any] {
                    let pitches = (result["transposed"] as? [String]) ?? []
                    lines.append("C D E F → \(pitches.joined(separator: " ")) (up M2)")
                    lines.append("versions \((result["versions"] as? [String])?.joined(separator: ", ") ?? "?") ✓")
                } else {
                    lines.append("selftest failed: \(r["error"] as? String ?? "\(r)")")
                }
            } else {
                lines.append("engine failed: \(started)")
            }
            selfTestResult = lines.joined(separator: "\n")
            selfTestRunning = false
        }
    }
}
