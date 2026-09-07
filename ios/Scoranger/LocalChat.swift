import Foundation

/// On-device arrangement agent: an OpenAI-style tool loop over OpenRouter,
/// dispatching tool calls into the embedded Python engine. Mirrors
/// engine/scoranger_engine/chat.py (same instructions, same 21 tools).
struct LocalChat {

    /// Friendly alias -> OpenRouter model slug (mirror of chat.py MODELS,
    /// OpenRouter routes only — the iPad always goes through the gateway).
    static let models: [String: String] = [
        "gemini-flash": "google/gemini-3.7-flash",
        "kimi": "moonshotai/kimi-k3",
        "qwen": "qwen/qwen3.8-max",
        "claude": "anthropic/claude-sonnet-5",
        "claude-opus": "anthropic/claude-opus-5",
        "deepseek": "deepseek/deepseek-v4-flash",
    ]
    static let defaultModel = "gemini-flash"

    /// Build-time default key (postBuild "Bake OpenRouter key" bakes it from
    /// the repo's gitignored .env); empty when the build had no .env.
    static let bakedKey: String =
        (Bundle.main.url(forResource: "openrouter-default-key", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

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
    6. A PIECE is the composition; an ARRANGEMENT is one scoring of it; a VERSION \
    is one immutable step in an arrangement's history. You always operate on ONE \
    arrangement. When the user writes '#N' they mean arrangement number N of the \
    same piece, listed with its 'arr:<slug>' ref in the context: "take the violin \
    part from #3" means pull_part from that ref. '#N' never means a version or a \
    measure. If no numbered list is in context, say the arrangement isn't filed \
    under a piece yet rather than guessing.
    7. A HARMONY LINE stays in the key. "A third above", "a sixth below", \
    "harmonise it" are diatonic: use transpose_diatonic, which moves by scale \
    degrees and leaves the key signature alone. Plain `transpose` is chromatic \
    and changes key -- right for "put this in D", wrong for a harmony. Never \
    answer that scale-degree transposition within a key is unsupported; it is \
    transpose_diatonic.
    Answer concisely; the user sees the score update live.
    """

    enum ChatError: Error, LocalizedError {
        case missingKey
        case http(Int, String)
        case badResponse(String)
        case network(URLError)
        var errorDescription: String? {
            switch self {
            case .missingKey: return "No OpenRouter API key — none baked into this build; add one in Settings."
            case .http(let code, let body): return "OpenRouter HTTP \(code): \(body.prefix(300))"
            case .badResponse(let why): return "Unexpected OpenRouter response: \(why)"
            case .network(let error):
                return "Couldn't reach OpenRouter: \(error.localizedDescription) "
                    + "(tried 4 times on fresh connections). Check Wi-Fi, and any "
                    + "VPN or proxy that might be closing the connection."
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
    /// A fractional number — a point size or a nudge, which integers cannot say.
    private static func num(_ d: String) -> [String: Any] { ["type": "number", "description": d] }
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
                 description: "CHROMATIC transposition: shift by a fixed interval and CHANGE KEY. Use it when the music should end up in a DIFFERENT key — \"put this in D\", \"a whole step up so I can sing it\", \"transpose for B-flat clarinet\". Every pitch moves by the same interval and the key signature is rewritten to match. Do NOT use it for a harmony line: \"a third above\", \"a sixth below\", \"harmonise it\" mean the notes must stay IN THE CURRENT KEY, which this cannot do — use transpose_diatonic. `interval` is a named interval ('M2', 'm-3', 'P8') or a semitone count ('-3'). Set from_measure/to_measure (inclusive) for a measure range.",
                 parameters: params(["interval": str("interval or semitone count"),
                                     "parts": strArr("optional part names; omit for all"),
                                     "from_measure": int("optional first measure of the range (inclusive)"),
                                     "to_measure": int("optional last measure of the range (inclusive)")],
                                    required: ["interval"]),
                 op: "transpose", rename: [:]),
        ToolSpec(name: "transpose_diatonic",
                 description: "DIATONIC transposition: move by SCALE DEGREES and STAY IN THE KEY. This is the tool for a harmony line — \"down a sixth\", \"a third above the melody\", \"harmonise this in thirds\", \"a second violin part below\". The key signature does not change and no accidentals appear that were not there before; some of the sixths come out major and some minor, exactly as the key requires, which is what makes it a harmony rather than a modulation. `degrees` is the number a musician says, signed: -6 is down a sixth, 3 up a third, 8 up an octave; 'down a sixth' works too. A unison is 1 and there is no zeroth. It moves the notes of the parts you name — it does not add a staff, so to write the harmony as a NEW part, pull_part the melody from the current version first and run this on the copy. `key` is only needed when the staff carries no key signature (common in scans): the tool refuses rather than guessing, and says so. Relay any note the result reports as OUTSIDE the key.",
                 parameters: params(["degrees": str("signed scale steps: -6 is down a sixth, 3 up a third"),
                                     "parts": strArr("optional part names; omit for all"),
                                     "from_measure": int("optional first measure of the range (inclusive)"),
                                     "to_measure": int("optional last measure of the range (inclusive)"),
                                     "key": str("optional key to count degrees in, e.g. 'G', 'e', 'Bb' — only when the staff has no key signature")],
                                    required: ["degrees"]),
                 op: "transpose-diatonic", rename: [:]),
        ToolSpec(name: "transpose_diatonic_elements",
                 description: "Move ONLY the given elements by scale degrees, staying in the key. Use this — never transpose_diatonic with a measure range — whenever the user refers to a selection and the context lists selected element addresses. Pass them unchanged ('s1/m15/l1/note#3').",
                 parameters: params(["degrees": str("signed scale steps: -6 is down a sixth"),
                                     "elements": strArr("element addresses from the selection, unchanged"),
                                     "key": str("optional key, when the staff has no key signature")],
                                    required: ["degrees", "elements"]),
                 op: "transpose-diatonic-elements", rename: [:]),
        ToolSpec(name: "respell",
                 description: "Respell accidentals enharmonically: prefer='flats' turns G# into Ab (right for flat keys like F minor); prefer='sharps' does the reverse. Key signatures untouched. Set from_measure/to_measure (inclusive) to respell only that measure range.",
                 parameters: params(["prefer": str("'flats' or 'sharps' (default flats)"),
                                     "parts": strArr("optional part names; omit for all"),
                                     "from_measure": int("optional first measure of the range (inclusive)"),
                                     "to_measure": int("optional last measure of the range (inclusive)")],
                                    required: []),
                 op: "respell", rename: [:]),
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
                 description: "Bring a part (or 'A-B' measure range, requires replace) from a source ('src:s01'), a historical version ('v007'), or a sibling arrangement ('arr:<slug>') into the arrangement.",
                 parameters: params(["from_ref": str("'src:sNN', 'vNNN', or 'arr:<slug>' (another arrangement of the same piece — see the numbered list in context)"), "part": str("part in the source"),
                                     "as_name": str("optional name for the added part"),
                                     "replace": str("optional part in the arrangement to replace"),
                                     "measures": str("optional 'A-B' inclusive range")],
                                    required: ["from_ref", "part"]),
                 op: "pull-part", rename: ["from_ref": "from", "as_name": "as"]),
        ToolSpec(name: "set_structure",
                 description: "Add, remove or move a repeat sign, a volta (1st/2nd ending) or a navigation mark. Kinds: repeat-start, repeat-end, repeat-both, volta, segno, coda, fine, da-capo, da-capo-al-fine, da-capo-al-coda, dal-segno, dal-segno-al-fine, dal-segno-al-coda. A volta needs measure, to_measure and number; repeat-end can take times. remove=true takes one off; move_to shifts it.",
                 parameters: params(["kind": str("which mark"),
                                     "measure": int("the measure it goes on"),
                                     "to_measure": int("last measure of a volta"),
                                     "number": int("volta number"),
                                     "times": int("play count on a repeat-end"),
                                     "move_to": int("move the mark to this measure"),
                                     "remove": bool("remove it instead of adding")],
                                    required: ["kind"]),
                 op: "set-structure", rename: [:]),
        ToolSpec(name: "adjust_element",
                 description: "Change the size or position of an added element — chord symbols today. size is an absolute point size (12 is the default); offset_x and offset_y nudge it sideways and up in MusicXML tenths, positive y being up. Address one with measure (plus ordinal when a bar has several), or set all=true for every chord symbol in the part. reset=true puts them back.",
                 parameters: params(["part": str("the part the element is on"),
                                     "measure": int("the bar it is in"),
                                     "kind": str("what kind of element (harm)"),
                                     "ordinal": int("which one, when a bar has several"),
                                     "size": num("absolute point size"),
                                     "offset_x": num("sideways nudge, in tenths"),
                                     "offset_y": num("upward nudge, in tenths"),
                                     "all": bool("every element of that kind in the part"),
                                     "reset": bool("put it back where it was")],
                                    required: ["part"]),
                 op: "adjust-element", rename: [:]),
        ToolSpec(name: "guitar_tablature",
                 description: "Write guitar tablature under a part: a fret number per note on a six-line tab staff, at the lowest position that plays it. Notes the tuning cannot play are reported, and so is any bar where a chord forced the hand higher up the neck. Set clear=true to remove it. Size and position are adjust_element's business, with kind=\"tab\".",
                 parameters: params(["part": str("the part to write tab under"),
                                     "tuning": str("EADGBE (standard), DADGAD, or DADGBE (drop D)"),
                                     "capo": num("the fret the capo sits on"),
                                     "clear": bool("remove the tab instead")],
                                    required: ["part"]),
                 op: "guitar-tab", rename: [:]),
        ToolSpec(name: "guitar_chord_diagrams",
                 description: "Draw a guitar chord diagram above every chord symbol already on a part: the grid, the finger dots, a barre as one bar, the nut at first position and a \"5 fr.\" label above it. Chords with no playable shape are reported, not faked. Set clear=true to remove them. Size and position are adjust_element's business, with kind=\"diagram\".",
                 parameters: params(["part": str("the part whose chord symbols get diagrams"),
                                     "tuning": str("EADGBE (standard), DADGAD, or DADGBE (drop D)"),
                                     "clear": bool("remove the diagrams instead")],
                                    required: ["part"]),
                 op: "chord-diagrams", rename: [:]),
        ToolSpec(name: "penny_whistle_fingerings",
                 description: "Write penny-whistle fingerings under every note of a part, engraved in the notation as stacked hole diagrams (X covered, O open, / half-hole, + overblown octave). Notes the whistle cannot play are reported. Set clear=true to remove them.",
                 parameters: params(["part": str("the part to fingerings"),
                                     "whistle": str("the whistle's key, D by default"),
                                     "clear": bool("remove the fingerings instead")],
                                    required: ["part"]),
                 op: "whistle-fingerings", rename: [:]),
        ToolSpec(name: "set_metadata",
                 description: "Set the arrangement's title (the title engraved at the top of the page AND its name in the library — they are one value), its composer or its arranger. An empty string clears a credit.",
                 parameters: params(["title": str("the arrangement's title"),
                                     "composer": str("composer credit"),
                                     "arranger": str("arranger credit")],
                                    required: []),
                 op: "set-metadata", rename: [:]),
        ToolSpec(name: "assign_to_piece",
                 description: "File this arrangement under a piece, creating it if needed.",
                 parameters: params(["piece_name": str("name of the piece to file under")],
                                    required: ["piece_name"]),
                 op: "assign-piece", rename: ["piece_name": "piece"]),
    ]

    /// The tool list as the model receives it. Not private: a test reads it to
    /// assert the feature is actually OFFERED on device. An op can exist in the
    /// engine, in the bridge and in chat.py and still be unreachable from the
    /// iPad, which is how `transpose_diatonic` would have shipped as a CLI-only
    /// feature after Ali asked for it by name.
    static var toolsJSON: [[String: Any]] {
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

    /// Live progress events for the UI checklist.
    enum Event {
        case toolStarted(title: String)
        case toolFinished(detail: String?)   // e.g. "→ v005"
    }

    /// One chat turn against the on-device engine. `historyJSON` is the JSON
    /// message array from the previous Turn (OpenAI wire format).
    /// `context` is extra situational info (e.g. the score's piece and sibling
    /// arrangements) appended to the system message. `onEvent` streams
    /// checklist progress to the UI as tools run.
    func run(slug: String, message: String, modelAlias: String?,
             historyJSON: String?, context: String? = nil,
             onEvent: (@MainActor (Event) -> Void)? = nil) async throws -> Turn {
        let model = Self.models[modelAlias ?? Self.defaultModel]
            ?? modelAlias ?? Self.models[Self.defaultModel]!

        // Stamp every version this turn creates with a shared turn id so the
        // UI can group them under the prompt. Best-effort; closed on all exits.
        _ = try? await engine.call(op: "begin-turn", args: ["score": slug, "prompt": message])
        do {
            let turn = try await runLoop(slug: slug, message: message, model: model,
                                         historyJSON: historyJSON, context: context,
                                         onEvent: onEvent)
            _ = try? await engine.call(op: "end-turn", args: [:])
            return turn
        } catch {
            _ = try? await engine.call(op: "end-turn", args: [:])
            throw error
        }
    }

    /// The tool loop itself (wrapped by run() in begin-turn/end-turn stamping).
    private func runLoop(slug: String, message: String, model: String,
                         historyJSON: String?, context: String? = nil,
                         onEvent: (@MainActor (Event) -> Void)? = nil) async throws -> Turn {
        let system = Self.instructions + (context.map { "\n\n" + $0 } ?? "")
        var messages: [[String: Any]]
        if let historyJSON, let data = historyJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            messages = parsed
            // keep the system context current (siblings may have changed)
            if messages.first?["role"] as? String == "system" {
                messages[0]["content"] = system
            }
        } else {
            messages = [["role": "system", "content": system]]
        }
        messages.append(["role": "user", "content": message])

        var finalReply = ""
        var rounds = 0
        for _ in 0..<20 {
            rounds += 1
            let assistant = try await complete(model: model, messages: messages)
            messages.append(assistant)
            guard let calls = assistant["tool_calls"] as? [[String: Any]], !calls.isEmpty else {
                finalReply = (assistant["content"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
            print("SCORANGER-CHAT-LOOP round \(rounds): \(calls.count) tool call(s)")
            for call in calls {
                let id = call["id"] as? String ?? UUID().uuidString
                let fn = call["function"] as? [String: Any]
                let name = fn?["name"] as? String ?? ""
                let argsRaw = fn?["arguments"] as? String ?? "{}"
                if let onEvent {
                    let title = ChatSteps.stepTitle(name: name, argsJSON: argsRaw)
                    await MainActor.run { onEvent(.toolStarted(title: title)) }
                }
                let resultText = await dispatch(slug: slug, name: name, argsJSON: argsRaw)
                if let onEvent {
                    // surface the created version (or an error) on the step
                    let parsed = (try? JSONSerialization.jsonObject(
                        with: Data(resultText.utf8)) as? [String: Any]) ?? [:]
                    let detail: String?
                    if let result = parsed["result"] as? [String: Any],
                       let v = result["new_version"] as? String {
                        detail = "→ \(v)"
                    } else if parsed["ok"] as? Bool == false {
                        detail = "⚠︎ \((parsed["error"] as? String ?? "error").prefix(60))"
                    } else {
                        detail = nil
                    }
                    await MainActor.run { onEvent(.toolFinished(detail: detail)) }
                }
                messages.append(["role": "tool", "tool_call_id": id, "content": resultText])
            }
        }

        // A turn must never end silent: if the model finished on a tool round
        // (empty content) or hit the round cap, force a text-only summary.
        if finalReply.isEmpty {
            print("SCORANGER-CHAT-LOOP empty reply after \(rounds) rounds; forcing summary")
            messages.append(["role": "user", "content":
                "Summarize for the user what you just did to the score (or explain what you need from them). Text only."])
            let summary = try await complete(model: model, messages: messages, allowTools: false)
            messages.append(summary)
            finalReply = (summary["content"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let historyData = try JSONSerialization.data(withJSONObject: messages)
        return Turn(reply: finalReply.isEmpty
                        ? "Something went wrong: the model returned no text (after \(rounds) rounds). Check the score's version list — operations may still have been applied."
                        : finalReply,
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

    /// Worth another go on a fresh connection: a dropped or timed-out
    /// connection, not "there is no network" or a cancelled request.
    static func isTransient(_ error: URLError) -> Bool {
        [.networkConnectionLost, .timedOut, .cannotConnectToHost,
         .cannotFindHost, .dnsLookupFailed].contains(error.code)
    }

    private func complete(model: String, messages: [[String: Any]],
                          allowTools: Bool = true) async throws -> [String: Any] {
        // stored key if present, baked-in default otherwise; a 401 self-heals
        // below by falling back to the baked key
        let storedKey = KeychainStore.openRouterKey
        var key = storedKey.isEmpty ? Self.bakedKey : storedKey
        guard !key.isEmpty else { throw ChatError.missingKey }

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://github.com/batchku/scoranger", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Scoranger", forHTTPHeaderField: "X-Title")
        var payload: [String: Any] = ["model": model, "messages": messages]
        if allowTools {
            payload["tools"] = Self.toolsJSON
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        var data: Data
        var code: Int
        var networkAttempt = 0
        while true {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            do {
                // A fresh ephemeral session per attempt, like the OMR upload
                // path: URLSession.shared pools HTTP/2 connections, and a
                // pooled one that the far end has dropped fails every retry
                // with "The network connection was lost" until it is discarded.
                let session = URLSession(configuration: .ephemeral)
                defer { session.finishTasksAndInvalidate() }
                let (d, response) = try await session.data(for: request)
                data = d
                code = (response as? HTTPURLResponse)?.statusCode ?? 0
            } catch let error as URLError where Self.isTransient(error) && networkAttempt < 3 {
                networkAttempt += 1
                try await Task.sleep(for: .seconds(networkAttempt))
                continue
            } catch let error as URLError {
                throw ChatError.network(error)
            }
            if code == 401, !Self.bakedKey.isEmpty, key != Self.bakedKey {
                // stored key is wrong — self-heal with the baked one, retry once
                key = Self.bakedKey
                KeychainStore.openRouterKey = Self.bakedKey
                continue
            }
            break
        }
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

    private static func write(_ account: String, _ rawValue: String) {
        // API keys never legitimately contain whitespace; pasted keys often do
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
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
