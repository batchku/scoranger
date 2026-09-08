import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation

/// Setlists several people can open, add to and mark up.
///
/// design/FIREBASE.md §6, and the goal the whole integration exists for
/// (principle 2 of §0): *"SHARED PLAYLISTS (setlists) where anyone in the
/// playlist can ADD arrangements and REORDER them."*
///
/// **This is a cloud-authority system cached locally, and the library is the
/// opposite** (§4.4). Your own library is editable offline forever; a shared
/// setlist you cannot reach is read-only until you can, and says so. They are
/// different animals and this type does not pretend otherwise.
///
/// Everything it decides was decided already and is tested elsewhere:
/// `SetlistPermission` for who may do what, `SharedOrder` for the running
/// order, `InkLayers` for whose marks are drawn, `SetlistInvite` for who may
/// join. This is the wiring, and the security rules are what actually enforce
/// any of it.
@MainActor
final class SharedSetlists: ObservableObject {

    struct Setlist: Identifiable, Equatable {
        let id: String
        let name: String
        let ownerId: String
        let members: [String: String]
        var role: SetlistRole? {
            guard let uid = Auth.auth().currentUser?.uid,
                  let raw = members[uid] else { return nil }
            return SetlistRole(rawValue: raw)
        }
        var isOwner: Bool { ownerId == Auth.auth().currentUser?.uid }
    }

    struct Entry: Identifiable, Equatable {
        let id: String
        let title: String
        let composer: String?
        /// The fractional index. Sorting on this IS the running order (§6.5).
        let order: String
        let scoreUid: String
        let versionUid: String
        let storagePath: String?
        let addedBy: String
        /// Soft removal keeps the ink and can be undone (§6.2).
        let removedAt: Timestamp?
        var isRemoved: Bool { removedAt != nil }
    }

    @Published private(set) var setlists: [Setlist] = []
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var trouble: String?
    /// True while offline and showing a cached setlist. §5.3: reordering and
    /// adding are DISABLED with the reason shown, never a silent no-op.
    @Published private(set) var isStale = false

    private var setlistsListener: ListenerRegistration?
    private var entriesListener: ListenerRegistration?

    private var db: Firestore { Firestore.firestore() }
    private var storage: Storage { Storage.storage() }
    private var functions: Functions { Functions.functions(region: "us-west1") }
    private var uid: String? { Auth.auth().currentUser?.uid }

    // MARK: - what I am in

    /// Watch the flat index, not the setlists.
    ///
    /// "What setlists am I in" is one indexed query on `userId` because RULES
    /// ARE NOT FILTERS (§10.1): a query is all or nothing, so it must carry the
    /// same constraint the rule enforces. Listing `setlists` is refused
    /// outright by the deployed rules, and this is why.
    func watchMemberships() {
        guard let uid, FirebaseApp.app() != nil else { return }
        setlistsListener?.remove()
        setlistsListener = db.collection("memberships")
            .whereField("userId", isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error { self.trouble = error.localizedDescription; return }
                let ids = snapshot?.documents.compactMap {
                    $0.data()["setlistId"] as? String
                } ?? []
                Task { await self.loadSetlists(ids) }
            }
    }

    private func loadSetlists(_ ids: [String]) async {
        var found: [Setlist] = []
        for id in ids {
            // One document each, by id. Deliberately not a query: the rule
            // reads the membership map off the document in hand, which is the
            // one lookup §4.2 is built around.
            guard let snapshot = try? await db.collection("setlists").document(id).getDocument(),
                  let data = snapshot.data() else { continue }
            found.append(Setlist(id: id,
                                 name: data["name"] as? String ?? "Untitled",
                                 ownerId: data["ownerId"] as? String ?? "",
                                 members: data["members"] as? [String: String] ?? [:]))
        }
        setlists = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - one setlist, live

    /// A snapshot listener on the setlist that is OPEN, and nothing else.
    ///
    /// §5.1: a listener disconnected for more than thirty minutes is billed as
    /// a brand-new query, which for an app designed to be offline is the
    /// dominant cost. This one is small, genuinely live, and open for minutes
    /// rather than days. The library is never listened to.
    func open(_ setlistId: String) {
        guard FirebaseApp.app() != nil else { return }
        entriesListener?.remove()
        entriesListener = db.collection("setlists").document(setlistId)
            .collection("entries")
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                guard let self else { return }
                if let error { self.trouble = error.localizedDescription; return }
                self.isStale = snapshot?.metadata.isFromCache ?? false
                self.entries = (snapshot?.documents ?? []).map { document in
                    let data = document.data()
                    return Entry(id: document.documentID,
                                 title: data["title"] as? String ?? "Untitled",
                                 composer: data["composer"] as? String,
                                 order: data["order"] as? String ?? "",
                                 scoreUid: data["scoreUid"] as? String ?? "",
                                 versionUid: data["versionUid"] as? String ?? "",
                                 storagePath: data["storagePath"] as? String,
                                 addedBy: data["addedBy"] as? String ?? "",
                                 removedAt: data["removedAt"] as? Timestamp)
                }
                // The order is the KEY, sorted here. Sorting server-side would
                // need an index and buy nothing at a dozen entries.
                .filter { !$0.isRemoved }
                .sorted { $0.order < $1.order }
            }
    }

