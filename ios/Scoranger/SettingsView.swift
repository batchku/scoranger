import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var urlDraft = ""

    var body: some View {
        NavigationStack {
            Form {
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
