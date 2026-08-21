import SwiftUI

/// The chat overlay's body. Its subject line and model alias live in the
/// overlay header (§8 screen 03), so this is the transcript and the input only.
struct ChatView: View {
    @EnvironmentObject var state: AppState
    @State private var draft = ""
    @FocusState private var inputFocused: Bool
    @StateObject private var dictation = SpeechDictation()
    /// Draft text at the moment dictation started; recognized speech appends to it.
    @State private var dictationBase = ""

    private var slug: String? { state.selectedScore?.slug }
    /// How many arrangements the open one shares its piece with (1 = it's alone,
    /// so there is nothing to refer to by number).
    private var siblingCount: Int {
        slug.flatMap { state.placement(of: $0)?.piece.arrangements.count } ?? 0
    }
    private var messages: [ChatDisplayMessage] {
        slug.flatMap { state.chatMessages[$0] } ?? []
    }
    private var liveSteps: [ChatStep] {
        slug.flatMap { state.activeChatSteps[$0] } ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Metric.s12) {
                        if messages.isEmpty { primer }
                        ForEach(messages) { msg in
                            bubble(msg).id(msg.id)
                        }
                        if state.chatBusy {
                            opCard.id("live-progress")
                        }
                    }
                    .padding(.vertical, Theme.Metric.s12)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onChange(of: liveSteps.count) {
                    proxy.scrollTo("live-progress", anchor: .bottom)
                }
            }
            inputBar
        }
        .background(Theme.Surface.panel)
    }

    private var primer: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.s8) {
            Text("Ask for an arrangement — “drop the piano”, “transpose down a minor third”, “give the cello line to a viola”…")
            if siblingCount > 1 {
                Text("Refer to the other arrangements of this piece by number: “take the violin part from #2”.")
            }
        }
        .typeRole(.body)
        .foregroundStyle(Theme.Ink.ink2)
        .padding(.horizontal, Theme.Metric.panelPadding)
    }

    // MARK: - Bubbles (§7.7)

    /// A bordered card with a caps author label above the text: cheaper than
    /// tails, and it survives having no colour to spare.
    @ViewBuilder
    private func bubble(_ msg: ChatDisplayMessage) -> some View {
        HStack {
            if msg.role == .user { Spacer(minLength: Theme.Metric.s32) }
            VStack(alignment: .leading, spacing: Theme.Metric.s6) {
                Text(authorLabel(msg.role))
                    .typeRole(.label)
                    .foregroundStyle(msg.role == .error ? Theme.Status.danger
                                                        : Theme.Accent.clayStrong)
                if let steps = msg.steps, !steps.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Metric.s4) {
                        ForEach(steps) { step in stepRow(step) }
                    }
                    Rectangle().fill(Theme.Line.line).frame(height: 1)
                }
                Text(msg.text)
                    .typeRole(.body)
                    .foregroundStyle(Theme.Ink.ink)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 11)
            .background(fill(for: msg.role))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metric.rPanel)
                    .stroke(border(for: msg.role), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rPanel))
            .frame(maxWidth: 300, alignment: msg.role == .user ? .trailing : .leading)
            if msg.role != .user { Spacer(minLength: Theme.Metric.s32) }
        }
        .padding(.horizontal, Theme.Metric.panelPadding)
    }

    private func authorLabel(_ role: ChatDisplayMessage.Role) -> String {
        switch role {
        case .user:  return "You"
        case .agent: return "Agent"
        case .error: return "Failed"
        }
    }

    private func fill(for role: ChatDisplayMessage.Role) -> Color {
        switch role {
        case .user:  return Theme.Accent.clayTint
        case .agent: return Theme.Surface.panel
        case .error: return Theme.Status.errorFill
        }
    }

    private func border(for role: ChatDisplayMessage.Role) -> Color {
        switch role {
        case .user:  return Theme.Accent.clayBorder
        case .agent: return Theme.Line.line2
        case .error: return Theme.Status.errorBorder
        }
    }

    // MARK: - Op card (§7.8)

    /// The live checklist: a band header stating the count, one row per op, and
    /// a spinner tail. Keeps its final state in the transcript when the turn ends.
    private var opCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            BandHeader("Working · \(liveSteps.count) op\(liveSteps.count == 1 ? "" : "s")")
            VStack(alignment: .leading, spacing: Theme.Metric.s4) {
                ForEach(liveSteps) { step in stepRow(step) }
                HStack(spacing: Theme.Metric.s8) {
                    ProgressView().controlSize(.small).tint(Theme.Accent.clay)
                    Text(liveSteps.isEmpty ? "planning…" : "thinking…")
                        .typeRole(.meta)
                        .foregroundStyle(Theme.Ink.ink3)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metric.rPanel)
                .stroke(Theme.Line.line2, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rPanel))
        .padding(.horizontal, Theme.Metric.panelPadding)
    }

    /// Status glyph, the op in prose, its arguments in mono.
    @ViewBuilder
    private func stepRow(_ step: ChatStep) -> some View {
        let failed = step.detail?.hasPrefix("⚠") ?? false
        HStack(alignment: .firstTextBaseline, spacing: Theme.Metric.s6) {
            Image(systemName: step.done ? (failed ? "exclamationmark.triangle" : "checkmark")
                                        : "circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(step.done ? (failed ? Theme.Status.warn : Theme.Status.ok)
                                           : Theme.Ink.ink3)
                .frame(width: 13)
            Text(step.title)
                .typeRole(.meta)
                .foregroundStyle(Theme.Ink.ink)
            if let detail = step.detail {
                Text(detail)
                    .typeRole(.data)
                    .foregroundStyle(failed ? Theme.Status.warn : Theme.Ink.ink2)
            }
        }
    }

    // MARK: - Input (§7.13)

    private var inputBar: some View {
        HStack(spacing: Theme.Metric.s8) {
            TextField(dictation.errorText ?? "Arrange…", text: $draft, axis: .vertical)
                .typeRole(.body)
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit(send)
                .padding(.vertical, 9)
                .padding(.horizontal, 10)
                .background(Theme.Surface.paper)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(inputFocused ? Theme.Accent.clay : Theme.Line.line2,
                                lineWidth: 1)
                }
                .onChange(of: dictation.transcript) {
                    guard !dictation.transcript.isEmpty else { return }
                    let sep = dictationBase.isEmpty || dictationBase.hasSuffix(" ") ? "" : " "
                    draft = dictationBase + sep + dictation.transcript
                }

            PanelIconButton(systemName: dictation.isRecording ? "mic.fill" : "mic",
                            label: dictation.isRecording ? "Stop dictation" : "Start dictation",
                            tint: dictation.isRecording ? Theme.Status.danger : Theme.Ink.ink2) {
                if dictation.isRecording {
                    dictation.stop()
                } else {
                    dictationBase = draft
                    dictation.start()
                }
            }

            PanelButton(title: "Send", kind: .primary, action: send)
                .disabled(state.chatBusy || draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(Theme.Metric.s12)
        .background(Theme.Surface.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Line.line2).frame(height: 1)
        }
    }

    private func send() {
        if dictation.isRecording { dictation.stop() }
        let text = draft
        draft = ""
        state.sendChat(text)
    }
}
