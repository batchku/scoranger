import SwiftUI

struct SettingsView: View {
    @AppStorage("touchDiagnostics") private var showTouchDiagnostics = false
    @EnvironmentObject var state: AppState
    @State private var urlDraft = ""
    @State private var selfTestResult = ""
    @State private var selfTestRunning = false
    @State private var apiKeyDraft = ""
    @State private var omrURLDraft = ""
    @State private var omrKeyDraft = ""
    @State private var omrTestResult = ""
    @State private var omrTestRunning = false
    /// What is actually in the keychain, so the field can say "saved" without
    /// the draft being the thing the network layer reads.
    @State private var savedChatKey = ""
    @State private var savedOMRKey = ""

    /// Send a tiny non-PDF body: 415 back = URL and key both good
    /// (the request passed auth and reached content validation).
    ///
    /// `key` must be the key the app would actually send — the saved one, or
    /// the built-in default when nothing is saved. Testing the *field* instead
    /// is what reported "the key is wrong" on a perfectly working install: the
    /// field is empty whenever the built-in key is in use.
    static func testOMR(urlString: String, key: String) async -> String {
        guard let url = URL(string: urlString), !urlString.isEmpty else {
            return "✗ enter the service URL first"
        }
        guard !key.isEmpty else {
            return "✗ no key: this build has no built-in key, so paste one above"
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
            BandHeader("Reading")
            VStack(alignment: .leading, spacing: Theme.Metric.s12) {
                PanelToggle(title: "Two pages side by side",
                            isOn: $state.twoPageSpread)
                PanelNote(text: "Two pages at once, the way a score sits on a stand. "
                          + "Best with the panels closed; one page at a time is larger.")
            }
            .padding(Theme.Metric.panelPadding)

            BandHeader("About")
            VStack(alignment: .leading, spacing: Theme.Metric.s8) {
                // The build stamp had no home once Home went, and a tester who
                // cannot say which build they are on cannot report anything
                // useful about it -- every device report in this project has
                // turned on knowing that.
                Text(BuildStamp.short)
                    .typeRole(.data)
                    .foregroundStyle(Theme.Ink.ink2)
                    .accessibilityIdentifier("build-stamp")
                PanelNote(text: "Quote this when reporting anything.")
            }
            .padding(Theme.Metric.panelPadding)

            BandHeader("Diagnostics")
            VStack(alignment: .leading, spacing: Theme.Metric.s12) {
                PanelToggle(title: "Show what the canvas is receiving",
                            isOn: $showTouchDiagnostics)
                PanelNote(text: "Prints every touch on the score — pencil or finger, how many "
                          + "are down, how long they were held, and whether a selection "
                          + "started. For reporting a gesture that is not working.")
            }
            .padding(Theme.Metric.panelPadding)

            BandHeader("On-device engine")
            VStack(alignment: .leading, spacing: Theme.Metric.s12) {
                HStack(spacing: Theme.Metric.s12) {
                    PanelToggle(title: "Use on-device engine", isOn: $state.useLocalEngine)
                }
                // the caller owns the mode word: the dot says whether the
                // engine answers, not which engine it is
                HStack(spacing: Theme.Metric.s6) {
                    LED(isOn: state.engineOK)
                    Text(state.useLocalEngine ? "on-device" : "remote")
                        .typeRole(.data).foregroundStyle(Theme.Ink.ink2)
                    Text(state.engineOK ? "reachable" : "unreachable")
                        .typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                }
                .accessibilityIdentifier("settings-engine-state")
                keyField(label: "OpenRouter API key",
                         draft: $apiKeyDraft, saved: $savedChatKey,
                         identifier: "openrouter-key",
                         baked: !LocalChat.bakedKey.isEmpty) { value in
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
                    LabeledField("Engine URL", text: $urlDraft, isMono: true,
                                 identifier: "engine-url")
                        .onChange(of: urlDraft) { _, value in
                            state.engineURLString = value.trimmingCharacters(in: .whitespaces)
                        }
                    PanelNote(text: "Run engine/.venv/bin/scor serve on your Mac, and use its hostname so the iPad can reach it over the local network.")
                }
                .padding(Theme.Metric.panelPadding)
            }

            BandHeader("PDF conversion (OMR)")
            VStack(alignment: .leading, spacing: Theme.Metric.s12) {
                LabeledField("OMR service URL", text: $omrURLDraft, isMono: true,
                             identifier: "omr-url")
                    .onChange(of: omrURLDraft) { _, value in
                        state.omrURLString = value.trimmingCharacters(in: .whitespaces)
                    }
                keyField(label: "OMR service API key",
                         draft: $omrKeyDraft, saved: $savedOMRKey,
                         identifier: "omr-key",
                         baked: !AppState.bakedOMRKey.isEmpty) { value in
                    KeychainStore.omrKey = value
                }
                HStack {
                    PanelButton(title: omrTestRunning ? "Testing…" : "Test connection & key") {
                        omrTestRunning = true
                        omrTestResult = ""
                        Task {
                            omrTestResult = await Self.testOMR(
                                urlString: omrURLDraft.trimmingCharacters(in: .whitespaces),
                                key: AppState.effectiveOMRKey)
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
            omrURLDraft = state.omrURLString
            // Key fields start empty and say what is in use underneath them.
            // Seeding them with the stored secret and writing back on every
            // keystroke is what let a stray edit clear a working key.
            savedChatKey = KeychainStore.openRouterKey
            savedOMRKey = KeychainStore.omrKey
            apiKeyDraft = ""
            omrKeyDraft = ""
        }
        .onDisappear { Task { await state.refresh() } }
    }

    /// A secret field: never pre-filled, saved on demand, and honest about
    /// which key the app is using right now.
    @ViewBuilder
    private func keyField(label: String, draft: Binding<String>, saved: Binding<String>,
                          identifier: String, baked: Bool,
                          store: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledField(label: label, text: draft, isMono: true,
                         identifier: identifier) {
                let typed = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !typed.isEmpty {
                    PanelButton(title: "Save", kind: .primary) {
                        store(typed)
                        saved.wrappedValue = typed
                        draft.wrappedValue = ""
                    }
                    .accessibilityIdentifier("save-\(identifier)")
                } else if !saved.wrappedValue.isEmpty {
                    PanelButton(title: "Clear") {
                        store("")
                        saved.wrappedValue = ""
                    }
                    .accessibilityIdentifier("clear-\(identifier)")
                }
            }
            PanelNote(text: keyStatus(saved: saved.wrappedValue, baked: baked))
        }
    }

    private func keyStatus(saved: String, baked: Bool) -> String {
        if !saved.isEmpty {
            return "Using your saved key (\(String(saved.suffix(4))) …last four). "
                + "Type a new one to replace it, or Clear to fall back to the built-in key."
        }
        return baked ? "Using the key built into this build. Type one above to override it."
                     : "No key: this build has none built in, so paste one above."
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
