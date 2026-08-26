import Foundation

/// One row of the library, and the derived facts shown on it.
///
/// Everything here is computed from the manifest the engine already publishes:
/// no tag store, no new fields, no engine change (NAVIGATION_SYSTEM.md §7).
struct LibraryRow: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    /// Small caps chips: "3 ARR", "OMR DRAFT", "UNFILED", "1 SOURCE".
    let chips: [Chip]
    /// Trailing meta, in mono: the version and when it last changed.
    let meta: String
    /// What the row sorts and indexes under.
    let sortName: String
    let composer: String
    let changed: String
    let arrangementCount: Int

    struct Chip: Equatable {
        let text: String
        let kind: Kind
        enum Kind: Equatable { case count, warning, plain }
    }
}

/// The library's own logic: what to show, in what order, under which letter.
///
/// Pure over the manifest so every rule can be stated in a test -- the sorts,
/// the derived filters, the alphabet rail and the search all decide what a
/// person sees, and none of them needs a screen to be checked.
enum LibraryModel {

    // MARK: - Pieces

    static func pieceRows(manifest: Manifest) -> [LibraryRow] {
        let scores = Dictionary(uniqueKeysWithValues: manifest.scores.map { ($0.slug, $0) })
        return (manifest.pieces ?? []).map { piece in
            let arrangements = piece.arrangements.compactMap { scores[$0] }
            let composer = arrangements.compactMap { $0.composer }
                .first { !$0.isEmpty } ?? "unknown"
            let sources = arrangements.reduce(0) { $0 + ($1.sources?.count ?? 0) }
            // No count chip: the subtitle already says "3 arrangements" in
            // words, and saying it twice on one row is noise (0.4.1 §5). The
            // warning and plain chips stay -- they are facts you cannot read
            // anywhere else on the row.
            var chips: [LibraryRow.Chip] = []
            if sources > 0 {
                chips.append(.init(text: "\(sources) SOURCE", kind: .plain))
            }
            if arrangements.contains(where: isOMRDraft) {
                chips.append(.init(text: "OMR DRAFT", kind: .warning))
            }
            let latest = arrangements.compactMap { $0.versions.last?.time ?? nil }.max() ?? ""
            let version = arrangements.compactMap { $0.latest }.last ?? ""
            return LibraryRow(
                id: piece.slug,
                title: piece.name,
                subtitle: "\(composer) · \(arrangements.count) "
                    + (arrangements.count == 1 ? "arrangement" : "arrangements"),
                chips: chips,
                meta: [version, shortTime(latest)].filter { !$0.isEmpty }
                    .joined(separator: " · "),
                sortName: piece.name,
                composer: composer,
                changed: latest,
                arrangementCount: arrangements.count)
        }
    }

    /// Arrangements filed under no piece. They have no `#N` -- a number is only
    /// meaningful inside a piece (§2) -- so the row shows no numeral and
    /// reserves no space for one.
    static func unfiledRows(manifest: Manifest) -> [LibraryRow] {
        manifest.scores.filter { ($0.piece ?? "").isEmpty }.map { score in
            var chips: [LibraryRow.Chip] = [.init(text: "UNFILED", kind: .warning)]
            if isOMRDraft(score) { chips.append(.init(text: "OMR DRAFT", kind: .warning)) }
            return LibraryRow(
                id: score.slug,
                title: score.title ?? score.name,
                subtitle: (score.composer?.isEmpty == false ? score.composer! : "unknown")
                    + " · \(score.versions.count) "
                    + (score.versions.count == 1 ? "version" : "versions"),
                chips: chips,
                meta: [score.latest ?? "", shortTime((score.versions.last?.time ?? nil) ?? "")]
                    .filter { !$0.isEmpty }.joined(separator: " · "),
                sortName: score.title ?? score.name,
                composer: score.composer ?? "",
                changed: (score.versions.last?.time ?? nil) ?? "",
                arrangementCount: 1)
        }
    }

    // MARK: - Setlists

