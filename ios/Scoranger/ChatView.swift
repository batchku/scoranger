import SwiftUI

struct ChatView: View {
    @EnvironmentObject var state: AppState
    @State private var draft = ""
    @FocusState private var inputFocused: Bool
    @StateObject private var dictation = SpeechDictation()
    /// Draft text at the moment dictation started; recognized speech appends to it.
    @State private var dictationBase = ""

    private var slug: String? { state.selectedScore?.slug }
    private var messages: [ChatDisplayMessage] {
        slug.flatMap { state.chatMessages[$0] } ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if messages.isEmpty {
                            Text("Ask for an arrangement — “drop the piano”, “transpose down a minor third”, “give the cello line to a viola”…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                        ForEach(messages) { msg in
                            bubble(msg)
                                .id(msg.id)
                        }
                        if state.chatBusy {
                            liveProgressCard
                                .id("live-progress")
                        }
                    }
                    .padding(.vertical, 10)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onChange(of: liveSteps.count) {
                    proxy.scrollTo("live-progress", anchor: .bottom)
                }
            }
            Divider()
            inputBar
        }
        .background(.background)
    }

    private var header: some View {
        HStack {
            Text("Chat").font(.headline)
            Spacer()
            if let catalog = state.modelCatalog {
                Picker("Model", selection: $state.chatModel) {
                    ForEach(catalog.models.keys.sorted(), id: \.self) { alias in
                        Text(alias).tag(alias)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var liveSteps: [ChatStep] {
        slug.flatMap { state.activeChatSteps[$0] } ?? []
    }

    /// The growing checklist shown while the agent works: every operation
    /// appended as a row, checked off as it completes, spinner on the tail.
    private var liveProgressCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(liveSteps) { step in
                stepRow(step)
            }
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(liveSteps.isEmpty ? "planning…" : "thinking…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private func stepRow(_ step: ChatStep) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                .font(.footnote)
                .foregroundStyle(step.done ? Color.green : Color.secondary)
            Text(step.title)
                .font(.footnote)
            if let detail = step.detail {
                Text(detail)
                    .font(.footnote.monospaced())
                    .foregroundStyle(detail.hasPrefix("⚠") ? Color.orange : Color.secondary)
            }
        }
    }

    @ViewBuilder
    private func bubble(_ msg: ChatDisplayMessage) -> some View {
        HStack {
            if msg.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 8) {
                if let steps = msg.steps {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(steps) { step in
                            stepRow(step)
                        }
                    }
                    Divider()
                }
                Text(msg.text)
                    .font(.callout)
                    .textSelection(.enabled)
            }
            .padding(10)
            .background(background(for: msg.role))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            if msg.role != .user { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 10)
    }

    private func background(for role: ChatDisplayMessage.Role) -> Color {
        switch role {
        case .user: return Color.accentColor.opacity(0.18)
        case .agent: return Color(.secondarySystemBackground)
        case .error: return Color.red.opacity(0.15)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(dictation.errorText ?? "Arrange…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .onSubmit(send)
                .onChange(of: dictation.transcript) {
                    guard !dictation.transcript.isEmpty else { return }
                    let sep = dictationBase.isEmpty || dictationBase.hasSuffix(" ") ? "" : " "
                    draft = dictationBase + sep + dictation.transcript
                }
            Button {
                if dictation.isRecording {
                    dictation.stop()
                } else {
                    dictationBase = draft
                    dictation.start()
                }
            } label: {
                Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                    .font(.title2)
                    .foregroundStyle(dictation.isRecording ? Color.red : Color.accentColor)
                    .symbolEffect(.pulse, isActive: dictation.isRecording)
            }
            .accessibilityLabel(dictation.isRecording ? "Stop dictation" : "Start dictation")
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(state.chatBusy || draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(10)
    }

    private func send() {
        if dictation.isRecording { dictation.stop() }
        let text = draft
        draft = ""
        state.sendChat(text)
    }
}
