import XCTest

/// The rules of a shared setlist: who may do what, who may join, and whose
/// markup is drawn.
///
/// design/FIREBASE.md §6.2, §6.3, §4.2, and principles 4 and 5 of §0. These are
/// the client's answers. The ENFORCEMENT is the Firestore security rules, which
/// do not exist yet and are the only thing a modified client cannot talk its way
/// past -- so what these tests hold is that the two will have one statement to
/// agree on, written down where a person can read it.
final class SetlistSharingTests: XCTestCase {

    // MARK: - principle 4: the flat model, and its one asymmetry

    /// The table, read out loud. Every cell of principle 4's grid.
    func testEveryRoleGetsExactlyThePowersPrinciple4GivesIt() {
        // A member is an editor: adding a tune must not need the owner.
        for action: SetlistAction in [.read, .annotate, .addEntry, .reorder,
                                      .repin, .invite] {
            XCTAssertTrue(SetlistPermission.allows(.member, action),
                          "a member cannot \(action) -- principle 4 says every "
                          + "member adds, reorders and shares")
            XCTAssertTrue(SetlistPermission.allows(.owner, action))
        }
        // A reader marks their own part and touches nothing shared.
        XCTAssertTrue(SetlistPermission.allows(.reader, .read))
        XCTAssertTrue(SetlistPermission.allows(.reader, .annotate))
        for action: SetlistAction in [.addEntry, .reorder, .repin, .removeEntry,
                                      .invite, .removeMember, .deleteSetlist] {
            XCTAssertFalse(SetlistPermission.allows(.reader, action),
                           "a reader can \(action), which is not a reader")
        }
    }

    /// THE asymmetry, and the reason it is the only one: deleting is the single
    /// act that destroys other people's work -- everyone's ink, on every entry,
    /// at once.
    func testOnlyTheOwnerCanDeleteTheSetlist() {
        XCTAssertTrue(SetlistPermission.allows(.owner, .deleteSetlist))
        XCTAssertFalse(SetlistPermission.allows(.member, .deleteSetlist),
                       "a member can delete the playlist -- principle 4 reserves "
                       + "that to the owner who created it")
        XCTAssertFalse(SetlistPermission.allows(.reader, .deleteSetlist))
    }

    /// Removing somebody else is the mirror of deleting, so it sits with the
    /// same person (§12.9, recommended and still open).
    func testRemovingAnotherPersonIsTheOwnersAlone() {
        XCTAssertTrue(SetlistPermission.allows(.owner, .removeMember))
        XCTAssertEqual(SetlistPermission.allows(.member, .removeMember),
                       SetlistPermission.membersMayRemoveMembers)
        XCTAssertFalse(SetlistPermission.membersMayRemoveMembers,
                       "the recommendation in §12.9 is that members do not "
                       + "remove each other; if that changed, say so here")
    }

    /// Anyone may walk away. The owner may not, because a setlist with no owner
    /// has nobody who can delete it -- §12.6, open.
    func testAnyoneButTheOwnerCanLeave() {
        XCTAssertTrue(SetlistPermission.mayLeave(.member))
        XCTAssertTrue(SetlistPermission.mayLeave(.reader))
        XCTAssertFalse(SetlistPermission.mayLeave(.owner))
    }

    // MARK: - the cap

    /// TWELVE INCLUDING THE OWNER, and the number is asserted literally.
    ///
    /// It matters more under the flat model than it did before: owner-only
    /// invitation was itself a brake on growth and member invitation removes it
    /// (§8.2 guard rail 2, §0.5). And it is a COPYRIGHT limit rather than a
    /// capacity one -- "private small-group sharing, no distribution of
    /// copyrighted content" -- so it is asserted as a value and not merely as a
    /// relation: a test that only checked `mayAdmit(cap) == false` would pass
    /// just as happily at 12, or at 200.
    func testTheTwelfthPersonFitsAndTheThirteenthDoesNot() {
        XCTAssertEqual(SetlistPermission.membershipCap, 12,
                       "max 12 including the owner, as confirmed; and it is what "
                       + "the deployed claimInvite already enforces")
        XCTAssertTrue(SetlistPermission.mayAdmit(currentCount: 0))
        XCTAssertTrue(SetlistPermission.mayAdmit(currentCount: 11),
                      "a group of eleven cannot add its twelfth")
        XCTAssertFalse(SetlistPermission.mayAdmit(currentCount: 12),
                       "twelve is the limit, so a thirteenth cannot be admitted")
        XCTAssertFalse(SetlistPermission.mayAdmit(currentCount: 40))
    }