    static func setlistRows(manifest: Manifest) -> [LibraryRow] {
        let scores = Dictionary(uniqueKeysWithValues: manifest.scores.map { ($0.slug, $0) })
        let pieces = manifest.pieces ?? []
        return (manifest.setlists ?? []).map { setlist in
            // The running order, named the way chat names it: piece #N. Our
            // setlists hold ARRANGEMENTS, not pieces (§2), so the subtitle has
            // to say which arrangement of which piece.
            let order = setlist.arrangements.compactMap { slug -> String? in
                guard let score = scores[slug] else { return nil }
                guard let piece = pieces.first(where: { $0.arrangements.contains(slug) }),
                      let index = piece.arrangements.firstIndex(of: slug) else {
                    return score.title ?? score.name
                }
                return "\(piece.name) #\(index + 1)"
            }
            // the same wording pieces use, then the running order
            let count = setlist.arrangements.count
            let heading = "\(count) arrangement\(count == 1 ? "" : "s")"
            return LibraryRow(
                id: setlist.slug,
                title: setlist.name,
                subtitle: ([heading] + order).joined(separator: " · "),
                chips: [.init(text: "ORDERED", kind: .plain)],
                meta: "",
                sortName: setlist.name,
                composer: "",
                changed: "",
                arrangementCount: setlist.arrangements.count)
        }
    }

    // MARK: - Sorting, filtering, searching

    static func sorted(_ rows: [LibraryRow], by sort: LibrarySort) -> [LibraryRow] {
        switch sort {
        case .name:
            return rows.sorted { $0.sortName.localizedCaseInsensitiveCompare($1.sortName) == .orderedAscending }
        case .composer:
            return rows.sorted {
                ($0.composer, $0.sortName).0.localizedCaseInsensitiveCompare($1.composer) == .orderedAscending
                    || ($0.composer.caseInsensitiveCompare($1.composer) == .orderedSame
                        && $0.sortName.localizedCaseInsensitiveCompare($1.sortName) == .orderedAscending)
            }
        case .recent:
            // newest first; a row that has never changed sorts last
            return rows.sorted { $0.changed > $1.changed }
        case .arrangements:
            return rows.sorted {
                $0.arrangementCount == $1.arrangementCount
                    ? $0.sortName.localizedCaseInsensitiveCompare($1.sortName) == .orderedAscending
                    : $0.arrangementCount > $1.arrangementCount
            }
        }
    }

    /// Client-side search over what the manifest holds: names and composers
    /// (§7). Case- and diacritic-insensitive, matching anywhere in the field,
    /// because a person searching "tango" should find "Libertango".
    static func searched(_ rows: [LibraryRow], query: String) -> [LibraryRow] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return rows }
        return rows.filter { row in
            [row.title, row.subtitle, row.composer].contains {
                $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    /// The letter a row files under. Anything not starting with a letter goes
    /// to "#", which is what the rail's last entry is for.
    static func indexLetter(for row: LibraryRow) -> String {
        let folded = row.sortName.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                          locale: .current)
        guard let first = folded.first, first.isLetter else { return "#" }
        return String(first).uppercased()
    }

    static func grouped(_ rows: [LibraryRow]) -> [(letter: String, rows: [LibraryRow])] {
        var buckets: [String: [LibraryRow]] = [:]
        for row in rows { buckets[indexLetter(for: row), default: []].append(row) }
        return buckets.keys.sorted { a, b in
            if a == "#" { return false }
            if b == "#" { return true }
            return a < b
        }.map { ($0, buckets[$0] ?? []) }
    }

    /// Every letter of the rail, and whether it has anything under it.
    static let alphabet: [String] =
        (UnicodeScalar("A").value...UnicodeScalar("Z").value)
            .compactMap { UnicodeScalar($0).map { String(Character($0)) } } + ["#"]

    static func lettersPresent(in rows: [LibraryRow]) -> Set<String> {
        Set(rows.map(indexLetter(for:)))
    }

    // MARK: - Derived facts

    /// An OMR draft: imported from a scan and never edited since. One version
    /// whose op is the import, which is exactly what a fresh scan looks like.
    static func isOMRDraft(_ score: ScoreDoc) -> Bool {
        guard score.versions.count == 1, let only = score.versions.first else { return false }
        return only.op == "import" || only.op == "omr"
    }

    /// Whatever time the engine wrote, shortened for a row's trailing edge.
    /// The engine's stamps are ISO-8601, so the date and the clock split on "T".
    static func shortTime(_ stamp: String) -> String {
        guard !stamp.isEmpty else { return "" }
        let parts = stamp.split(separator: "T")
        guard parts.count == 2 else { return stamp }
        return String(parts[1].prefix(5))
    }
}
