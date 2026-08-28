import Foundation

/// What the score view calls the thing you are reading (L18).
///
/// Ali's screenshot showed "sous-le-ciel-quartet" as the title, in the top bar
/// and engraved on the page. That is the file it came out of. The engine no
/// longer lets a file name become a title on the way in -- but scores imported
/// before that fix still carry one, and a name is not something to rewrite
/// under someone silently. So the view refuses to SAY it: a title that is
/// really a slug is replaced with what the app does know, which is the piece
/// this arrangement belongs to and what is in it.
enum ScoreTitle {

    /// A title that is really a file name or a slug.
    ///
    /// Mirrors `_is_junk_title` in engine/scoranger_engine/ops.py -- the same
    /// judgement on both sides of the boundary, because the engine decides
    /// what to STORE and the view decides what to SHOW, and they must agree
    /// about what counts as a name.
    static func isSlugLike(_ text: String, slug: String? = nil) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return true }
        if let slug, value.caseInsensitiveCompare(slug) == .orderedSame { return true }
        if value.range(of: #"\.(musicxml|xml|mxl|mid|midi|pdf)$"#,
                       options: [.regularExpression, .caseInsensitive]) != nil { return true }
        let placeholders = ["music21 fragment", "untitled", "untitled score", "score"]
        if placeholders.contains(value.lowercased()) { return true }
        let hasSpace = value.rangeOfCharacter(from: .whitespaces) != nil
        let joined = value.contains("-") || value.contains("_")
        return !hasSpace && joined
    }

    /// The title to show, in order of what is actually known.
    static func display(title: String?, name: String, slug: String,
                        pieceName: String?, parts: [String]) -> String {
        for candidate in [title, name] {
            if let candidate, !isSlugLike(candidate, slug: slug) { return candidate }
        }
        if let pieceName, !isSlugLike(pieceName, slug: slug) {
            let described = partDescription(parts)
            return described.isEmpty ? pieceName : "\(pieceName) — \(described)"
        }
        return "Untitled arrangement"
    }

    /// What is in it, when the name cannot say: the parts if there are few
    /// enough to read, a count when there are not.
    static func partDescription(_ parts: [String]) -> String {
        let named = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.lowercased() != "voice" }
        guard !named.isEmpty else {
            return parts.isEmpty ? "" : "\(parts.count) part\(parts.count == 1 ? "" : "s")"
        }
        if named.count <= 3 { return named.joined(separator: ", ") }
        return "\(named.count) parts"
    }
}
