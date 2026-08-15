import Foundation

/// On-device arrangement agent: an OpenAI-style tool loop over OpenRouter,
/// dispatching tool calls into the embedded Python engine. Mirrors
/// engine/scoranger_engine/chat.py (same instructions, same 21 tools).
struct LocalChat {

    /// Friendly alias -> OpenRouter model slug (mirror of chat.py MODELS,
    /// OpenRouter routes only — the iPad always goes through the gateway).
    static let models: [String: String] = [
        "gemini-flash": "google/gemini-3.7-flash",
        "kimi": "moonshotai/kimi-k3:exacto",
        "qwen": "qwen/qwen3.8-max",
        "claude": "anthropic/claude-sonnet-5",
        "claude-opus": "anthropic/claude-opus-5",
        "deepseek": "deepseek/deepseek-v4-flash",
    ]
    static let defaultModel = "gemini-flash"

    static let instructions = """
    You are Scoranger's arrangement agent. You manipulate a musical score ONLY \
    through the provided tools — deterministic operations that each create a new \
    immutable version. Never describe notation edits you cannot perform with a tool.

    Working rules:
    1. Orient first: call get_score_info before planning changes.
    2. State your plan briefly, then execute it with tool calls.
    3. Verify after: read each tool result; after change_instrument, relay the \
    octave-shift and out-of-range report to the user.
    4. If a tool returns an error, read it — bad part names include the real part \
    list. Correct and retry.
    5. Musical judgment is yours: sensible clefs, octaves, keys. Flag questionable \
    requests instead of silently producing garbage.
    Answer concisely; the user sees the score update live.
    """

    enum ChatError: Error, LocalizedError {
        case missingKey
        case http(Int, String)
        case badResponse(String)
        var errorDescription: String? {
            switch self {
            case .missingKey: return "No OpenRouter API key — add one in Settings."
            case .http(let code, let body): return "OpenRouter HTTP \(code): \(body.prefix(300))"
            case .badResponse(let why): return "Unexpected OpenRouter response: \(why)"
            }
        }
    }

    let engine = LocalEngine()

    // MARK: tool definitions (OpenAI function-calling schema)

    private struct ToolSpec {
        let name: String
        let description: String
        let parameters: [String: Any]
        /// bridge op + arg-name remapping (tool arg -> bridge arg)
        let op: String
        let rename: [String: String]
    }

