import Foundation

/// Bringing a library's metadata across from Newzik.
///
/// The arrangements arrive as a folder of PDFs, which carry no metadata at all
/// -- the composer, the tags and the corrected titles live in Newzik's own
/// database and travelled only as far as the folder NAMES. So they come across
/// separately, matched to the pieces already imported, by name.
///
/// Matching normalises punctuation because the export could not keep it: a
/// piece called "Imate li vino? (Do you have Wine?)" becomes a folder called
/// "Imate li vino- (Do you have Wine-)", since a filesystem will not take the
/// question marks. Case, accents and separators are levelled for the same
/// reason; nothing is guessed beyond that, and a piece that does not match is
/// reported rather than approximated.
enum MetadataMigration {

    struct Entry: Codable, Equatable {
        /// The piece's name as imported -- what to find it by.
        let match: String
        /// A corrected name, when the imported one has a typo in it.
        let title: String?
        let composer: String
        let arranger: String
        let tags: [String]
    }

    struct File: Codable { let pieces: [Entry] }

    /// One piece's worth of work, already resolved to a slug.
    struct Action: Equatable {
        let slug: String
        let rename: String?
        let composer: String
        let arranger: String
        let tags: [String]
        /// Nothing to write: the piece already says all of this.
        var isEmpty: Bool {
            rename == nil && composer.isEmpty && arranger.isEmpty && tags.isEmpty
        }
    }

    struct Plan: Equatable {
        var actions: [Action] = []
        /// Entries with no piece in the library. Reported, never guessed at.
        var unmatched: [String] = []
    }

    /// Levelled hard enough that a filesystem-safe folder name still matches
    /// the title it came from.
    static func normalise(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive],
                               locale: Locale(identifier: "en_US"))
        let kept = folded.map { ch -> Character in
            (ch.isLetter || ch.isNumber) ? ch : " "
        }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// What to write, given the file and the pieces that exist.
    ///
    /// A piece that already carries a value keeps it: this fills a library in,
    /// it does not overwrite work done since. A rename is proposed only when
    /// the name genuinely differs.
    static func plan(entries: [Entry], pieces: [PieceDoc]) -> Plan {
        var byName: [String: PieceDoc] = [:]
        for p in pieces { byName[normalise(p.name)] = p }

        var plan = Plan()
        for e in entries {
            guard let piece = byName[normalise(e.match)] else {
                plan.unmatched.append(e.match)
                continue
            }
            let hasComposer = (piece.composer ?? "").isEmpty == false
            let hasArranger = (piece.arranger ?? "").isEmpty == false
            let hasTags = (piece.tags ?? []).isEmpty == false
            let rename = e.title.flatMap { $0 == piece.name ? nil : $0 }
            let action = Action(slug: piece.slug,
                                rename: rename,
                                composer: hasComposer ? "" : e.composer,
                                arranger: hasArranger ? "" : e.arranger,
                                tags: hasTags ? [] : e.tags)
            if !action.isEmpty { plan.actions.append(action) }
        }
        return plan
    }

    /// Read the file that ships with the app.
    static func bundled(_ bundle: Bundle = .main) -> [Entry] {
        guard let url = bundle.url(forResource: "newzik-metadata", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else { return [] }
        return file.pieces
    }
}
