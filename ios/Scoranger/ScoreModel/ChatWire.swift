import Foundation

/// What came back from the model provider, and what to do about it.
///
/// Ali's arrange chat failed with this on screen:
///
///     Unexpected OpenRouter response: {"error":{"message":"Corrupted thought
///     signature.","code":400}}
///
/// Two separate faults in one line. The second is that a provider's JSON
/// reached a reader at all -- that message is the app saying "I did not
/// recognise this", printed with the evidence, which is a log line and not
/// something to show anybody.
///
/// The first is the actual failure, and it is about REASONING STATE. Gemini
/// returns its private chain of thought alongside each tool call, encrypted and
/// signed, as `reasoning_details` on the assistant message:
///
///     {"type": "reasoning.encrypted", "format": "google-gemini-v1",
///      "data": "AY89a1/7lpVIIErGpyaFiBJ...", "id": "call_1802374"}
///
/// The loop appends every assistant message to the history verbatim and sends
/// the history back, so those blobs go out again on the next request. When one
/// does not validate, Gemini answers "Corrupted thought signature." and the
/// whole turn dies -- with the arrangement possibly half-applied, since the
/// tools that already ran already made versions.
///
/// A blob damaged in transit reproduces it exactly (truncate the base64 and the
/// provider says those three words), and the app never truncates anything, so
/// the damage is upstream: OpenRouter routes one model name to more than one
/// provider, and a signature minted by Google AI Studio is meaningless to
/// Vertex. That is not fixable here, which decides the shape of the fix --
/// recover rather than prevent:
///
///   - a signature is worth keeping only inside the turn that minted it, where
///     the model is continuing its own chain of thought. Across a turn boundary
///     it is dead weight that can only fail, so history loaded from a previous
///     turn is stripped of them. Proven against the live provider: a
///     conversation with every signature removed completes normally, tool calls
///     and all.
///   - a request that fails on one anyway is retried ONCE with every signature
///     stripped, which is the same recovery applied a message too late.
///
/// And whatever the fault turns out to be, the reader is told in a sentence.
enum ChatWire {

    /// A provider's refusal, read out of whatever envelope it arrived in.
    struct Fault: Equatable {
        enum Kind: Equatable {
            /// The reasoning state carried over from an earlier message was
            /// rejected. Recoverable by dropping it.
            case staleReasoning
            /// Rate limited, out of credit, or the model is at capacity.
            case busy
            case credentials
            case other
        }

        let kind: Kind
        /// The provider's own sentence. Never JSON -- see `readable`.
        let providerMessage: String
        let status: Int

        /// Worth sending again, either automatically or by the reader.
        var isRetryable: Bool { kind == .staleReasoning || kind == .busy }

        /// What the reader sees. One sentence, no JSON, and it says what to do.
        var readable: String {
            switch kind {
            case .staleReasoning:
                return "The model provider rejected the reasoning it carried over "
                    + "from the previous message. That state is cleared now — send "
                    + "the same request again. Check the version list first: any "
                    + "operation that already ran was saved."
            case .busy:
                return "The model is busy or out of capacity right now"
                    + (providerMessage.isEmpty ? "." : ": \(providerMessage).")
                    + " Try again in a moment."
            case .credentials:
                return "The model provider rejected the API key. Add a working "
                    + "OpenRouter key in Settings."
            case .other:
                return providerMessage.isEmpty
                    ? "The model provider refused that request (HTTP \(status)), "
                        + "without saying why."
                    : "The model provider refused that request: \(providerMessage)"
            }
        }
    }

