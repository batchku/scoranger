import Foundation

/// What a version row says HAPPENED, in the reader's words.
///
/// The version lists showed the engine's own op name: "v001 bulk-import",
/// "v002 omr". Ali marked both "Don't!" -- and he is right, those are pipeline
/// names. `bulk-import` is a migration route, `omr` is optical music
/// recognition; neither is a thing he did to his music, and a version list is
/// the history of what he did to his music.
///
/// So each op is given a phrase. An op with no phrase says "edited" rather
/// than its own name: the list stays readable when the engine gains an op
/// nobody has translated yet, and it can never leak one. That degradation is
/// the point -- there are about forty ops and this table will fall behind.
enum VersionLabel {

    /// op -> what happened. Written from the reader's side of the operation:
    /// he did not "keep-parts", he kept some parts.
    static let phrases: [String: String] = [
        // where an arrangement comes from
        "import": "imported",
        "import-pdf": "imported",
        "bulk-import": "imported",
        "create-arrangement": "imported",
        "book-extract": "taken from a book",
        "omr": "transcribed from the scan",
        "add-version-from-file": "transcribed from the scan",
        "duplicate": "copied",
        "selftest": "engine self-test",

        // pitch
        "transpose": "transposed",
        "transpose-elements": "selection transposed",
        "octave-shift": "moved an octave",
        "respell": "accidentals respelled",
        "clean-accidentals": "accidentals tidied",
        "set-accidental": "an accidental changed",

        // staves and parts
        "keep-parts": "parts kept",
        "remove-parts": "parts removed",
        "merge-parts": "parts merged",
        "split-bass": "bass split onto its own staff",
        "absorb-part": "a part folded into another",
        "flatten-voices": "voices flattened onto one staff",
        "pull-part": "a part brought in",
        "rebuild-part": "a part rebuilt",
        "limit-part": "a part brought into range",
        "rename-part": "a part renamed",
        "strip-notes": "notes cleared, chord names kept",
        "change-clef": "clef changed",
        "change-instrument": "instrument changed",

        // what is written on the page
        "consolidate-ties": "ties tidied",
        "simplify-repeats": "repeated bars simplified",
        "set-chords": "chord symbols written",
        "chart-style": "styled as a chord chart",
        "chord-diagrams": "chord diagrams added",
        "guitar-tab": "guitar tab added",
        "whistle-fingerings": "whistle fingerings added",
        "set-structure": "repeats and navigation marks",
        "set-rehearsal": "rehearsal marks",
        "adjust-element": "something moved or resized",
        "set-metadata": "title and credits",
    ]

    /// What every unmapped op says. Truthful and says nothing it does not
    /// know: a version exists because the arrangement was changed.
    static let fallback = "edited"

    /// The phrase for one op.
    static func text(_ op: String?) -> String {
        let key = (op ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return fallback }
        return phrases[key] ?? fallback
    }

    /// The value beside a version in a list. A version made during a chat turn
    /// says what was ASKED for instead -- the reader's own words beat any
    /// phrase written here.
    static func text(op: String?, prompt: String?) -> String {
        if let prompt {
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return text(op)
    }

    /// True when the string is one of the engine's own op names.
    ///
    /// Only a test needs this: it is how "no raw op string reaches a row" is
    /// asserted, rather than by listing the rows and reading them.
    static func isRawOpName(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return phrases.keys.contains(value)
    }
}
