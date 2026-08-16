import Foundation

// Mirrors the engine's manifest/chat JSON (decoded with .convertFromSnakeCase).

struct Manifest: Codable {
    var generated: String?
    var scores: [ScoreDoc]
}

struct ScoreDoc: Codable, Identifiable, Hashable {
    var slug: String
    var name: String
    var title: String?
    var composer: String?
    var latest: String?
    var versions: [VersionDoc]
    var sources: [SourceDoc]?

    var id: String { slug }

    static func == (lhs: ScoreDoc, rhs: ScoreDoc) -> Bool { lhs.slug == rhs.slug }
    func hash(into hasher: inout Hasher) { hasher.combine(slug) }
}

struct VersionDoc: Codable, Identifiable, Hashable {
    var id: String
    var file: String
    var op: String
    var time: String?
    var parts: [PartDoc]?

    static func == (lhs: VersionDoc, rhs: VersionDoc) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct SourceDoc: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var file: String
    var parts: [PartDoc]?
}

struct PartDoc: Codable, Hashable {
    var index: Int
    var name: String
    var instrument: String?
    var clefs: [String]?
    var range: [String]?
    var measures: Int?
    var notes: Int?
}

struct ModelCatalog: Codable {
    var `default`: String
    var models: [String: String]
    var keysPresent: [String: Bool]?
}

struct ChatUsage: Codable {
    var inputTokens: Int?
    var outputTokens: Int?
    var requests: Int?
}

struct ChatResponse: Codable {
    var reply: String
    var model: String?
    var usage: ChatUsage?
    var history: String
    var latest: String?
}

/// One row in the live "what the agent is doing" checklist.
struct ChatStep: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var detail: String?
    var done: Bool
}

struct ChatDisplayMessage: Identifiable, Hashable {
    enum Role { case user, agent, error }
    let id = UUID()
    let role: Role
    let text: String
    /// The operations performed during this turn (kept in the transcript).
    var steps: [ChatStep]? = nil
}

struct EngineError: Codable, Error {
    var error: String
}
