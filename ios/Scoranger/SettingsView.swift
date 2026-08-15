import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
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
        NavigationStack {
            Form {
                Section("On-device engine") {
                    Toggle("Use on-device engine", isOn: $state.useLocalEngine)
                    SecureField("OpenRouter API key (sk-or-…)", text: $apiKeyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: apiKeyDraft) { _, value in
                            KeychainStore.openRouterKey = value
                        }
                    Text("On: scores live on this iPad; no laptop needed. Off: connect to `scor serve` on your Mac (URL below).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(selfTestRunning ? "Running…" : "Run engine self-test") {
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
                    .disabled(selfTestRunning)
                    if !selfTestResult.isEmpty {
                        Text(selfTestResult)
                            .font(.footnote.monospaced())
                            .foregroundStyle(selfTestResult.contains("failed") ? .red : .green)
                    }
                }
                if !state.useLocalEngine {
                    Section("Remote engine") {
                        TextField("http://your-mac.local:8765", text: $urlDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .onChange(of: urlDraft) { _, value in
                                state.engineURLString = value.trimmingCharacters(in: .whitespaces)
                            }
                        LabeledContent("Status") {
                            Text(state.engineOK ? "Connected" : "Unreachable")
                                .foregroundStyle(state.engineOK ? .green : .red)
                        }
                        Text("Run `engine/.venv/bin/scor serve` on your Mac. Use your Mac's hostname (e.g. http://alis-mac.local:8765) so the iPad can reach it over the local network.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("PDF conversion (OMR)") {
                    TextField("https://scoranger-omr-….run.app", text: $omrURLDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onChange(of: omrURLDraft) { _, value in
                            state.omrURLString = value.trimmingCharacters(in: .whitespaces)
                        }
                    SecureField("OMR service API key", text: $omrKeyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: omrKeyDraft) { _, value in
                            KeychainStore.omrKey = value
                        }
                    Button(omrTestRunning ? "Testing…" : "Test connection & key") {
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
                    if !omrTestResult.isEmpty {
                        Text(omrTestResult)
                            .font(.footnote)
                            .foregroundStyle(omrTestResult.hasPrefix("✓") ? .green : .red)
                    }
                    Text("Share a PDF into Scoranger and it's converted to a score by Audiveris running in the cloud. Leave empty to just collect PDFs in Files → Scoranger → intake.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Chat model") {
                    if let catalog = state.modelCatalog {
                        Picker("Model", selection: $state.chatModel) {
                            ForEach(catalog.models.keys.sorted(), id: \.self) { alias in
                                Text("\(alias) — \(catalog.models[alias] ?? "")").tag(alias)
                            }
                        }
                        .pickerStyle(.inline)
                    } else {
                        Text("Model list loads once the engine is reachable.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // fields already write through onChange; just refresh
                        Task { await state.refresh() }
                        dismiss()
                    }
                }
            }
            .onAppear {
                urlDraft = state.engineURLString
                apiKeyDraft = KeychainStore.openRouterKey
                omrURLDraft = state.omrURLString
                omrKeyDraft = KeychainStore.omrKey
            }
        }
    }
}