    /// The fault in a response body, or nil if there is none.
    ///
    /// Read for ANY status, because a 200 is not proof of success: Ali's failure
    /// came back as HTTP 200 with an error object and no `choices`, which is why
    /// the app fell through to its "unexpected response" branch and printed the
    /// body. The same failure also arrives as a 400 with the provider's real
    /// words buried two envelopes down, in `error.metadata.raw`.
    static func fault(in body: Data, status: Int) -> Fault? {
        let top = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        guard let error = errorObject(in: top) else {
            // No error object. A 200 carrying choices is the success case and
            // the only one; a 200 carrying neither is unusable, and saying so
            // plainly beats printing the body at somebody.
            if status == 200, top?["choices"] != nil { return nil }
            return Fault(kind: kind(of: "", status: status), providerMessage: "", status: status)
        }
        let message = deepestMessage(error) ?? ""
        return Fault(kind: kind(of: message, status: status),
                     providerMessage: presentable(message), status: status)
    }

    /// The `error` value, whether it is an object or a bare string.
    private static func errorObject(in top: [String: Any]?) -> Any? {
        guard let raw = top?["error"] else { return nil }
        if raw is NSNull { return nil }
        if let dictionary = raw as? [String: Any], dictionary.isEmpty { return nil }
        return raw
    }

    /// The most specific human sentence in the envelope.
    ///
    /// OpenRouter wraps an upstream refusal as "Provider returned error" and
    /// keeps the real message in `metadata.raw` -- as a STRING of JSON, which
    /// has to be parsed again. Ali's arrived unwrapped, so both shapes matter.
    private static func deepestMessage(_ error: Any?) -> String? {
        if let text = error as? String { return text }
        guard let error = error as? [String: Any] else { return nil }
        let outer = error["message"] as? String
        if let metadata = error["metadata"] as? [String: Any] {
            if let raw = metadata["raw"] as? String,
               let data = raw.data(using: .utf8),
               let nested = try? JSONSerialization.jsonObject(with: data),
               let inner = deepestMessage(errorObject(in: nested as? [String: Any])
                                            ?? (nested as? [String: Any])?["message"]),
               !inner.isEmpty {
                return inner
            }
            if let raw = metadata["raw"] as? String, !looksLikeJSON(raw) { return raw }
        }
        return outer
    }

    private static func looksLikeJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    /// A message fit to put in front of somebody: never JSON, never a wall.
    private static func presentable(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !looksLikeJSON(trimmed) else { return "" }
        let sentence = trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
        return sentence.count > 200 ? String(sentence.prefix(200)) + "…" : sentence
    }

    private static func kind(of message: String, status: Int) -> Fault.Kind {
        let text = message.lowercased()
        if text.contains("thought signature") || text.contains("thought_signature")
            || (text.contains("signature") && (text.contains("corrupt") || text.contains("invalid"))) {
            return .staleReasoning
        }
        if status == 401 || status == 403 || text.contains("api key")
            || text.contains("unauthorized") || text.contains("no auth credentials") {
            return .credentials
        }
        if status == 429 || status == 502 || status == 503 || status == 529
            || text.contains("rate limit") || text.contains("rate-limit")
            || text.contains("overloaded") || text.contains("quota")
            || text.contains("temporarily") || text.contains("capacity")
            || text.contains("insufficient credits") {
            return .busy
        }
        return .other
    }

    // MARK: reasoning state

    /// The same conversation with every reasoning blob removed.
    ///
    /// Only assistant messages carry them, and only `reasoning` and
    /// `reasoning_details`: the tool calls, their ids and the text all stay, so
    /// the model still sees exactly what it did and said. What it loses is its
    /// private chain of thought from a turn that is already over.
    static func withoutReasoning(_ messages: [[String: Any]]) -> [[String: Any]] {
        messages.map { message in
            guard message["role"] as? String == "assistant" else { return message }
            var stripped = message
            stripped.removeValue(forKey: "reasoning")
            stripped.removeValue(forKey: "reasoning_details")
            return stripped
        }
    }

    /// Whether a conversation is carrying any reasoning state at all -- what a
    /// retry has to check before deciding a strip-and-retry is worth an attempt.
    static func carriesReasoning(_ messages: [[String: Any]]) -> Bool {
        messages.contains { message in
            message["reasoning_details"] != nil && !(message["reasoning_details"] is NSNull)
                || (message["reasoning"] != nil && !(message["reasoning"] is NSNull))
        }
    }
}
