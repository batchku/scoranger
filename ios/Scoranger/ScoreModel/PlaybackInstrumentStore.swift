import Foundation

/// Where a reader's instrument choices are kept between sessions.
///
/// Per ARRANGEMENT, not per version. A choice is about how the reader wants to
/// hear the piece, and it would be absurd for transposing a bar to reset every
/// strip back to its guess. The version is deliberately not in the key.
///
/// Deliberately the shape of `DrawingStore`, which does the same job for
/// pencil marks: one small file per arrangement under Documents, a `rename`
/// that follows a slug when the engine renames one, and a `clear` for when the
/// arrangement is deleted. Copied rather than invented so there is one way
/// this app files per-score state, not two.
///
/// The directory is injectable so the suite can point it at a temporary folder
/// and assert an actual round trip through the disk, instead of asserting that
/// a struct equals itself.
final class PlaybackInstrumentStore {

    static let shared = PlaybackInstrumentStore()

    private let dir: URL

    init(directory: URL? = nil) {
        dir = directory ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "playback")
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
    }

    /// A slug is a path component in the workspace and could in principle
    /// carry a separator; flattened the way `DrawingStore` flattens its keys so
    /// one arrangement can never write outside this folder.
    private func url(for slug: String) -> URL {
        let safe = slug.replacingOccurrences(of: "/", with: "_")
        return dir.appending(path: "\(safe).instruments.json")
    }

    /// What the reader chose for this arrangement, or nothing.
    ///
    /// Every failure reads as "nothing chosen": a missing file is the normal
    /// case, and a corrupt one should cost the reader their choices and not
    /// their playback. The guess underneath is always a usable performance.
    func instruments(for slug: String) -> PlaybackInstruments {
        guard let data = try? Data(contentsOf: url(for: slug)),
              let stored = try? JSONDecoder().decode(PlaybackInstruments.self,
                                                     from: data)
        else { return PlaybackInstruments() }
        return stored
    }

    /// Writes, or REMOVES the file when nothing is chosen.
    ///
    /// Removing matters: "back to the guess on every strip" has to be a state
    /// that survives a relaunch, and an empty file left behind would be
    /// indistinguishable from one, so the simplest thing that is also correct
    /// is to leave no file at all.
    func save(_ instruments: PlaybackInstruments, for slug: String) {
        let target = url(for: slug)
        guard !instruments.isEmpty else {
            try? FileManager.default.removeItem(at: target)
            return
        }
        guard let data = try? JSONEncoder().encode(instruments) else { return }
        try? data.write(to: target, options: .atomic)
    }

    /// Follow a renamed arrangement. The engine moves a score's artifacts when
    /// its slug changes; state filed beside them has to move too or it is
    /// silently orphaned -- the same trap `DrawingStore.rename` exists for.
    func rename(from old: String, to new: String) {
        let source = url(for: old)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let target = url(for: new)
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.moveItem(at: source, to: target)
    }

    func clear(slug: String) {
        try? FileManager.default.removeItem(at: url(for: slug))
    }
}
