import Foundation

/// Where this device put its copy of a shared set list entry.
///
/// A shared entry is a COPY of somebody's arrangement (design/FIREBASE.md
/// §4.3), and to read it this device downloads that copy and imports it into
/// the local library. From then on it is an ordinary arrangement: the same
/// reader, the same pencil, the same playback, offline forever. That is
/// principle 1 rather than a shortcut -- a parallel read-only viewer for cloud
/// scores would be a second reader to keep in step with the first, and the
/// first is the whole app.
///
/// The import assigns a NEW uid, because the score arrived from outside and
/// two devices importing the same file must not claim the same identity. So
/// which local arrangement is this entry's copy is a fact only this device
/// knows, and this is where it is written down.
///
/// **A device-local cache, deliberately.** It is not synced and it is not
/// authoritative: losing it costs one re-download, and there is nothing in it
/// another device could use.
struct SharedEntryCopies {

    private let defaults: UserDefaults
    private static let prefix = "shared-entry-copy."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func localSlug(forEntry entryId: String) -> String? {
        defaults.string(forKey: Self.prefix + entryId)
    }

    func remember(entryId: String, localSlug: String) {
        defaults.set(localSlug, forKey: Self.prefix + entryId)
    }

    func forget(entryId: String) {
        defaults.removeObject(forKey: Self.prefix + entryId)
    }

    /// The ink namespace for an entry, which is the ENTRY and not the local
    /// arrangement.
    ///
    /// Two reasons, and both matter:
    ///
    /// 1. It is the same string on every device, so a bandmate's marks land on
    ///    the page they were drawn on. The local uid differs per device and
    ///    would put everybody's ink under a key nobody else has.
    /// 2. It keeps the band's markup SEPARATE from my own notes on my own copy
    ///    of the same tune. Those are different things -- a private fingering
    ///    and a cue for the whole band -- and one key for both would publish
    ///    the private one.
    static func inkNamespace(entryId: String) -> String {
        "shared/\(entryId)"
    }

    /// Whether an ink key belongs to a shared entry rather than to a local
    /// arrangement. Used by the store's migration, which must leave these
    /// alone: they are already keyed on something global.
    static func isShared(namespace: String) -> Bool {
        namespace.hasPrefix("shared/")
    }

    /// Which shared entry and which page a `DrawingStore` key belongs to.
    ///
    /// The store's keys are `<namespace>/<versionId>/p<n>`, and for a shared
    /// entry the namespace is `shared/<entryId>`. This is what lets a save
    /// reach the right Firestore document without the pencil, the canvas or
    /// the view knowing anything about the cloud: the key already carries
    /// everything the push needs.
    ///
    /// Returns nil for a local arrangement's key, which is the common case and
    /// not a fault -- most saves in this app are never pushed anywhere.
    static func entryAndPage(forDrawingKey key: String) -> (entry: String, page: Int)? {
        let parts = key.split(separator: "/", omittingEmptySubsequences: false)
        // shared / <entryId> / <versionId> / p<n>
        guard parts.count == 4, parts[0] == "shared", !parts[1].isEmpty,
              parts[3].hasPrefix("p"),
              let page = Int(parts[3].dropFirst()) else { return nil }
        return (String(parts[1]), page)
    }
}
