import Foundation

/// The version history as a GRAPH, because two devices can append to it at once.
///
/// Until stage 0 a version's key was `v{count + 1}`, so two devices arranging
/// the same piece offline both allocated `v031` and one of them had to lose
/// work a musician did. Keys are opaque now (`ids.new_id()`), which makes the
/// second child of a version REPRESENTABLE -- but representable is not the same
/// as handled, and this is what handles it.
///
/// design/FIREBASE.md §7 rule 2: two people arranging offline both keep their
/// work. Both children arrive, the arrangement has a branch, the app says so
/// ONCE, and `latest` resolves to the most recent with the other branch one tap
/// away. Rule 7 adds the reason it is said at all: a fork creates work that
/// would otherwise be invisible, which is the only sync outcome worth
/// interrupting anybody for.
///
/// Pure over the manifest: no engine, no network, no Firebase.
enum VersionGraph {

    /// One version, as much of it as a graph needs.
    struct Node: Equatable {
        let id: String
        let parent: String?
        /// The engine's ISO-8601 stamp, with its offset (`2026-08-31T20:01:21-07:00`).
        let time: String?
        /// What a person reads. Two forked versions can share one -- both are
        /// the eleventh version of something -- which is exactly why the label
        /// is not the identity.
        let label: String?

        init(id: String, parent: String? = nil, time: String? = nil, label: String? = nil) {
            self.id = id
            self.parent = parent
            self.time = time
            self.label = label
        }
    }

    /// A version that has more than one child: the point the history split.
    struct Fork: Equatable {
        let parent: String
        /// In the same order `latest` would rank them: newest first.
        let children: [String]
    }

    private static let stamps: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func moment(_ node: Node) -> Date {
        guard let time = node.time, let date = stamps.date(from: time) else { return .distantPast }
        return date
    }

    /// Newest first, ties broken by id.
    ///
    /// The tie-break is not decoration. Two versions made in the same second
    /// on two devices would otherwise sort differently on each of them, and
    /// `latest` -- which is what opens when you tap an arrangement -- would
    /// show a different page depending on which iPad you picked up.
    static func ranked(_ versions: [Node]) -> [Node] {
        versions.sorted {
            let (a, b) = (moment($0), moment($1))
            return a == b ? $0.id > $1.id : a > b
        }
    }

    /// What `latest` should point at. Nil for an empty history.
    static func latest(_ versions: [Node]) -> String? {
        ranked(versions).first?.id
    }

    /// Every place the history split, newest fork first.
    ///
    /// A version whose parent is not in the list is NOT a fork and is not
    /// dropped: documents arrive in whatever order the network delivers them,
    /// and a child that landed before its parent is an ordinary version that
    /// will look ordinary again in a moment. Announcing a fork there would
    /// train people to dismiss the notice (rule 7).
    static func forks(_ versions: [Node]) -> [Fork] {
        let known = Set(versions.map(\.id))
        var childrenOf: [String: [Node]] = [:]
        for v in versions {
            guard let parent = v.parent, known.contains(parent) else { continue }
            childrenOf[parent, default: []].append(v)
        }
        return childrenOf
            .filter { $0.value.count > 1 }
            .map { Fork(parent: $0.key, children: ranked($0.value).map(\.id)) }
            .sorted { lhs, rhs in
                let l = versions.first { $0.id == lhs.children[0] }
                let r = versions.first { $0.id == rhs.children[0] }
                let (a, b) = (l.map(moment) ?? .distantPast, r.map(moment) ?? .distantPast)
                return a == b ? lhs.parent > rhs.parent : a > b
            }
    }

    /// True when someone else's work is sitting in this history unseen.
    static func hasFork(_ versions: [Node]) -> Bool { !forks(versions).isEmpty }

    /// The other children of this version's parent: the branch one tap away.
    static func siblings(of id: String, in versions: [Node]) -> [String] {
        guard let node = versions.first(where: { $0.id == id }), let parent = node.parent else {
            return []
        }
        return ranked(versions.filter { $0.parent == parent && $0.id != id }).map(\.id)
    }

    /// Root-first path down to `id`. Empty when the id is not in the list.
    ///
    /// A cycle cannot arise from an append-only history, but a corrupt or
    /// half-delivered one could, so the walk stops when it revisits a version
    /// rather than hanging the app.
    static func lineage(of id: String, in versions: [Node]) -> [String] {
        let byId = Dictionary(versions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        guard byId[id] != nil else { return [] }
        var path: [String] = []
        var seen: Set<String> = []
        var cursor: String? = id
        while let current = cursor, !seen.contains(current), let node = byId[current] {
            path.append(current)
            seen.insert(current)
            cursor = node.parent
        }
        return path.reversed()
    }
}

extension VersionGraph.Node {
    /// From the manifest the app already polls.
    init(_ doc: VersionDoc) {
        self.init(id: doc.id, parent: doc.parent, time: doc.time, label: doc.label)
    }
}
