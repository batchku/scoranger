import Foundation

/// Thin client for the Scoranger engine API (`scor serve`).
struct EngineClient {
    var baseURL: URL

    init(baseURLString: String) {
        self.baseURL = URL(string: baseURLString) ?? URL(string: "http://localhost:8765")!
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private func get(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        var comps = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        let (data, response) = try await URLSession.shared.data(from: comps.url!)
        try Self.check(response, data: data)
        return data
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode >= 400 {
            if let err = try? JSONDecoder().decode(EngineError.self, from: data) { throw err }
            throw EngineError(error: "HTTP \(http.statusCode)")
        }
    }

    func manifest() async throws -> Manifest {
        try decoder.decode(Manifest.self, from: try await get("/api/scores"))
    }

    func models() async throws -> ModelCatalog {
        try decoder.decode(ModelCatalog.self, from: try await get("/api/models"))
    }

    func exportPDF(score: String, version: String?, parts: [String]? = nil) async throws -> Data {
        var query = [URLQueryItem(name: "score", value: score),
                     URLQueryItem(name: "format", value: "pdf")]
        if let version { query.append(URLQueryItem(name: "version", value: version)) }
        if let parts, !parts.isEmpty {
            query.append(URLQueryItem(name: "parts", value: parts.joined(separator: ",")))
        }
        return try await get("/api/export", query: query)
    }

    func transpose(score: String, semitones: Int) async throws {
        var comps = URLComponents(url: baseURL.appending(path: "/api/transpose"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "score", value: score),
                            URLQueryItem(name: "semitones", value: String(semitones))]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.check(response, data: data)
    }

    func chat(score: String, message: String, model: String?, history: String?) async throws -> ChatResponse {
        var req = URLRequest(url: baseURL.appending(path: "/api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 300
        var body: [String: Any] = ["score": score, "message": message]
        if let model { body["model"] = model }
        if let history { body["history"] = history }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try Self.check(response, data: data)
        return try decoder.decode(ChatResponse.self, from: data)
    }
}
