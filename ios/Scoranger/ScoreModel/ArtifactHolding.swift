import Foundation

/// Which artifacts this device keeps, which it fetches, and over what.
///
/// A version's bytes are the expensive part of the library and the cheap part
/// to be wrong about: one measured arrangement holds 29 MusicXML versions
/// totalling 16 MB, and a book on the owner's device is 52 MB on its own
/// (design/FIREBASE.md §1.2). The version LIST is documents and always present,
/// so history stays complete and browsable offline even when the bytes are not
/// there; what is not held is a row with a download affordance, never an error
/// and never a blank page.
///
/// Everything here is pure: it decides, it does not transfer.
enum ArtifactHolding {

    /// What an artifact IS, which decides how carelessly it may be moved.
    enum Kind: Equatable {
        /// A version of an arrangement. Text, compresses about 24:1.
        case notation
        /// A scan filed as an arrangement. A few pages; does not compress.
        case pdf
        /// A reference work arrangements are taken out of. Tens of megabytes,
        /// and the highest rights risk in the library (§8).
        case book
    }

    /// One artifact as the policy sees it.
    struct Artifact: Equatable {
        let key: String
        let kind: Kind
        let bytes: Int
        /// The version this score currently opens at.
        var isLatest: Bool = false
        /// `AppState.pinnedVersion`: the reader chose this one deliberately.
        var isPinned: Bool = false
        var lastOpened: Date?
        /// In a setlist the reader marked "keep this offline".
        var inOfflineSetlist: Bool = false
        /// The bytes exist on the server too. FALSE means this device holds
        /// the only copy that exists anywhere.
        var isPushed: Bool = true
        /// Downloaded, as opposed to a row with a download affordance.
        var isHeld: Bool = true
    }

    /// Why an artifact is kept. Nil means it is a candidate for eviction.
    enum Reason: Equatable {
        /// Nowhere else. Evicting this is data loss, not cache management.
        case notPushed
        case offlineSetlist
        case pinned
        case latest
        case openedRecently
    }

    /// How long an artifact the reader opened stays held after they close it.
    static let recentDays = 30

    /// In descending order of how much the answer matters.
    ///
    /// `notPushed` is first for the reason §5.4 gives it a test of its own: an
    /// artifact that has not been pushed is the only copy that exists, and the
    /// check is easy to forget precisely because every other reason here is
    /// about convenience and this one is about loss.
    static func reasonToHold(_ artifact: Artifact, now: Date = Date()) -> Reason? {
        if !artifact.isPushed { return .notPushed }
        if artifact.inOfflineSetlist { return .offlineSetlist }
        if artifact.isPinned { return .pinned }
        if artifact.isLatest { return .latest }
        if let opened = artifact.lastOpened,
           now.timeIntervalSince(opened) <= Double(recentDays) * 86_400 {
            return .openedRecently
        }
        return nil
    }

    /// What a device should have on disk without being asked (§5.1).
    static func shouldFetch(_ artifact: Artifact, now: Date = Date()) -> Bool {
        // A book is the one thing that is never fetched on a policy: it is one
        // enormous file, it is reference material rather than work, and its
        // owner turns it on per book (`books/{bookUid}.syncEnabled`, off by
        // default).
        if artifact.kind == .book { return false }
        switch reasonToHold(artifact, now: now) {
        case .none, .some(.notPushed): return false
        default: return true
        }
    }

    /// What to delete to get back under a budget, least recently opened first.
    ///
    /// Returns the artifacts to remove, in the order to remove them, and stops
    /// as soon as the total fits. An empty result means either it already fits
    /// or everything left is held for a reason.
    static func evictionPlan(_ artifacts: [Artifact],
                             budget: Int,
                             now: Date = Date()) -> [Artifact] {
        let held = artifacts.filter(\.isHeld)
        var total = held.reduce(0) { $0 + $1.bytes }
        guard total > budget else { return [] }

        let evictable = held
            .filter { reasonToHold($0, now: now) == nil }
            .sorted {
                let (a, b) = ($0.lastOpened ?? .distantPast, $1.lastOpened ?? .distantPast)
                return a == b ? $0.key < $1.key : a < b
            }

        var plan: [Artifact] = []
        for artifact in evictable where total > budget {
            plan.append(artifact)
            total -= artifact.bytes
        }
        return plan
    }

    // -- what may cross which connection (§5.2) ----------------------------

    enum Connection: Equatable { case none, cellular, wifi }

    /// Three tiers, one setting.
    enum Tier: Equatable {
        /// Documents and ink. Kilobytes; they go over anything.
        case anyConnection
        /// Notation artifacts. Wi-Fi by default, cellular on explicit request.
        case wifiUnlessAsked
        /// Books and large scans. Wi-Fi only, and never on a policy: a 52 MB
        /// book must not begin downloading because someone opened the library
        /// on a train.
        case wifiOnly
    }

    /// A PDF arrangement above this is treated as a book would be.
    static let largeArtifactBytes = 8 * 1024 * 1024

    static func tier(for artifact: Artifact) -> Tier {
        switch artifact.kind {
        case .book: return .wifiOnly
        case .pdf:  return artifact.bytes >= largeArtifactBytes ? .wifiOnly : .wifiUnlessAsked
        case .notation: return .wifiUnlessAsked
        }
    }

    /// `allowCellular` is the one control a reader sees ("download scores over
    /// cellular", off by default). `asked` is a reader tapping the download
    /// affordance on a particular thing, which beats the setting -- they are
    /// looking at what they asked for and they know what they are on.
    static func mayTransfer(_ tier: Tier,
                            over connection: Connection,
                            allowCellular: Bool,
                            asked: Bool = false) -> Bool {
        switch connection {
        case .none:
            return false
        case .wifi:
            return true
        case .cellular:
            switch tier {
            case .anyConnection:    return true
            case .wifiUnlessAsked:  return allowCellular || asked
            case .wifiOnly:         return false
            }
        }
    }
}
