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
    /// book-detect over the bookmarks and the text layer: well under a second
    /// on a 134-page book, but a stage all the same.
    static let finding = "finding its tunes…"

    /// Vision over the pages that have no text layer -- the long wait on a
    /// scanned book, so it counts.
    static func scanning(_ done: Int, of total: Int) -> String {
        "reading scanned page \(done) of \(total)…"
    }

    /// When the tunes could not be found. The book is still imported and
    /// still usable -- the manual page ranges work -- so this says so.
    static func detectionFailure(name: String, reason: String) -> String {
        say("\(name) was imported, but its tunes could not be found", reason)
    }

    static func splitFailure(name: String, reason: String) -> String {
        say("The tunes could not be taken out of \(name)", reason)
    }

    static func contentsFailure(name: String, reason: String) -> String {
        say("The contents of \(name) could not be saved", reason)
    }

    /// What to say when it fails. The engine's own message is kept -- a
    /// missing module and an unreadable PDF are not the same problem, and the
    /// only report that ever reaches us is what the reader can see.
    static func failure(name: String, reason: String) -> String {
        say("\(name) could not be imported as a book", reason)
    }

    /// ...and the same for taking pages out of one, which reported nothing at
    /// all: the screen showed a note on success and stayed silent on failure.
    static func extractionFailure(name: String, reason: String) -> String {
        say("\(name) could not be taken out of the book", reason)
    }

    private static func say(_ what: String, _ reason: String) -> String {
        let detail = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? "\(what)." : "\(what): \(detail)"
    }
}
