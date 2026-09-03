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
            // No composer is no composer. It used to read "unknown", which is
            // a word where a fact should be -- and after a PDF import, which
            // carries no metadata, EVERY row said it.
            //
            // The PIECE's own credit wins: a scan has no notation to carry one,
            // so for an imported library it is the only credit there is.
            let composer = (piece.composer?.isEmpty == false ? piece.composer! : nil)
                ?? arrangements.compactMap { $0.composer }.first { !$0.isEmpty }
                ?? ""
            let sources = arrangements.reduce(0) { $0 + ($1.sources?.count ?? 0) }
            // No count chip: the subtitle already says "3 arrangements" in
            // words, and saying it twice on one row is noise (0.4.1 §5). The
            // warning and plain chips stay -- they are facts you cannot read
            // anywhere else on the row.
            // What this piece HOLDS leads every other chip (0.6.3 #3, #4).
            // A library of imported PDFs and OMR'd notation looked identical
            // row by row, and it is the fact that decides whether anything
            // else on the row can be transposed, selected, asked about or
            // played -- so it goes ahead of where the tune is from.
            var chips = ArtifactTag.chips(
                files: arrangements.flatMap { $0.versions.map(\.file) })
            for tag in piece.tags ?? [] {
                chips.append(.init(text: tag, kind: .plain))
            }
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
                subtitle: [composer, "\(arrangements.count) "
                    + (arrangements.count == 1 ? "arrangement" : "arrangements")]
                    .filter { !$0.isEmpty }.joined(separator: " · "),
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
            var chips = ArtifactTag.chips(files: score.versions.map(\.file))
            chips.append(.init(text: "UNFILED", kind: .warning))
            if isOMRDraft(score) { chips.append(.init(text: "OMR DRAFT", kind: .warning)) }
            return LibraryRow(
                id: score.slug,
                title: score.title ?? score.name,
                subtitle: [score.composer ?? "", "\(score.versions.count) "
                    + (score.versions.count == 1 ? "version" : "versions")]
                    .filter { !$0.isEmpty }.joined(separator: " · "),
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

    /// Books: a collection is one row, and what it says about itself is how
    /// long it is. No chips -- a book has no arrangements of its own, which is
    /// exactly what distinguishes it from a piece.
    static func bookRows(manifest: Manifest) -> [LibraryRow] {
        (manifest.books ?? []).map { book in
            LibraryRow(id: book.slug,
                       title: book.name,
                       subtitle: book.pages.map { "\($0) pages" } ?? "",
                       chips: [],
                       meta: "",
                       sortName: book.name,
                       composer: "",
                       changed: "",
                       arrangementCount: 0)
        }
    }

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
            // A set list is a gig's running order, and what a player needs to
            // know before the gig is whether any of it is still a PDF (#4).
            var chips = ArtifactTag.chips(
                files: setlist.arrangements.compactMap { scores[$0] }
                    .flatMap { $0.versions.map(\.file) })
            chips.append(.init(text: "ORDERED", kind: .plain))
            return LibraryRow(
                id: setlist.slug,
                title: setlist.name,
                subtitle: ([heading] + order).joined(separator: " · "),
                chips: chips,
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
            // A row with no composer sorts LAST. Empty string sorts first
            // otherwise, which would put every un-credited piece above the
            // named ones -- the opposite of what sorting by composer is for.
            return rows.sorted { a, b in
                if a.composer.isEmpty != b.composer.isEmpty { return !a.composer.isEmpty }
                let c = a.composer.localizedCaseInsensitiveCompare(b.composer)
                if c != .orderedSame { return c == .orderedAscending }
                return a.sortName.localizedCaseInsensitiveCompare(b.sortName) == .orderedAscending
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

    /// Client-side search over what the manifest holds: names, composers and
    /// tags (§7). Case- and diacritic-insensitive, matching anywhere in the
    /// field, because a person searching "tango" should find "Libertango".
    ///
    /// Tags are in here rather than behind a filter control: they are already
    /// on the row as chips, and typing "Serbia" to see the Serbian tunes needs
    /// no new affordance to learn.
    static func searched(_ rows: [LibraryRow], query: String) -> [LibraryRow] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return rows }
        return rows.filter { row in
            ([row.title, row.subtitle, row.composer] + row.chips.map(\.text)).contains {
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

// MARK: - What the library says it holds (L11, #39)

extension LibraryModel {

    /// The count under "My library", as a phrase rather than a bare number --
    /// and counting the rows that are actually on screen, by what they are.
    ///
    /// It read "My library 1", which names nothing. Then it read "2 pieces · 2
    /// arrangements" over two rows that were both UNFILED ARRANGEMENTS (#39):
    /// an arrangement with no piece is not a piece, and the total counted the
    /// same music twice under two names. Neither number matched what the
    /// reader could see.
    ///
    /// So the header counts top-level ROWS by their true kind, and nothing
    /// else: "1 piece · 3 unfiled" over four rows. The cross-total is gone on
    /// purpose -- arrangements inside a piece are visible when you open it,
    /// and a number in the header that does not match the rows under it is
    /// the whole of what went wrong here.
    static func countPhrase(segment: LibrarySegment, rows: [LibraryRow]) -> String {
        switch segment {
        case .pieces:
            guard !rows.isEmpty else { return "No pieces yet" }
            let unfiled = rows.filter(isUnfiled).count
            let pieces = rows.count - unfiled
            switch (pieces, unfiled) {
            case (0, let u):  return "\(plural(u, "unfiled arrangement"))"
            case (let p, 0):  return plural(p, "piece")
            case (let p, let u): return "\(plural(p, "piece")) · \(u) unfiled"
            }
        case .setlists:
            guard !rows.isEmpty else { return "No set lists yet" }
            return plural(rows.count, "set list")
        case .books:
            guard !rows.isEmpty else { return "No books yet" }
            return plural(rows.count, "book")
        }
    }

    /// An arrangement that belongs to no piece. The row says so itself -- the
    /// same signal the Unfiled filter reads, so the header and the filter can
    /// never disagree about what is unfiled.
    static func isUnfiled(_ row: LibraryRow) -> Bool {
        row.chips.contains { $0.text == "UNFILED" }
    }

    /// "1 piece", "2 pieces" -- the noun is never dropped and never mis-agreed.
    static func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}

// MARK: - What the list is showing right now (#42)

/// Loading is not emptiness.
///
/// At launch the manifest is nil and the engine has not answered yet, which
/// looks exactly like a library with nothing in it -- so the empty state, with
/// its "No music yet" and its Import button, flashed up on every launch of a
/// device that is full of music. The score view already knew the difference
/// (`AppState.libraryLoaded`); the library itself did not.
enum LibraryListState: Equatable {
    /// Still looking. Nothing is known yet, so nothing may be claimed.
    case loading
    /// Looked, and there is genuinely nothing here.
    case empty
    /// There is music, but not any that matches what was typed.
    case noMatches
    case rows
}

extension LibraryModel {

    static func listState(loaded: Bool, rows: Int, pendingImports: Int,
                          isFiltered: Bool) -> LibraryListState {
        if rows > 0 || pendingImports > 0 { return .rows }
        // An import in flight is content: the row for it is already on screen.
        guard loaded else { return .loading }
        return isFiltered ? .noMatches : .empty
    }
}