    func close() {
        entriesListener?.remove()
        entriesListener = nil
        entries = []
        isStale = false
    }

    // MARK: - making one

    func create(named name: String) async throws -> String {
        guard let uid else { throw Trouble.signedOut }
        let reference = db.collection("setlists").document()
        // Owner, sole member, and the rules check all three at creation so an
        // oversized setlist cannot be created in one write (§8.2).
        try await reference.setData([
            "name": name,
            "ownerId": uid,
            "members": [uid: SetlistRole.owner.rawValue],
            "memberIds": [uid],
            "createdAt": FieldValue.serverTimestamp(),
        ])
        return reference.documentID
    }

    /// Delete the whole setlist. The owner's alone -- the one act that destroys
    /// everybody's work at once (principle 4).
    func delete(_ setlist: Setlist) async throws {
        guard setlist.isOwner else { throw Trouble.notYours }
        try await db.collection("setlists").document(setlist.id).delete()
    }

    // MARK: - adding an arrangement

    /// Copy an arrangement of mine into a shared setlist.
    ///
    /// A COPY, not a reference (§4.3, and §12.13 as the owner settled it: his
    /// own purchased material shares as the real thing, to named people, capped
    /// at twelve). The bytes go to `shared/{setlistId}/{entryId}/` so a
    /// member's read permission is a property of the PATH and authorising it is
    /// one Firestore lookup -- not a chain into somebody's private library.
    ///
    /// The engine says what the entry carries (`share-payload`), because the
    /// engine is what knows which version is pinned.
    func addEntry(to setlistId: String, payload: [String: Any],
                  after previous: String?, before next: String?) async throws {
        guard let uid else { throw Trouble.signedOut }
        guard let localPath = payload["path"] as? String,
              let scoreUid = payload["scoreUid"] as? String,
              let versionUid = payload["versionUid"] as? String else {
            throw Trouble.unusablePayload
        }
        let entries = db.collection("setlists").document(setlistId).collection("entries")
        let entry = entries.document()

        // Uploaded BEFORE the document is written. A row pointing at bytes that
        // are not there yet is an entry that opens as a blank page, and the
        // reader cannot tell that from a broken one.
        let kind = payload["kind"] as? String ?? "notation"
        let name = kind == "pdf" ? "\(versionUid).pdf" : "\(versionUid).musicxml"
        let path = "shared/\(setlistId)/\(entry.documentID)/\(name)"
        _ = try await storage.reference(withPath: path)
            .putFileAsync(from: URL(fileURLWithPath: localPath))

        try await entry.setData([
            "title": payload["title"] as? String ?? "Untitled",
            "composer": payload["composer"] as? String as Any,
            "order": SharedOrder.between(previous, next),
            "scoreUid": scoreUid,
            "versionUid": versionUid,
            "versionLabel": payload["versionLabel"] as? String as Any,
            "mode": "copy",
            "provenance": payload["provenance"] as? String ?? "unknown",
            "storagePath": path,
            "bytes": payload["bytes"] as? Int ?? 0,
            "sha256": payload["sha256"] as? String as Any,
            "addedBy": uid,
            "addedAt": FieldValue.serverTimestamp(),
        ])
    }

    /// Move one entry. A one-field write to one document, which is what lets
    /// two people reorder at once without either losing a move (§6.5).
    ///
    /// Takes the neighbouring KEYS rather than the neighbouring entries, because
    /// which keys those are is a decision (`SharedOrder.neighbours`) and it is
    /// made and tested there.
    func move(_ entry: Entry, afterKey previous: String?, beforeKey next: String?,
              in setlistId: String) async throws {
        try await db.collection("setlists").document(setlistId)
            .collection("entries").document(entry.id)
            .updateData(["order": SharedOrder.between(previous, next)])
    }