    private static func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }
    private static func int(_ d: String) -> [String: Any] { ["type": "integer", "description": d] }
    private static func bool(_ d: String) -> [String: Any] { ["type": "boolean", "description": d] }
    private static func strArr(_ d: String) -> [String: Any] {
        ["type": "array", "items": ["type": "string"], "description": d]
    }
    private static func params(_ props: [String: Any], required: [String]) -> [String: Any] {
        ["type": "object", "properties": props, "required": required]
    }

    private static let tools: [ToolSpec] = [
        ToolSpec(name: "get_score_info",
                 description: "Parts, instruments, clefs, ranges, measure counts, key and time signatures of the current score.",
                 parameters: params([:], required: []), op: "info", rename: [:]),
        ToolSpec(name: "list_versions",
                 description: "The score's version history (op + args per version) and its sources (other editions of the piece).",
                 parameters: params([:], required: []), op: "versions", rename: [:]),
        ToolSpec(name: "keep_parts",
                 description: "Keep only the named parts; remove all others. Part names match case-insensitively; '#N' targets by index.",
                 parameters: params(["parts": strArr("part names to keep")], required: ["parts"]),
                 op: "keep-parts", rename: [:]),
        ToolSpec(name: "remove_parts",
                 description: "Remove the named parts from the score.",
                 parameters: params(["parts": strArr("part names to remove")], required: ["parts"]),
                 op: "remove-parts", rename: [:]),
        ToolSpec(name: "transpose",
                 description: "Transpose the whole score (or given parts) by a named interval ('M2', 'm-3', 'P8') or semitone count ('-3').",
                 parameters: params(["interval": str("interval or semitone count"),
                                     "parts": strArr("optional part names; omit for all")],
                                    required: ["interval"]),
                 op: "transpose", rename: [:]),
        ToolSpec(name: "change_clef",
                 description: "Set a part's clef (treble, bass, alto, tenor, treble8vb, bass8vb) from a given measure.",
                 parameters: params(["part": str("part name"), "clef": str("clef name"),
                                     "from_measure": int("first measure (default 1)")],
                                    required: ["part", "clef"]),
                 op: "change-clef", rename: [:]),
        ToolSpec(name: "change_instrument",
                 description: "Reassign a part to another instrument: converts transposition, octave-fits the line to the instrument's range, sets the idiomatic clef, and reports remaining out-of-range notes.",
                 parameters: params(["part": str("part name"), "to_instrument": str("target instrument")],
                                    required: ["part", "to_instrument"]),
                 op: "change-instrument", rename: ["to_instrument": "to"]),
        ToolSpec(name: "rename_part",
                 description: "Rename a part (label only, no musical change).",
                 parameters: params(["part": str("current part name or '#N'"), "name": str("new name"),
                                     "abbreviation": str("optional staff abbreviation")],
                                    required: ["part", "name"]),
                 op: "rename-part", rename: [:]),
        ToolSpec(name: "check_range",
                 description: "List notes outside an instrument's range (the part's own instrument, or the named one). Read-only.",
                 parameters: params(["part": str("part name"),
                                     "instrument": str("optional instrument to check against")],
                                    required: ["part"]),
                 op: "check-range", rename: [:]),
        ToolSpec(name: "octave_shift",
                 description: "Shift a part by whole octaves within an inclusive measure range.",
                 parameters: params(["part": str("part name"), "octaves": int("e.g. -1"),
                                     "from_measure": int("first measure"), "to_measure": int("last measure")],
                                    required: ["part", "octaves", "from_measure", "to_measure"]),
                 op: "octave-shift", rename: [:]),
        ToolSpec(name: "merge_parts",
                 description: "Merge several parts losslessly into one staff (each source becomes a voice).",
                 parameters: params(["parts": strArr("parts to merge, top voice first"),
                                     "new_name": str("name of the merged part"),
                                     "clef": str("clef for the merged staff (default treble)")],
                                    required: ["parts", "new_name"]),
                 op: "merge-parts", rename: ["new_name": "name"]),
        ToolSpec(name: "split_bass",
                 description: "Split a part into a bass staff (lowest pitch per moment, bass clef) and a chords staff (the rest, treble).",
                 parameters: params(["part": str("part to split"), "bass_name": str("name for the bass staff"),
                                     "chords_name": str("name for the chords staff"),
                                     "instrument": str("optional instrument for both staves")],
                                    required: ["part", "bass_name", "chords_name"]),
                 op: "split-bass", rename: [:]),
        ToolSpec(name: "absorb_part",
                 description: "Fold a chordal part into a melodic part as a second voice under the melody. Optional rules override: below_melody(bool), drop_doubling(bool), min_pitch(str), max_span(int).",
                 parameters: params(["source": str("part to absorb"), "target": str("melodic part"),
                                     "rules": ["type": "object", "description": "optional rule overrides"]],
                                    required: ["source", "target"]),
                 op: "absorb-part", rename: [:]),
        ToolSpec(name: "flatten_voices",
                 description: "Collapse a multi-voice staff into one voice of chords (piano right-hand style).",
                 parameters: params(["part": str("part name")], required: ["part"]),
                 op: "flatten-voices", rename: [:]),
        ToolSpec(name: "consolidate_ties",
                 description: "Merge runs of tied same-pitch notes into single longer notes (notational cleanup).",
                 parameters: params(["parts": strArr("part names")], required: ["parts"]),
                 op: "consolidate-ties", rename: [:]),
        ToolSpec(name: "limit_part",
                 description: "Enforce playability limits on a part, always dropping higher notes: a pitch ceiling and/or monophony.",
                 parameters: params(["part": str("part name"), "max_pitch": str("e.g. 'C4'"),
                                     "monophonic": bool("keep only the lowest note per moment")],
                                    required: ["part"]),
                 op: "limit-part", rename: [:]),
        ToolSpec(name: "simplify_repeats",
                 description: "Collapse measures that only restate one pitch class (octave jumps/repeats) to a downbeat note + rests.",
                 parameters: params(["part": str("part name")], required: ["part"]),
                 op: "simplify-repeats", rename: [:]),
        ToolSpec(name: "analyze_harmony",
                 description: "Per-measure harmony analysis: ranked chord candidates per bar with the downbeat bass note. Read-only; you adjudicate the final chart (prefer functional readings, name secondary dominants literally).",
                 parameters: params(["parts": strArr("optional parts to analyze")], required: []),
                 op: "analyze", rename: [:]),
        ToolSpec(name: "set_chords",
                 description: "Write chord symbols onto a part: [{\"measure\": 1, \"symbol\": \"Fm\"}, ...]. Qualities: '', m, 7, m7, maj7, m7b5, 6, m6, dim, dim7, aug; roots may carry b/#.",
                 parameters: params(["part": str("part to carry the symbols"),
                                     "chords": ["type": "array", "description": "list of {measure, symbol}",
                                                "items": ["type": "object",
                                                          "properties": ["measure": ["type": "integer"],
                                                                         "symbol": ["type": "string"]],
                                                          "required": ["measure", "symbol"]]]],
                                    required: ["part", "chords"]),
                 op: "set-chords", rename: [:]),
        ToolSpec(name: "chart_style",
                 description: "Real Book styling for a chord-symbol staff: hide rests, put the names on the staff.",
                 parameters: params(["part": str("part name")], required: ["part"]),
                 op: "chart-style", rename: [:]),
        ToolSpec(name: "pull_part",
                 description: "Bring a part (or 'A-B' measure range, requires replace) from a source ('src:s01') or a historical version ('v007') into the arrangement.",
                 parameters: params(["from_ref": str("'src:sNN' or 'vNNN'"), "part": str("part in the source"),
                                     "as_name": str("optional name for the added part"),
                                     "replace": str("optional part in the arrangement to replace"),
                                     "measures": str("optional 'A-B' inclusive range")],
                                    required: ["from_ref", "part"]),
                 op: "pull-part", rename: ["from_ref": "from", "as_name": "as"]),
    ]

    private static var toolsJSON: [[String: Any]] {
        tools.map { t in
            ["type": "function",
             "function": ["name": t.name, "description": t.description, "parameters": t.parameters]]
        }
    }

    // MARK: the loop

    struct Turn {
        var reply: String
        var historyJSON: String
    }

    /// One chat turn against the on-device engine. `historyJSON` is the JSON
    /// message array from the previous Turn (OpenAI wire format).
    func run(slug: String, message: String, modelAlias: String?,
             historyJSON: String?, apiKey: String) async throws -> Turn {
        let model = Self.models[modelAlias ?? Self.defaultModel]
            ?? modelAlias ?? Self.models[Self.defaultModel]!

        var messages: [[String: Any]]
        if let historyJSON, let data = historyJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            messages = parsed
        } else {
            messages = [["role": "system", "content": Self.instructions]]
        }
        messages.append(["role": "user", "content": message])

        var finalReply = ""
        for _ in 0..<20 {
            let assistant = try await complete(model: model, messages: messages)
            messages.append(assistant)
            guard let calls = assistant["tool_calls"] as? [[String: Any]], !calls.isEmpty else {
                finalReply = assistant["content"] as? String ?? ""
                break
            }
            for call in calls {
                let id = call["id"] as? String ?? UUID().uuidString
                let fn = call["function"] as? [String: Any]
                let name = fn?["name"] as? String ?? ""
                let argsRaw = fn?["arguments"] as? String ?? "{}"
                let resultText = await dispatch(slug: slug, name: name, argsJSON: argsRaw)
                messages.append(["role": "tool", "tool_call_id": id, "content": resultText])
            }
        }

        let historyData = try JSONSerialization.data(withJSONObject: messages)
        return Turn(reply: finalReply.isEmpty ? "(no reply)" : finalReply,
                    historyJSON: String(data: historyData, encoding: .utf8) ?? "")
    }

    private func dispatch(slug: String, name: String, argsJSON: String) async -> String {
        guard let spec = Self.tools.first(where: { $0.name == name }) else {
            return #"{"ok": false, "error": "unknown tool \#(name)"}"#
        }
        var args: [String: Any] =
            (try? JSONSerialization.jsonObject(with: Data(argsJSON.utf8)) as? [String: Any]) ?? [:]
        for (from, to) in spec.rename {
            if let v = args.removeValue(forKey: from) { args[to] = v }
        }
        args["score"] = slug
        do {
            let result = try await engine.call(op: spec.op, args: args)
            let data = try JSONSerialization.data(withJSONObject: ["ok": true, "result": result])
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            // errors go back to the model as data so it can self-correct
            let data = (try? JSONSerialization.data(
                withJSONObject: ["ok": false, "error": "\(error.localizedDescription)"])) ?? Data("{}".utf8)
            return String(data: data, encoding: .utf8) ?? "{}"
        }
    }

    private func complete(model: String, messages: [[String: Any]]) async throws -> [String: Any] {
        let key = KeychainStore.openRouterKey
        guard !key.isEmpty else { throw ChatError.missingKey }

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://github.com/batchku/scoranger", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Scoranger", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "messages": messages, "tools": Self.toolsJSON,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw ChatError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              var assistant = choices.first?["message"] as? [String: Any] else {
            throw ChatError.badResponse(String(data: data, encoding: .utf8)?.prefix(300).description ?? "")
        }
        // normalize: some providers send content: null with tool_calls
        if assistant["content"] is NSNull { assistant["content"] = "" }
        return assistant
    }
}

/// Minimal Keychain wrapper for API keys.
enum KeychainStore {
    private static let service = "com.irllabs.scoranger"

    static var openRouterKey: String {
        get { read("openrouter-api-key") }
        set { write("openrouter-api-key", newValue) }
    }

    static var omrKey: String {
        get { read("omr-api-key") }
        set { write("omr-api-key", newValue) }
    }

    private static func read(_ account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func write(_ account: String, _ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
