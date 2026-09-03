import Foundation

/// What an import in flight is making, and therefore where its row belongs.
///
/// Import Book put nothing on screen at all. The picker closed, the library
/// switched to Books, and the work happened in a Task nobody could see: no
/// row, no stage, and -- when the engine raised -- an error into `lastError`,
/// which the redesigned library never displays. A 52MB fake book is tens of
/// seconds of work even when it succeeds, so "nothing happened" was also what
/// a WORKING import looked like for the first half minute.
///
/// The pieces list already draws a row per import in flight. This is the one
/// fact it was missing: which list a given import belongs in.
enum ImportTarget: String, Equatable, Codable {
    /// A score file or a scan: it becomes an arrangement, under Pieces.
    case arrangement
    /// A PDF collection: it becomes a book, under Books.
    case book

    var segment: LibrarySegment {
        switch self {
        case .arrangement: return .pieces
        case .book:        return .books
        }
    }
}

/// The stages a book import passes through, named for the reader rather than
/// for the code. Copying a 52MB file and counting its pages are the two waits,
/// so they are the two things it says.
enum BookImportStage {
    static let copying = "copying the file…"
    static let reading = "reading its pages…"

    /// What to say when it fails. The engine's own message is kept -- a
    /// missing module and an unreadable PDF are not the same problem, and the
    /// only report that ever reaches us is what the reader can see.
    static func failure(name: String, reason: String) -> String {
        let detail = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty
            ? "\(name) could not be imported as a book."
            : "\(name) could not be imported as a book: \(detail)"
    }
}