    /// The client's cap and the server's are the same number.
    ///
    /// The Function is the ONLY thing that can enforce it -- the rules refuse
    /// every client write to the membership map, and only the Function counts
    /// members inside a transaction. So the constant in this app is advisory,
    /// and if the two ever disagree the server wins silently: a group would
    /// fill to the server's number while the UI kept offering to invite.
    /// Read out of the deployed source rather than restated.
    func testTheFunctionEnforcesTheSameCapThisAppShows() throws {
        let index = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ScorangerTests
            .deletingLastPathComponent()   // ios
            .deletingLastPathComponent()   // repo root
            .appending(path: "firebase/functions/index.js")
        let source = try String(contentsOf: index, encoding: .utf8)
        XCTAssertTrue(
            source.contains("MEMBERSHIP_CAP = \(SetlistPermission.membershipCap);"),
            "firebase/functions/index.js must enforce "
            + "\(SetlistPermission.membershipCap); the server is what actually "
            + "counts members, and a mismatch fills the group past the limit "
            + "this app advertises")
    }

    // MARK: - invitations

    private func invite(email: String = "aisha@example.com",
                        name: String = "Friday") -> SetlistInvite {
        SetlistInvite(id: "i1", setlistId: "s1", setlistName: name, email: email,
                      invitedBy: "u-owner", invitedAt: "2026-09-07T19:00:00Z")
    }

    func testAPendingInviteIsClaimedByTheAddressItWasSentTo() {
        let i = invite()
        XCTAssertEqual(i.state, .pending)
        XCTAssertNil(i.refusal(claimedBy: "aisha@example.com", emailVerified: true,
                               currentMemberCount: 3))
    }

    /// Case and stray whitespace are not identity. A keyboard's capital and a
    /// trailing space must not lock somebody out of their own invitation.
    func testAnAddressMatchesWhateverTheKeyboardDidToIt() {
        let i = invite(email: "  Aisha@Example.COM ")
        XCTAssertEqual(i.emailLower, "aisha@example.com")
        XCTAssertNil(i.refusal(claimedBy: "AISHA@example.com ", emailVerified: true,
                               currentMemberCount: 1))
    }

    func testTheWrongAddressIsRefused() {
        XCTAssertEqual(invite().refusal(claimedBy: "ben@example.com",
                                        emailVerified: true, currentMemberCount: 1),
                       .wrongAddress)
    }

    /// An unverified address is not an identity. Google SSO gives a verified
    /// one; without this an invite could be claimed by anyone who could type
    /// the address (§0.4).
    func testAnUnverifiedAddressCannotClaimAnything() {
        XCTAssertEqual(invite().refusal(claimedBy: "aisha@example.com",
                                        emailVerified: false, currentMemberCount: 1),
                       .addressNotVerified)
    }

    func testAnInviteIsGoodOnce() {
        var i = invite()
        i.acceptedAt = "2026-09-07T19:05:00Z"
        i.acceptedBy = "u-aisha"
        XCTAssertEqual(i.state, .accepted)
        XCTAssertEqual(i.refusal(claimedBy: "aisha@example.com", emailVerified: true,
                                 currentMemberCount: 3), .alreadyAccepted)
    }

    func testAWithdrawnInviteStaysWithdrawn() {
        var i = invite()
        i.revokedAt = "2026-09-07T19:05:00Z"
        XCTAssertEqual(i.refusal(claimedBy: "aisha@example.com", emailVerified: true,
                                 currentMemberCount: 3), .revoked)
    }

    /// Both stamped should never happen. If a race ever writes it, the reading
    /// that grants nothing is the safe one.
    func testWithdrawnBeatsAcceptedWhenBothAreSomehowStamped() {
        var i = invite()
        i.acceptedAt = "2026-09-07T19:05:00Z"
        i.revokedAt = "2026-09-07T19:06:00Z"
        XCTAssertEqual(i.state, .revoked)
    }

    func testTheCapRefusesTheThirteenthEvenWithAGoodInvite() {
        XCTAssertEqual(invite().refusal(claimedBy: "aisha@example.com",
                                        emailVerified: true, currentMemberCount: 12),
                       .full)
    }

