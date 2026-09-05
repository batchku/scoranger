import Foundation
import PencilKit

/// Local persistence for pencil annotations.
///
/// Its own file since 0.7.0, for two reasons that arrived together: the key
/// migration below needs a test, and the unit-test bundle has no host app -- it
/// compiles individual sources in, and `ScorePagesView.swift` drags a whole
/// SwiftUI canvas with it. The bundle format of design/FIREBASE.md §13 reads
/// and writes this store too, from outside any view.
///
/// Cloud sync is a later stage (§11.7); nothing here knows about it.
final class DrawingStore {
    static let shared = DrawingStore()
    private let dir: URL

    /// `dir` is injectable so the migration can be tested against a scratch
    /// directory. Nothing but a test passes it.
    init(dir: URL? = nil) {
        self.dir = dir ?? FileManager.default.urls(for: .documentDirectory,
                                                   in: .userDomainMask)[0]
            .appending(path: "annotations")
        try? FileManager.default.createDirectory(at: self.dir, withIntermediateDirectories: true)
    }

    private func url(for key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return dir.appending(path: "\(safe).pkdrawing")
    }

    func drawing(for key: String) -> PKDrawing {
        guard let data = try? Data(contentsOf: url(for: key)),
              let drawing = try? PKDrawing(data: data) else { return PKDrawing() }
        return drawing
    }

    func save(_ drawing: PKDrawing, for key: String) {
        try? drawing.dataRepresentation().write(to: url(for: key))
    }

    /// Re-file every drawing of one arrangement under a new slug.
    ///
    /// Largely retired: markup is keyed by the score's uid now, and a uid does
    /// not move when a slug does, so against a migrated library this matches
    /// nothing and does nothing. It is kept, not deleted, for the one case
    /// where it is still the right answer -- a score whose uid has not been
    /// assigned yet, whose markup is therefore still filed under the slug
    /// (`ScoreDoc.inkNamespace`). Deleting it would orphan that markup on a
    /// rename, and the cost of keeping it is a directory scan that finds
    /// nothing.
    func rename(fromPrefix old: String, toPrefix new: String) {
        let from = old.replacingOccurrences(of: "/", with: "_")
        let to = new.replacingOccurrences(of: "/", with: "_")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.lastPathComponent.hasPrefix(from + "_") {
            let moved = to + String(f.lastPathComponent.dropFirst(from.count))
            try? FileManager.default.moveItem(at: f, to: dir.appending(path: moved))
        }
    }

    func clear(prefix: String) {
        // the trailing separator matters: without it, clearing "blue" also
        // clears "blue-bossa", and clearing one version's marks could reach
        // another version whose id merely starts the same way
        let safePrefix = prefix.isEmpty ? ""
            : prefix.replacingOccurrences(of: "/", with: "_") + "_"
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files where safePrefix.isEmpty
            || f.lastPathComponent.hasPrefix(safePrefix) {
            try? FileManager.default.removeItem(at: f)
        }
    }

    /// Re-file drawings onto the key they are addressed by now.
    ///
    /// A drawing's key is `<namespace>/<version>/p<N>`, and BOTH halves moved.
    /// Version ids became opaque so two devices could allocate one without
    /// colliding (design/FIREBASE.md §3), and the namespace became the score's
    /// uid rather than its slug, because a slug is `slugify(name)` -- it moves
    /// when the score is renamed, and it means nothing on the device a bundle
    /// is opened on (§13.3). The engine migrates its own documents and
    /// deliberately renames no artifact, but a reader's pencil marks live HERE,
    /// outside the workspace. Without this they are not deleted, they are
    /// simply never looked up again: markup still on disk and gone from the
    /// page, which is the worst of both.
    ///
    /// Both hops are done in ONE pass, against the destination, rather than as
    /// two migrations that have to run in the right order. A file keyed by the
    /// old label AND the old slug is one move, not two, and re-running after a
    /// half-run cannot leave a key half-migrated.
    ///
    /// Driven by the manifest because the manifest is the only place that knows
    /// every old name beside its new one: a version carries its `label`
    /// (`v012`) beside its id, and a score carries its `slug` beside its `uid`.
    /// Idempotent, and it never overwrites: a destination that already exists is
    /// left alone and the stale source is kept, so running it twice destroys
    /// nothing.
    @discardableResult
    func migrateKeys(manifest: Manifest) -> Int {
        var files = Set(((try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []).map { $0.lastPathComponent })
        var moved = 0
        for score in manifest.scores {
            // every name this score's markup could have been filed under
            var namespaces = [score.slug]
            if let uid = score.uid, uid != score.slug { namespaces.append(uid) }
            let destNamespace = score.inkNamespace
            for version in score.versions {
                var versionKeys = [version.id]
                if let label = version.label, label != version.id { versionKeys.append(label) }
                let to = "\(destNamespace)_\(version.id)_"
                for ns in namespaces {
                    for vk in versionKeys {
                        let from = "\(ns)_\(vk)_"
                        guard from != to else { continue }
                        for name in files where name.hasPrefix(from) {
                            let target = to + String(name.dropFirst(from.count))
                            guard !files.contains(target) else { continue }
                            do {
                                try FileManager.default.moveItem(
                                    at: dir.appending(path: name),
                                    to: dir.appending(path: target))
                                files.remove(name)
                                files.insert(target)
                                moved += 1
                            } catch {
                                // a drawing that will not move is left where it
                                // is: losing the markup is worse than not
                                // migrating it
                            }
                        }
                    }
                }
            }
        }
        return moved
    }
}
