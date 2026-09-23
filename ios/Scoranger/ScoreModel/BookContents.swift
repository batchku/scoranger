import Foundation

/// A book's tunes as a list the reader edits before it is kept.
///
/// The engine PROPOSES the list (`book-detect`); this is what the review does
/// to it before anything is written -- rename a tune, move where it starts or
/// ends, fold a false start back into the tune before it, split a tune the
/// detector ran together, drop a row. It is pure so ScorangerTests can hold
/// it, and it never reorders: a book's tunes are in page order, and an edit
/// that broke that would make "next tune" mean something else.
struct BookContents: Equatable {
    private(set) var entries: [BookEntry]
    let pages: Int

    init(entries: [BookEntry], pages: Int) {
        self.entries = entries.sorted { ($0.from, $0.to) < ($1.from, $1.to) }
        self.pages = pages
    }

    /// Why the list cannot be kept yet, or nil when it can. Mirrors
    /// booksplit._validated, so the button is disabled for exactly the lists
    /// the engine would refuse.
    var problem: String? {
        if entries.isEmpty { return "There are no tunes in the list." }
        for (n, e) in entries.enumerated() {
            let title = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { return "Tune \(n + 1) has no title." }
            if e.from < 1 || e.to > pages || e.from > e.to {
                return "“\(title)” is pages \(e.from)–\(e.to); the book has pages 1–\(pages)."
            }
        }
        return nil
    }

    mutating func rename(_ id: String, to title: String) {
        guard let i = index(id) else { return }
        entries[i].title = title
    }

    /// Where a tune starts and ends. Clamped into the book, never inverted.
    mutating func setRange(_ id: String, from: Int, to: Int) {
        guard let i = index(id) else { return }
        let start = min(max(from, 1), pages)
        entries[i].from = start
        entries[i].to = min(max(to, start), pages)
        entries.sort { ($0.from, $0.to) < ($1.from, $1.to) }
    }

    /// A false start -- a page the detector read as a new tune that is the
    /// last one turned over -- folded back into the tune before it.
    mutating func mergeWithPrevious(_ id: String) {
        guard let i = index(id), i > 0 else { return }
        entries[i - 1].to = max(entries[i - 1].to, entries[i].to)
        entries.remove(at: i)
    }

    /// Two tunes the detector ran together, parted at `page`: the second
    /// starts there and is named `title`.
    mutating func split(_ id: String, at page: Int, title: String) {
        guard let i = index(id), page > entries[i].from, page <= entries[i].to else { return }
        var second = entries[i]
        second.id = UUID().uuidString
        second.title = title
        second.from = page
        second.evidence = nil
        entries[i].to = page - 1
        entries.insert(second, at: i + 1)
    }

    mutating func remove(_ id: String) {
        entries.removeAll { $0.id == id }
    }

    mutating func add(title: String, from: Int, to: Int) {
        let start = min(max(from, 1), pages)
        entries.append(BookEntry(id: UUID().uuidString, title: title,
                                 from: start, to: min(max(to, start), pages)))
        entries.sort { ($0.from, $0.to) < ($1.from, $1.to) }
    }

    private func index(_ id: String) -> Int? {
        entries.firstIndex { $0.id == id }
    }
}

/// Where the reader is in a book's contents, the way a set list tracks its
/// place: worked out from the entry on screen, never stored as an index that
/// an edit to the list could leave pointing at the wrong tune.
enum BookReading {
    static func position(of id: String, in entries: [BookEntry]) -> Int? {
        entries.firstIndex { $0.id == id }
    }

    static func neighbour(of id: String, in entries: [BookEntry], by delta: Int) -> BookEntry? {
        guard let i = position(of: id, in: entries) else { return nil }
        let j = i + delta
        return entries.indices.contains(j) ? entries[j] : nil
    }

    /// "Tune 3 of 124"
    static func label(of id: String, in entries: [BookEntry]) -> String? {
        position(of: id, in: entries).map { "Tune \($0 + 1) of \(entries.count)" }
    }

    /// "p. 12" or "pp. 12–14"
    static func pages(_ entry: BookEntry) -> String {
        entry.from == entry.to ? "p. \(entry.from)" : "pp. \(entry.from)–\(entry.to)"
    }
}

/// What a file shared into the app should become (0.14.0 §1).
enum ImportChoice: Equatable {
    /// A new piece named after the file -- matched by name before one is
    /// created, the rule every import follows.
    case newPiece
    /// A new arrangement in a piece the reader picks.
    case existingPiece(String)
    /// A book: a collection its tunes are read or taken out of.
    case newBook

    /// Whether a book can be made of these files: one PDF, since a book IS a
    /// PDF and several files shared at once are several things.
    static func bookAvailable(for urls: [URL]) -> Bool {
        urls.count == 1 && urls[0].pathExtension.lowercased() == "pdf"
    }
}
