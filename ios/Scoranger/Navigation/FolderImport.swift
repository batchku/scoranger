import Foundation

/// The plan for importing a whole exported folder, as the app holds it.
///
/// A library exported from another app arrives as one folder per piece, its
/// files the arrangements. The engine plans that structure without writing
/// anything (`bulk.plan`), and this is that plan, decoded — so a reader can
/// see the shape of their own library before it exists.
struct FolderImportPlan: Equatable {
    struct Arrangement: Equatable, Identifiable {
        var id: String { file }
        let name: String
        let file: String
        /// "pdf" or "musicxml" — a scan reads at once; notation is editable.
        let kind: String
    }

    struct Piece: Equatable, Identifiable {
        var id: String { piece }
        let piece: String
        let arrangements: [Arrangement]
    }

    let folder: URL
    let pieces: [Piece]
    /// Files that are not scores at all. Counted, never silently dropped.
    let ignored: Int

    var arrangementCount: Int { pieces.reduce(0) { $0 + $1.arrangements.count } }
    var isEmpty: Bool { pieces.isEmpty }

    /// What the confirm button says it will do.
    var summary: String {
        let p = pieces.count == 1 ? "1 piece" : "\(pieces.count) pieces"
        let a = arrangementCount == 1 ? "1 arrangement" : "\(arrangementCount) arrangements"
        return "\(p), \(a)"
    }

    /// Decode the engine's plan. Returns nil when the shape is not what the
    /// engine promises, rather than importing a guess.
    static func decode(_ payload: [String: Any], folder: URL) -> FolderImportPlan? {
        guard let plan = payload["plan"] as? [String: Any],
              let rawPieces = plan["pieces"] as? [[String: Any]] else { return nil }
        let pieces: [Piece] = rawPieces.compactMap { raw in
            guard let name = raw["piece"] as? String,
                  let rawArrangements = raw["arrangements"] as? [[String: Any]]
            else { return nil }
            let arrangements = rawArrangements.compactMap { a -> Arrangement? in
                guard let file = a["file"] as? String else { return nil }
                return Arrangement(name: (a["name"] as? String) ?? file,
                                   file: file,
                                   kind: (a["kind"] as? String) ?? "musicxml")
            }
            return Piece(piece: name, arrangements: arrangements)
        }
        let ignored = (plan["ignored"] as? [[String: Any]])?.count ?? 0
        return FolderImportPlan(folder: folder, pieces: pieces, ignored: ignored)
    }
}