    /// An unaccepted invite must not be a read grant: it carries the setlist's
    /// name so the invitee knows what they are joining, and nothing else.
    func testAnInviteCarriesTheNameAndNoContent() throws {
        let i = invite(name: "Friday at the Lescar")
        XCTAssertEqual(i.setlistName, "Friday at the Lescar")
        // If entries, artifacts or ink ever appear on this type, the invite has
        // become a read grant and §4.2's rule is broken. Asserted on the ENCODED
        // form, because that is what would actually be written to Firestore.
        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(i))
                as? [String: Any])
        let fields = Set(encoded.keys)
        for leak in ["entries", "storagePath", "pages", "ink", "members"] {
            XCTAssertFalse(fields.contains(leak),
                           "an unaccepted invite carries \(leak) -- it has become "
                           + "a read grant")
        }
        XCTAssertTrue(fields.contains("setlistName"))
    }

    // MARK: - principle 5: everyone annotates, and you can tell who

    private let band = ["u-aisha", "u-ben", "u-cara", "u-me"]

    func testMineShowsOnlyMine() {
        XCTAssertEqual(InkLayers.drawOrder(visibility: .mine, me: "u-me",
                                           participants: band), ["u-me"])
    }

    /// Everyone's marks, with the reader's own on TOP. Drawing your own ink
    /// underneath four other people's is the same as not having drawn it.
    func testEveryoneShowsEverybodyWithMineOnTop() {
        let order = InkLayers.drawOrder(visibility: .everyone, me: "u-me",
                                        participants: band)
        XCTAssertEqual(Set(order), Set(band), "somebody's layer is not drawn")
        XCTAssertEqual(order.last, "u-me", "my own marks are not on top")
        XCTAssertEqual(order.dropLast().map { $0 }, ["u-aisha", "u-ben", "u-cara"],
                       "the others are not in a stable order")
    }

    func testOnePersonShowsThatPerson() {
        XCTAssertEqual(InkLayers.drawOrder(visibility: .only("u-ben"), me: "u-me",
                                           participants: band), ["u-ben"])
        XCTAssertEqual(InkLayers.drawOrder(visibility: .only("u-nobody"),
                                           me: "u-me", participants: band), [],
                       "a layer was drawn for somebody who is not in the band")
    }

    /// A viewer who is not a participant sees the band's marks and has none of
    /// their own -- which is what a reader invited to look actually is.
    func testANonParticipantHasNoLayerOfTheirOwn() {
        XCTAssertEqual(InkLayers.drawOrder(visibility: .mine, me: "u-guest",
                                           participants: band), [])
        XCTAssertEqual(Set(InkLayers.drawOrder(visibility: .everyone, me: "u-guest",
                                               participants: band)), Set(band))
    }

    /// Every device colours the same person the same way, with no stored
    /// mapping and no coordination -- the participant list is the only input.
    func testColoursAgreeOnEveryDeviceWhateverOrderTheListArrivesIn() {
        let shuffled = band.shuffled()
        for user in band {
            XCTAssertEqual(InkLayers.colourSlot(for: user, participants: band, slots: 8),
                           InkLayers.colourSlot(for: user, participants: shuffled, slots: 8),
                           "\(user) changes colour when the list is reordered")
        }
        let slots = band.compactMap { InkLayers.colourSlot(for: $0, participants: band, slots: 8) }
        XCTAssertEqual(Set(slots).count, band.count, "two people share a colour")
        XCTAssertNil(InkLayers.colourSlot(for: "u-nobody", participants: band, slots: 8),
                     "a non-participant was given a colour that collides with a real one")
        XCTAssertNil(InkLayers.colourSlot(for: "u-me", participants: band, slots: 0))
    }

    /// The key addresses one page of one person's layer, the same way locally
    /// and remotely -- the lesson of the annotation re-key (§13.3).
    func testTheInkKeyNamesTheEntryThePersonAndThePage() {
        XCTAssertEqual(InkLayers.key(entry: "e1", user: "u-me", page: 3),
                       "e1/u-me/p3")
        XCTAssertNotEqual(InkLayers.key(entry: "e1", user: "u-me", page: 3),
                          InkLayers.key(entry: "e1", user: "u-ben", page: 3),
                          "two people's layers collide on one key")
    }
}
