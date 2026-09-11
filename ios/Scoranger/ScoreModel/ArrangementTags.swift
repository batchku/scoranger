import Foundation

/// Tags on an arrangement (design/DESIGN_SYSTEM.md [C14]).
///
/// Tags are not notation, so they save at once without a version (A3) and
/// live beside the library rather than in it: one JSON file under
/// Application Support, keyed by the arrangement's uid (its identity across
/// renames and devices) with the slug as the fallback for a library older
/// than uids. Piece tags stay on the piece document, where the engine keeps
/// them; both are filterable [C9].
final class ArrangementTags {
    static let shared = ArrangementTags()

    private var map: [String: [String]] = [:]
    private let url: URL

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("arrangement-tags.json")
        load()
    }

    func tags(for key: String) -> [String] { map[key] ?? [] }

    func set(_ tags: [String], for key: String) {
        let cleaned = ArrangementTags.clean(tags)
        if cleaned.isEmpty { map.removeValue(forKey: key) } else { map[key] = cleaned }
        save()
    }

    /// "chanson, Waltz , chanson" -> ["chanson", "Waltz"]: trimmed, deduped
    /// case-insensitively, first spelling kept.
    static func clean(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    static func parse(_ text: String) -> [String] {
        clean(text.split(separator: ",").map(String.init))
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else { return }
        map = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(map)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("SCORANGER arrangement tags: could not save: %@", "\(error)")
        }
    }
}
