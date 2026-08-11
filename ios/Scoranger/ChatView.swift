import SwiftUI

struct ChatView: View {
    @EnvironmentObject var state: AppState
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

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
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("arranging…").font(.footnote).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 10)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
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

    @ViewBuilder
    private func bubble(_ msg: ChatDisplayMessage) -> some View {
        HStack {
            if msg.role == .user { Spacer(minLength: 40) }
            Text(msg.text)
                .font(.callout)
                .textSelection(.enabled)
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
            TextField("Arrange…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(state.chatBusy || draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(10)
    }

    private func send() {
        let text = draft
        draft = ""
        state.sendChat(text)
    }
}
