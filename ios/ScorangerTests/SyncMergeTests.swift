import XCTest

/// Two copies of one document becoming one (`SyncMerge`).
///
/// The rules are design/FIREBASE.md §7, and each test below is one of them.
/// The one that matters most is rule 4: a delete is a tombstone forever, or a
/// device that was offline during the delete pushes the score back up when it
/// reconnects, and deleted things returning from the dead is the most alarming
/// sync bug a user can meet.
final class SyncMergeTests: XCTestCase {

    private let acknowledged: SyncDocument = [
        "id": .text("morrisons-jig"),
        "uid": .text("01AAA"),
        "name": .text("Morrison's Jig"),
        "composer": .text("trad."),
        "piece": .text("morrisons-jig"),
    ]

    // -- rule 3: field by field -------------------------------------------

    /// A rename here and a re-file there are different fields, and both survive.
    func testARenameAndARefileBothSurvive() {
        var local = acknowledged
        local["name"] = .text("Morrison's Reel")          // this device renamed

        var remote = acknowledged
        remote["piece"] = .text("session-tunes")          // the other one re-filed

        let merged = SyncMerge.apply(remote: remote, onto: local, owed: ["name"])

        XCTAssertEqual(merged["name"], .text("Morrison's Reel"))
        XCTAssertEqual(merged["piece"], .text("session-tunes"))
    }

    /// Only what changed is sent. A whole-document write reverts every field
    /// the sender happened to hold an older copy of.
    func testOnlyTheChangedFieldsAreSent() {
        var current = acknowledged
        current["name"] = .text("Morrison's Reel")

        let payload = SyncMerge.update(from: acknowledged, to: current)

        XCTAssertEqual(payload.count, 1)
        XCTAssertEqual(payload["name"], .text("Morrison's Reel"))
    }

    /// A field the device dropped has to be sent, or the server keeps a value
    /// nobody has any more.
    func testARemovedFieldIsSentAsARemoval() {
        var current = acknowledged
        current.removeValue(forKey: "composer")

        let payload = SyncMerge.update(from: acknowledged, to: current)

        XCTAssertEqual(payload["composer"], SyncValue.none)
        XCTAssertEqual(SyncMerge.changedFields(from: acknowledged, to: current), ["composer"])
    }

    func testAnIdlePollSendsNothing() {
        XCTAssertTrue(SyncMerge.update(from: acknowledged, to: acknowledged).isEmpty)
    }

    /// A field this device still owes is not overwritten by an older remote
    /// value: the pending push is going to win, and showing the reader a value
    /// that is about to be replaced by their own edit is a flicker.
    func testAnUnpushedEditIsNotOverwrittenByTheRemoteCopy() {
        var local = acknowledged
        local["name"] = .text("Mine, not pushed yet")

        let merged = SyncMerge.apply(remote: acknowledged, onto: local, owed: ["name"])

        XCTAssertEqual(merged["name"], .text("Mine, not pushed yet"))
        XCTAssertEqual(SyncMerge.winner(local: .text("Mine, not pushed yet"),
                                        remote: .text("Theirs"),
                                        localIsOwed: true),
                       .text("Mine, not pushed yet"))
    }

    /// ...and a field it does not owe takes whatever the server says.
    func testAFieldThisDeviceDoesNotOweTakesTheRemoteValue() {
        var remote = acknowledged
        remote["composer"] = .text("James Morrison")

        let merged = SyncMerge.apply(remote: remote, onto: acknowledged)

        XCTAssertEqual(merged["composer"], .text("James Morrison"))
    }

    func testAFieldRemovedRemotelyGoesHereToo() {
        var remote = acknowledged
        remote.removeValue(forKey: "composer")

        let merged = SyncMerge.apply(remote: remote, onto: acknowledged)

        XCTAssertNil(merged["composer"])
    }

    func testAFieldRemovedRemotelyStaysWhileThisDeviceOwesIt() {
        var local = acknowledged
        local["composer"] = .text("trad. (Sligo)")
        var remote = acknowledged
        remote.removeValue(forKey: "composer")

        let merged = SyncMerge.apply(remote: remote, onto: local, owed: ["composer"])

        XCTAssertEqual(merged["composer"], .text("trad. (Sligo)"))
    }

    // -- rule 4: the tombstone --------------------------------------------

    /// The device that was offline during the delete has an edit to push. The
    /// delete still wins, in both directions.
    func testADeleteBeatsAConcurrentEdit() {
        var edited = acknowledged
        edited["name"] = .text("Renamed while it was being deleted")
        var deleted = acknowledged
        deleted[SyncMerge.tombstone] = .text("2026-08-30T12:00:00-07:00")

        let remoteDeleted = SyncMerge.apply(remote: deleted, onto: edited, owed: ["name"])
        let localDeleted = SyncMerge.apply(remote: edited, onto: deleted)

        XCTAssertTrue(SyncMerge.isDeleted(remoteDeleted))
        XCTAssertTrue(SyncMerge.isDeleted(localDeleted),
                      "a tombstone here is not resurrected by an edit from there")
    }

    /// A tombstone keeps its identity and nothing else. Rebuilding the fields
    /// from whichever copy still had them is how a deleted score comes back.
    func testATombstoneKeepsOnlyItsIdentity() {
        var deleted = acknowledged
        deleted[SyncMerge.tombstone] = .text("2026-08-30T12:00:00-07:00")

        let merged = SyncMerge.apply(remote: deleted, onto: acknowledged)

        XCTAssertEqual(merged["uid"], .text("01AAA"))
        XCTAssertEqual(merged["id"], .text("morrisons-jig"))
        XCTAssertNil(merged["name"])
        XCTAssertNil(merged["composer"])
    }

    /// The mark is what deletion means; an empty one is not a deletion.
    func testAnEmptyTombstoneFieldIsNotADeletion() {
        var doc = acknowledged
        doc[SyncMerge.tombstone] = SyncValue.none

        XCTAssertFalse(SyncMerge.isDeleted(doc))
        XCTAssertEqual(SyncMerge.apply(remote: doc, onto: acknowledged)["name"],
                       .text("Morrison's Jig"))
    }

    /// Ordering fields are lists, and a list is one field like any other:
    /// last writer wins on it, whole. §6.5 is where that stops being enough,
    /// and it is deliberately not generalised here.
    func testAnOrderingIsOneFieldAndMergesAsOne() {
        var local = acknowledged
        local["order"] = .list([.text("a"), .text("b")])
        var remote = acknowledged
        remote["order"] = .list([.text("b"), .text("a")])

        XCTAssertEqual(SyncMerge.apply(remote: remote, onto: local)["order"],
                       .list([.text("b"), .text("a")]))
        XCTAssertEqual(SyncMerge.apply(remote: remote, onto: local, owed: ["order"])["order"],
                       .list([.text("a"), .text("b")]))
    }
}
