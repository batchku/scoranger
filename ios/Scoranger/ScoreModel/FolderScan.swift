import Foundation

/// Listing the files under a chosen folder.
///
/// This exists because a directory vended by the iCloud file provider does not
/// enumerate through plain POSIX calls: `os.walk` on such a path yields NOTHING,
/// while opening a file inside the very same directory works. Import File
/// therefore worked on an iCloud library while Import Folder found no files at
/// all, planned nothing, and returned to the library without a word.
///
/// FileManager's enumerator goes through the file coordination machinery that
/// knows about providers, so it sees what Files.app shows. The listing is made
/// HERE, inside the security scope the picker granted, and handed to the engine
/// as relative paths -- the engine is given the names, never the job of finding
/// them.
enum FolderScan {

    /// Every file beneath `folder`, as a path relative to it ("Piece/take.pdf").
    ///
    /// Directories are not listed; only the files inside them. Order is not
    /// promised -- the engine sorts before it groups.
    static func relativePaths(in folder: URL,
                              using fm: FileManager = .default) -> [String] {
        let base = folder.standardizedFileURL.pathComponents
        guard let walk = fm.enumerator(at: folder,
                                       includingPropertiesForKeys: [.isRegularFileKey],
                                       options: []) else { return [] }
        var found: [String] = []
        for case let url as URL in walk {
            // A folder is a container here, not an item: only its files count.
            let regular = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?
                .isRegularFile
            if regular == false { continue }
            let parts = url.standardizedFileURL.pathComponents
            guard parts.count > base.count,
                  Array(parts.prefix(base.count)) == base else { continue }
            found.append(parts.dropFirst(base.count).joined(separator: "/"))
        }
        return found
    }
}