    /// Soft, attributed, and undoable. Removing an entry never destroys ink.
    func remove(_ entry: Entry, in setlistId: String) async throws {
        guard let uid else { throw Trouble.signedOut }
        try await db.collection("setlists").document(setlistId)
            .collection("entries").document(entry.id)
            .updateData(["removedAt": FieldValue.serverTimestamp(), "removedBy": uid])
    }

    // MARK: - people

    /// Invite by email. Any member may (principle 4).
    ///
    /// The invite is a document addressed to an ADDRESS, because at a rehearsal
    /// "wait until your bandmate has signed up" is not a workable flow (§4.2).
    /// It carries the setlist's name and nothing else: the rules name the five
    /// allowed fields, so it cannot become a read grant.
    /// Returns the invitation's id, which is what the inviter has to send:
    /// the rules refuse `list` on `invites/`, so an invitee cannot find their
    /// own (`SharedInviteLink`).
    @discardableResult
    func invite(_ email: String, to setlist: Setlist) async throws -> String {
        guard let uid else { throw Trouble.signedOut }
        guard SetlistPermission.mayAdmit(currentCount: setlist.members.count) else {
            throw Trouble.full
        }
        let reference = db.collection("invites").document()
        try await reference.setData([
            "setlistId": setlist.id,
            "setlistName": setlist.name,
            "emailLower": SetlistInvite.normalise(email),
            "invitedBy": uid,
            "invitedAt": FieldValue.serverTimestamp(),
        ])
        return reference.documentID
    }

    /// Claim an invitation. Through the Function, because the rules refuse
    /// every client write to the membership map -- a client that could edit
    /// `members` could make itself the owner (§4.4, §12.11).
    func claim(inviteId: String) async throws -> String {
        let result = try await functions.httpsCallable("claimInvite")
            .call(["inviteId": inviteId])
        guard let data = result.data as? [String: Any],
              let setlistId = data["setlistId"] as? String else {
            throw Trouble.unusablePayload
        }
        return setlistId
    }

    func removeMember(_ userId: String, from setlistId: String) async throws {
        _ = try await functions.httpsCallable("removeMember")
            .call(["setlistId": setlistId, "userId": userId])
    }

    // MARK: - markup

    /// One page of my own layer. Nobody ever writes anybody else's, which is
    /// what makes the ink conflict-free with no merge function (§6.3).
    func writeInk(_ data: Data, entry: String, page: Int, in setlistId: String) async throws {
        guard let uid else { throw Trouble.signedOut }
        try await db.collection("setlists").document(setlistId)
            .collection("entries").document(entry)
            .collection("ink").document(uid)
            .setData(["layer": "personal",
                      "updatedAt": FieldValue.serverTimestamp(),
                      "pages": [String(page): data]], merge: true)
    }

    /// Everybody's layers for one entry, keyed by user.
    func readInk(entry: String, in setlistId: String) async throws -> [String: [Int: Data]] {
        let snapshot = try await db.collection("setlists").document(setlistId)
            .collection("entries").document(entry).collection("ink").getDocuments()
        var layers: [String: [Int: Data]] = [:]
        for document in snapshot.documents {
            let pages = document.data()["pages"] as? [String: Any] ?? [:]
            layers[document.documentID] = pages.reduce(into: [:]) { out, pair in
                if let page = Int(pair.key), let data = pair.value as? Data {
                    out[page] = data
                }
            }
        }
        return layers
    }

    /// Fetch an entry's music to a local file, once.
    func download(_ entry: Entry) async throws -> URL {
        guard let path = entry.storagePath else { throw Trouble.unusablePayload }
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "shared", directoryHint: .isDirectory)
            .appending(path: "\(entry.id)-\(URL(fileURLWithPath: path).lastPathComponent)")
        try? FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        _ = try await storage.reference(withPath: path).writeAsync(toFile: destination)
        return destination
    }

    enum Trouble: LocalizedError {
        case signedOut, notYours, full, unusablePayload

        var errorDescription: String? {
            switch self {
            case .signedOut:       return "Sign in to share setlists."
            case .notYours:        return "Only the person who made this setlist can delete it."
            case .full:            return "That setlist already has twelve people in it."
            case .unusablePayload: return "That arrangement could not be prepared for sharing."
            }
        }
    }
}
