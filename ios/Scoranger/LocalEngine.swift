import Foundation

/// Typed facade over the embedded Python engine (PythonEngine actor).
/// Mirrors the subset of EngineClient the app uses, so AppState can switch
/// between the on-device engine and a remote `scor serve`.
enum LocalEngineError: Error, LocalizedError {
    case engine(String)
    var errorDescription: String? {
        if case .engine(let msg) = self { return msg }
        return nil
    }
}

struct LocalEngine {
    private func result(op: String, args: [String: Any] = [:]) async throws -> [String: Any] {
        let r = await PythonEngine.shared.call(op: op, args: args)
        guard let ok = r["ok"] as? Bool, ok else {
            throw LocalEngineError.engine(r["error"] as? String ?? "engine error")
        }
        return (r["result"] as? [String: Any]) ?? [:]
    }

    private func decode<T: Decodable>(_ dict: [String: Any], as type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }

    func manifest() async throws -> Manifest {
        try decode(try await result(op: "manifest"), as: Manifest.self)
    }

    func transpose(score: String, semitones: Int) async throws {
        _ = try await result(op: "transpose",
                             args: ["score": score, "interval": String(semitones)])
    }

    /// Import a MusicXML/MIDI file into the on-device workspace, optionally
    /// filing the new arrangement under a piece.
    @discardableResult
    func importScore(fileURL: URL, name: String?, piece: String? = nil) async throws -> String {
        var args: [String: Any] = ["path": fileURL.path]
        if let name { args["name"] = name }
        if let piece { args["piece"] = piece }
        let r = try await result(op: "import", args: args)
        return (r["score"] as? String) ?? ""
    }

    /// Import a PDF as a scan arrangement: stored as it arrived, readable and
    /// annotatable at once. OMR is a separate, explicit step afterwards.
    func importPDF(fileURL: URL, name: String?, piece: String? = nil) async throws -> String {
        var args: [String: Any] = ["path": fileURL.path]
        if let name { args["name"] = name }
        if let piece { args["piece"] = piece }
        let r = try await result(op: "import-pdf", args: args)
        return (r["score"] as? String) ?? ""
    }

    /// Plan (or run) the import of a whole exported folder.
    ///
    /// `commit: false` writes nothing and returns the tree it WOULD build --
    /// this runs across an entire library, and the shape of someone's library
    /// is worth reading before it exists.
    func bulkImport(folder: URL, commit: Bool,
                    manifest: [[String: Any]]? = nil) async throws -> [String: Any] {
        var args: [String: Any] = ["folder": folder.path, "commit": commit]
        if let manifest { args["manifest"] = manifest }
        return try await result(op: "bulk-import", args: args)
    }

    /// Add a notation file as the next VERSION of an existing arrangement.
    /// What OMR on demand produces: the scan stays as it was, and the
    /// transcription sits after it in the same history.
    /// `recordedAs` is the label the VERSION carries in its history ("omr"),
    /// not a bridge op -- named apart from `op:` so it cannot be mistaken for
    /// one, by a reader or by check_bridge_ops.
    @discardableResult
    func addVersion(from fileURL: URL, score: String,
                    recordedAs label: String) async throws -> String {
        let r = try await result(op: "add-version-from-file",
                                 args: ["score": score, "path": fileURL.path, "op": label])
        return (r["version"] as? String) ?? ""
    }

    func deleteScore(_ slug: String) async throws {
        _ = try await result(op: "delete-score", args: ["score": slug])
    }

    /// Absolute path of a version's MusicXML artifact (for rendering).
    /// Write a version out as MusicXML or MIDI and hand back where it landed.
    ///
    /// PDF is deliberately NOT here: the bridge refuses it, because engraving
    /// on device is Swift and carries chord adjustments and whistle fingerings
    /// that the Python side never sees. `AppState.exportFile` routes PDF to
    /// `VerovioRenderer` instead.
    func exportFile(score: String, version: String?,
                    format: String, parts: [String] = []) async throws -> String {
        var args: [String: Any] = ["score": score, "format": format]
        if let version { args["version"] = version }
        if !parts.isEmpty { args["parts"] = parts.joined(separator: ",") }
        let r = try await result(op: "export", args: args)
        guard let path = r["path"] as? String else {
            throw LocalEngineError.engine("no path in export result")
        }
        return path
    }

    func versionFilePath(score: String, version: String?) async throws -> String {
        var args: [String: Any] = ["score": score]
        if let version { args["version"] = version }
        let r = try await result(op: "version-file", args: args)
        guard let path = r["path"] as? String else {
            throw LocalEngineError.engine("no path in version-file result")
        }
        return path
    }

    /// Raw op passthrough (used by the chat tool loop).
    func call(op: String, args: [String: Any]) async throws -> [String: Any] {
        try await result(op: op, args: args)
    }
}
