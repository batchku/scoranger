import Foundation

/// A document value, as far as sync cares.
///
/// Deliberately small: the documents in question are score, piece, setlist and
/// book records -- names, credits, tags, orderings, timestamps. Nothing nested
/// beyond a list of strings, so nothing here pretends to merge a tree.
enum SyncValue: Equatable {
    case text(String)
    case number(Double)
    case flag(Bool)
    case list([SyncValue])
    case none

    var isNone: Bool { self == .none }
}

typealias SyncDocument = [String: SyncValue]

/// How two copies of one document become one, stated as rules a person could
/// predict (design/FIREBASE.md §7).
///
/// The rules this implements, and what each one is protecting:
///
/// **Field by field, last writer wins per field** (rule 3). A rename on one
/// device and a re-file on another are different fields and both survive.
/// The sync layer sends only the fields that changed -- `updateData`, never
/// `setData` with a whole document -- because a whole-document write silently
/// reverts every field the sender happened to have an older copy of.
///
/// **A delete beats a concurrent edit, and a tombstone is forever** (rule 4).
/// Locally a delete is two-phase and `sweep()` reclaims the row; remotely the
/// document keeps its `deletedAt` and loses its fields, or a device that was
/// offline during the delete pushes the score back up on reconnect. Deleted
/// things returning from the dead is the most alarming sync bug a user can
/// meet, so it is the one rule here that is not symmetric.
///
/// **A field this device still owes keeps its local value.** Whoever pushes
/// last wins, and this device has not pushed yet, so it is going to win -- and
/// showing the reader a value that is about to be overwritten by their own
/// pending write is a flicker, not information. Every other field takes the
/// remote value.
///
/// Nothing here is announced to the user. The winner is what is on screen, and
/// telling someone their rename lost trains them to dismiss sync notices, which
/// is how they come to dismiss the one that matters (rule 7). Forks are the
/// exception, and forks are `VersionGraph`'s business.
enum SyncMerge {

    /// The field the engine writes when a document is deleted.
    static let tombstone = "deleted_at"

    static func isDeleted(_ doc: SyncDocument) -> Bool {
        guard let mark = doc[tombstone] else { return false }
        return !mark.isNone
    }

    /// What changed since the server last saw this document.
    ///
    /// A field that was REMOVED counts as changed: it has to be sent, or the
    /// server keeps a value the device no longer has. It arrives as `.none`,
    /// which is what the sync layer turns into a field delete.
    static func changedFields(from acknowledged: SyncDocument,
                              to current: SyncDocument) -> Set<String> {
        var changed: Set<String> = []
        for (key, value) in current where acknowledged[key] != value {
            changed.insert(key)
        }
        for key in acknowledged.keys where current[key] == nil {
            changed.insert(key)
        }
        return changed
    }

    /// The payload for an `updateData`: only what changed, never the whole
    /// document.
    static func update(from acknowledged: SyncDocument,
                       to current: SyncDocument) -> SyncDocument {
        var payload: SyncDocument = [:]
        for key in changedFields(from: acknowledged, to: current) {
            payload[key] = current[key] ?? SyncValue.none
        }
        return payload
    }

    /// Fold an incoming remote document into the local one.
    ///
    /// `owed` is the set of fields this device has changed and not yet pushed.
    static func apply(remote: SyncDocument,
                      onto local: SyncDocument,
                      owed: Set<String> = []) -> SyncDocument {
        // A tombstone on either side wins, whatever anyone was editing, and it
        // keeps nothing but the mark and the identity. Rebuilding the fields
        // from the survivor's copy is how a deleted score comes back.
        if isDeleted(remote) || isDeleted(local) {
            var grave: SyncDocument = [:]
            for key in ["id", "slug", "uid"] {
                if let value = remote[key] ?? local[key] { grave[key] = value }
            }
            grave[tombstone] = remote[tombstone] ?? local[tombstone]
            return grave
        }
        var merged = local
        for (key, value) in remote where !owed.contains(key) {
            merged[key] = value
        }
        // A field the remote no longer has was deleted there. Drop it here too,
        // unless this device is the one still holding an unpushed value for it.
        for key in local.keys where remote[key] == nil && !owed.contains(key) {
            merged.removeValue(forKey: key)
        }
        return merged
    }

    /// A local edit and a remote edit to the SAME field, with neither pushed:
    /// which value a reader will end up with once both have been sent.
    ///
    /// Not used to decide anything -- the server decides, by arrival order --
    /// but the app has to be able to say what it is about to show, and this is
    /// that answer in one place rather than assumed in three.
    static func winner(local: SyncValue, remote: SyncValue, localIsOwed: Bool) -> SyncValue {
        localIsOwed ? local : remote
    }
}
