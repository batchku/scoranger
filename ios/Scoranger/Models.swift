import Foundation

// Mirrors the engine's manifest/chat JSON (decoded with .convertFromSnakeCase).

/// A collection to take arrangements out of.
///
/// A PIECE is a composition and holds arrangements. A BOOK holds many
/// compositions, and arrangements are EXTRACTED from it: a fake book filed as
/// an arrangement would put hundreds of tunes under one title.
struct BookDoc: Codable, Identifiable, Hashable {
    var slug: String
    var name: String
    var pages: Int?

    var id: String { slug }
}

struct Manifest: Codable, Equatable {
    /// The engine stamps this on every rebuild, so it differs even when
    /// nothing about the library did. Deliberately left out of equality:
    /// what the UI cares about is the content.
    var generated: String?
    var scores: [ScoreDoc]
    var pieces: [PieceDoc]?
    var setlists: [SetlistDoc]?
    /// Collections that arrangements are taken OUT of -- a fake book, a
    /// method book. Not pieces, and not arrangements.
    var books: [BookDoc]?
    /// This device's library, and its identity. Written before any account
    /// exists, so signing in later gives the library an owner rather than
    /// migrating it (design/FIREBASE.md §9.2). Optional: a manifest from an
    /// engine that predates it still decodes.
    var library: LibraryDoc?

    static func == (lhs: Manifest, rhs: Manifest) -> Bool {
        lhs.scores == rhs.scores && lhs.pieces == rhs.pieces
            && lhs.setlists == rhs.setlists && lhs.books == rhs.books
    }
}

/// The library this device holds. One per device, identity assigned once.
struct LibraryDoc: Codable, Equatable {
    var uid: String?
    var created: String?
}

struct ScoreDoc: Codable, Identifiable, Hashable {
    var slug: String
    /// Identity that outlives the title. The slug is `slugify(name)` and moves
    /// when a score is renamed; this does not, and it is what a bundle and a
    /// shared setlist entry address (design/FIREBASE.md §3, §13). Optional so a
    /// manifest written before the engine assigned one still decodes; the
    /// engine backfills it on open, so in a shipped build it is always there.
    var uid: String?
    var name: String
    var title: String?
    var composer: String?
    var latest: String?
    var versions: [VersionDoc]
    var sources: [SourceDoc]?
    var piece: String?

    var id: String { slug }

    /// What a reader's pencil marks are filed under. The uid, because markup
    /// must survive a rename and must mean the same thing on the device a
    /// bundle is opened on; the slug only while an older manifest is in hand,
    /// and `DrawingStore.migrateKeys` re-files onto the uid as soon as one
    /// appears.
    var inkNamespace: String { uid ?? slug }

    /// By content: the sidebar polls, and a poll that finds the same library
    /// must not look like a change or every row rebuilds twice a second.
    static func == (lhs: ScoreDoc, rhs: ScoreDoc) -> Bool {
        lhs.slug == rhs.slug && lhs.name == rhs.name && lhs.title == rhs.title
            && lhs.composer == rhs.composer && lhs.latest == rhs.latest && lhs.piece == rhs.piece
            && lhs.versions == rhs.versions && lhs.sources == rhs.sources
    }
    func hash(into hasher: inout Hasher) { hasher.combine(slug) }

    /// The readable name of the version `latest` points at. `latest` is an
    /// opaque id, so anywhere it was shown directly has to come through here.
    var latestLabel: String? {
        guard let latest else { return versions.last?.name }
        return versions.first { $0.id == latest }?.name ?? versions.last?.name
    }
}

struct PieceDoc: Codable, Identifiable, Hashable {
    var slug: String
    var name: String
    var arrangements: [String]
    /// The piece's own credit. Notation carries one too, but an arrangement
    /// imported as a PDF has no notation to carry it -- so for a scanned
    /// library this is the only place a composer can live.
    var composer: String?
    /// A credit that is not a composer: a performer, a transcriber, whoever
    /// made this reading of the tune.
    var arranger: String?
    /// Origin and tradition, in practice ("Serbia", "Bulgaria"). Flat, ordered
    /// as the reader typed them. Absent in a manifest written before tags
    /// existed, hence the default.
    var tags: [String]?

    var id: String { slug }

    static func == (lhs: PieceDoc, rhs: PieceDoc) -> Bool {
        lhs.slug == rhs.slug && lhs.name == rhs.name
            && lhs.arrangements == rhs.arrangements
            && lhs.composer == rhs.composer && lhs.tags == rhs.tags
            && lhs.arranger == rhs.arranger
    }
    func hash(into hasher: inout Hasher) { hasher.combine(slug) }
}

/// An ordered group of arrangements (a gig's running order). Arrangements,
/// not pieces: what gets played is a particular version of a tune.
struct SetlistDoc: Codable, Identifiable, Hashable {
    var slug: String
    var name: String
    var arrangements: [String]

    var id: String { slug }

    static func == (lhs: SetlistDoc, rhs: SetlistDoc) -> Bool {
        lhs.slug == rhs.slug && lhs.name == rhs.name
            && lhs.arrangements == rhs.arrangements
    }
    func hash(into hasher: inout Hasher) { hasher.combine(slug) }
}

struct VersionDoc: Codable, Identifiable, Hashable {
    /// The identity: opaque, assigned once, never rewritten. Key annotations,
    /// caches and selections on this; never show it to anyone.
    var id: String
    /// The name a person reads -- `v012`. Optional, and defaulted, so that a
    /// manifest written by an older engine still decodes and so that every
    /// existing `VersionDoc(...)` in the tests still compiles. `name` is what
    /// callers use.
    var label: String? = nil
    var file: String
    var op: String
    var time: String?
    /// The version this one was made FROM. Present in the manifest since the
    /// history existed; decoded here since two devices could append to the
    /// same parent (`VersionGraph`, design/FIREBASE.md §7 rule 2).
    var parent: String? = nil
    var parts: [PartDoc]?
    /// The chat turn (prompt) this version was created during, if any.
    var turn: TurnRef?

    /// What to put on screen. The id became opaque when versions had to be
    /// allocatable on two devices at once (design/FIREBASE.md §3); every place
    /// that used to render `id` renders this instead, or the library fills up
    /// with 26-character strings nobody can read.
    var name: String { label ?? id }

    static func == (lhs: VersionDoc, rhs: VersionDoc) -> Bool {
        lhs.id == rhs.id && lhs.op == rhs.op && lhs.parts == rhs.parts
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Groups consecutive versions made by one chat prompt.
struct TurnRef: Codable, Hashable {
    var id: String
    var prompt: String?
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
