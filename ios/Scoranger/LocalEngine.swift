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

    func deleteScore(_ slug: String) async throws {
        _ = try await result(op: "delete-score", args: ["score": slug])
    }

    /// Absolute path of a version's MusicXML artifact (for rendering).
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
