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
        if value.range(of: #"\.(musicxml|xml|mxl|mid|midi|abc|pdf)$"#,
                       options: [.regularExpression, .caseInsensitive]) != nil { return true }
        let placeholders = ["music21 fragment", "untitled", "untitled score", "score"]
        if placeholders.contains(value.lowercased()) { return true }
        let hasSpace = value.rangeOfCharacter(from: .whitespaces) != nil
        let joined = value.contains("-") || value.contains("_")
        return !hasSpace && joined
    }

    /// The workspace's own file name for a version: `v001.mxl`, `v002`, `V001`.
    ///
    /// Mirrors `ops.is_internal_artifact_name`. Separate from `isSlugLike`
    /// because they are different judgements and only one of them can be
    /// salvaged: a slug still carries the music's name and improves by being
    /// spelled out, while `v001.mxl` carries nothing and improves only by not
    /// being shown. Spelling one out is what put "V001" on the page after the
    /// first attempt at this fix.
    static func isInternalArtifactName(_ text: String?) -> Bool {
        guard let text else { return false }
        var stem = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dot = stem.lastIndex(of: ".") { stem = String(stem[stem.startIndex..<dot]) }
        return stem.range(of: #"^[vV]\d{2,}$"#, options: .regularExpression) != nil
    }

    /// A slug spelled out. Mirrors `ops.humanise_title`.
    static func humanised(_ text: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, isSlugLike(value) else { return value }
        var spelled = value.replacingOccurrences(
            of: #"\.(musicxml|xml|mxl|mid|midi|abc|pdf)$"#, with: "",
            options: [.regularExpression, .caseInsensitive])
        spelled = spelled.replacingOccurrences(of: #"[-_]+"#, with: " ",
                                               options: .regularExpression)
        spelled = spelled.replacingOccurrences(of: #"\s+"#, with: " ",
                                               options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard let first = spelled.first else { return value }
        return first.uppercased() + spelled.dropFirst()
    }

    /// What ONE arrangement is called in a list.
    ///
    /// The rows in a piece read `score.title ?? score.name`, and a title
    /// poisoned before the engine guarded the way in beats the real name --
    /// which is how two arrangements of Jovano Jovanke both came to be labelled
    /// "v001.mxl". A stored title only wins while it is a name.
    static func arrangementName(title: String?, name: String,
                                slug: String? = nil) -> String {
        for candidate in [title, name] {
            guard let candidate else { continue }
            if isInternalArtifactName(candidate) { continue }
            if isSlugLike(candidate, slug: slug) { continue }
            return candidate
        }
        // Neither is a name as it stands. The arrangement's OWN name is still
        // the closest thing to one, so it is spelled out -- unless it is an
        // artifact name too, which spells out to nothing worth reading.
        if !isInternalArtifactName(name) {
            let spelled = humanised(name)
            if !spelled.isEmpty { return spelled }
        }
        return "Untitled arrangement"
    }

    /// One arrangement of a list of them, as it should be filed.
    struct Arrangement: Equatable {
        var title: String?
        var name: String
        var slug: String
        /// The parts of the displayed version, when there are any. A scan has
        /// none until OMR reads it.
        var parts: [String] = []
        /// Whether the arrangement is a scan rather than notation.
        var isScan: Bool = false
    }

    /// The labels for every arrangement of one piece, none of them the same.
    ///
    /// Two rows reading identically is its own bug, reported alongside the
    /// file-name one: the numeral badge beside them is not a name, and a reader
    /// choosing between two identical lines is guessing. Where a collision
    /// survives, the rows are told apart by something TRUE about them -- what
    /// is in them, or whether they are scans -- and by their position only when
    /// nothing else distinguishes them at all.
    static func labels(for arrangements: [Arrangement]) -> [String] {
        let base = arrangements.map {
            arrangementName(title: $0.title, name: $0.name, slug: $0.slug)
        }
        var counts: [String: Int] = [:]
        for label in base { counts[label, default: 0] += 1 }

        var ordinal: [String: Int] = [:]
        return base.indices.map { i in
            let label = base[i]
            guard (counts[label] ?? 0) > 1 else { return label }
            let group = base.indices.filter { base[$0] == label }
            if let marks = distinguishers(group.map { arrangements[$0] }),
               let mark = marks[group.firstIndex(of: i)!] {
                return "\(label) — \(mark)"
            }
            ordinal[label, default: 0] += 1
            return "\(label) (\(ordinal[label]!))"
        }
    }

    /// Something true that tells a colliding group apart, or nil when nothing
    /// does. Tried in order of how much it tells a reader.
    private static func distinguishers(_ group: [Arrangement]) -> [String?]? {
        let byParts = group.map { partDescription($0.parts) }
        if byParts.allSatisfy({ !$0.isEmpty }), Set(byParts).count == group.count {
            return byParts
        }
        let byKind = group.map { $0.isScan ? "scan" : "notation" }
        if Set(byKind).count == group.count { return byKind }
        return nil
    }

    /// The title to show, in order of what is actually known.
    static func display(title: String?, name: String, slug: String,
                        pieceName: String?, parts: [String]) -> String {
        for candidate in [title, name] {
            guard let candidate, !isInternalArtifactName(candidate) else { continue }
            if !isSlugLike(candidate, slug: slug) { return candidate }
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

    /// The version count, as the label on the control that opens the version
    /// dropdown. Nil when there is nothing to list.
    static func versionsLabel(count: Int) -> String? {
        guard count > 0 else { return nil }
        return "\(count) version" + (count == 1 ? "" : "s")
    }
}
