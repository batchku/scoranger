import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var urlDraft = ""
    @State private var selfTestResult = ""
    @State private var selfTestRunning = false

    var body: some View {
        NavigationStack {
            Form {
                Section("On-device engine") {
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
                Section("Engine") {
                    TextField("http://your-mac.local:8765", text: $urlDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    LabeledContent("Status") {
                        Text(state.engineOK ? "Connected" : "Unreachable")
                            .foregroundStyle(state.engineOK ? .green : .red)
                    }
                    Text("Run `engine/.venv/bin/scor serve` on your Mac. Use your Mac's hostname (e.g. http://alis-mac.local:8765) so the iPad can reach it over the local network.")
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
                        state.engineURLString = urlDraft
                        Task { await state.refresh() }
                        dismiss()
                    }
                }
            }
            .onAppear { urlDraft = state.engineURLString }
        }
    }
}
