import Foundation

/// The licence text a credit points at, read out of the bundle.
///
/// A credit's `text` names a file or a folder relative to the bundle root,
/// and every file in a folder is part of the text: requests carries a LICENSE
/// and a NOTICE, and Apache-2.0 requires both to travel. `vendor_engine.sh`
/// fills `Licences/python/<distribution>/` for the Python packages;
/// deploy_testflight.sh refuses an archive where a credit's text is missing.
///
/// Pure over a directory, so a test hands it a temporary one: the unit-test
/// bundle has no host app and no `Bundle.main` worth reading.
enum LicenceText {

    struct File: Equatable {
        let name: String
        let text: String
    }

    enum Failure: Error, Equatable {
        /// The path is not in the bundle, or is a folder holding nothing.
        case missing(String)
        /// A file in it is not UTF-8.
        case unreadable(String)
    }

    /// `path` under `root`: a FILE is the whole text (CPython's LICENSE.txt
    /// sits among the standard library, which is not a licence); a FOLDER is
    /// every file in it, in name order so LICENSE comes before NOTICE.
    static func read(_ path: String, under root: URL) throws -> [File] {
        let url = root.appendingPathComponent(path)
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else {
            throw Failure.missing(path)
        }
        guard isFolder.boolValue else {
            return [try file(url, shownAs: path)]
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        let files = names.filter { !$0.hasPrefix(".") }.sorted()
        guard !files.isEmpty else { throw Failure.missing(path) }
        return try files.map { try file(url.appendingPathComponent($0), shownAs: "\(path)/\($0)") }
    }

    /// A text cut at its blank lines, for a lazy list. Nothing is reflowed:
    /// every line break inside a paragraph stays where the licence put it.
    static func paragraphs(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func file(_ url: URL, shownAs path: String) throws -> File {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw Failure.unreadable(path)
        }
        return File(name: url.lastPathComponent, text: text)
    }
}
