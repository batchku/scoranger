import XCTest

/// The invitation link, and the ink palette a set list's people are told apart
/// by.
///
/// design/FIREBASE.md §4.2, §6.3, §8.2. Two things are being held here:
///
/// 1. `onOpenURL` is a single door for every kind of thing this app can be
///    handed -- a `.scorbundle` from AirDrop, a PDF, a photograph, Google's
///    sign-in callback -- and an invitation has to be recognised POSITIVELY,
///    with everything else falling through to the file path unchanged. A parser
///    that is loose here swallows an AirDropped arrangement.
/// 2. The link carries a document id and nothing else. It is not a token and it
///    is not a permission: guard rail 1 of §8.2 says an invitation is to an
///    account, never a link, and the value in this URL is useless to anybody
///    but the one verified address `claimInvite` will accept it from.
final class SharedInviteLinkTests: XCTestCase {

    // MARK: - a link this app made

    func testAnInvitationLinkCarriesTheInvitationsId() {
        let url = SharedInviteLink.url(inviteId: "abc123XYZ")
        XCTAssertNotNil(url)
        XCTAssertEqual(SharedInviteLink.inviteId(in: url!), "abc123XYZ")
    }

    func testTheLinkIsNotAToken() {
        // The whole query string, so a future field cannot be added without
        // this test noticing. Nothing signed, nothing secret, nothing about
        // the setlist's contents -- an unaccepted invitation must not be a
        // read grant, and a link that carried one would be.
        let url = SharedInviteLink.url(inviteId: "i1")!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.map(\.name), ["id"])
    }

    // MARK: - every other thing that comes through the same door

    func testAnAirDroppedBundleIsNotMistakenForAnInvitation() {
        let bundle = URL(fileURLWithPath: "/var/mobile/Inbox/Tuesday.scorbundle")
        XCTAssertNil(SharedInviteLink.inviteId(in: bundle),
                     "a file URL must fall through to the import path")
    }

    func testGooglesSignInCallbackIsNotMistakenForAnInvitation() {
        // The reversed client id scheme, which is the OTHER scheme this app
        // registers. Both arrive at the same `onOpenURL`.
        let callback = URL(string: "com.googleusercontent.apps.185895597142-x:"
                           + "/oauth2redirect?code=4/abc")!
        XCTAssertNil(SharedInviteLink.inviteId(in: callback))
    }

    func testAWebLinkIsNotMistakenForAnInvitation() {
        XCTAssertNil(SharedInviteLink.inviteId(in: URL(string: "https://invite/?id=x")!),
                     "the scheme is what decides, not the host")
    }

    func testOurSchemeWithSomeOtherHostIsRefused() {
        XCTAssertNil(SharedInviteLink.inviteId(in: URL(string: "scoranger://open?id=x")!))
    }

    func testTheSchemeIsMatchedCaseInsensitivelyBecauseAMailClientMayRewriteIt() {
        XCTAssertEqual(SharedInviteLink.inviteId(in: URL(string: "SCORANGER://INVITE?id=k9")!),
                       "k9")
    }

    // MARK: - a value that is not a document id

    func testAnIdWithAPathSeparatorIsRefused() {
        // `invites/x/../setlists/y` addresses a different collection. The
        // Function would refuse it, and refusing it here means the refusal is
        // not the only thing standing between a crafted link and a wrong read.
        XCTAssertNil(SharedInviteLink.inviteId(in: URL(string: "scoranger://invite?id=a%2Fb")!))
    }

    func testAnEmptyOrMissingIdIsRefused() {
        XCTAssertNil(SharedInviteLink.inviteId(in: URL(string: "scoranger://invite")!))
        XCTAssertNil(SharedInviteLink.inviteId(in: URL(string: "scoranger://invite?id=")!))
        XCTAssertNil(SharedInviteLink.inviteId(in: URL(string: "scoranger://invite?id=%20%20")!))
    }

    func testAnAbsurdlyLongIdIsRefused() {
        let long = String(repeating: "a", count: 500)
        XCTAssertNil(SharedInviteLink.inviteId(in:
            URL(string: "scoranger://invite?id=\(long)")!))
    }

    // MARK: - what the inviter sends

    func testTheMessageNamesTheSetlistTheAddressAndTheLink() {
        let text = SharedInviteLink.message(setlistName: "Tuesday at the club",
                                            email: "son@example.com",
                                            inviteId: "i7")
        XCTAssertTrue(text.contains("Tuesday at the club"))
        // The address is in it because a mismatch is the one failure that
        // reads as a broken link rather than as the wrong account (§0.4).
        XCTAssertTrue(text.contains("son@example.com"))
        XCTAssertTrue(text.contains("scoranger://invite?id=i7"))
    }

    // MARK: - enough of an address to be worth sending

    func testAnAddressWithoutAnAtOrADotIsNotWorthSending() {
        XCTAssertFalse(SetlistInvite.looksLikeAnAddress(""))
        XCTAssertFalse(SetlistInvite.looksLikeAnAddress("son"))
        XCTAssertFalse(SetlistInvite.looksLikeAnAddress("son@example"))
        XCTAssertFalse(SetlistInvite.looksLikeAnAddress("@example.com"))
        XCTAssertFalse(SetlistInvite.looksLikeAnAddress("a@b@example.com"))
    }

    func testAnOrdinaryAddressPassesIncludingTheAwkwardOnes() {
        for address in ["son@example.com", " Son@Example.COM ",
                        "a.b+tag@sub.example.co.uk", "x@e.io"] {
            XCTAssertTrue(SetlistInvite.looksLikeAnAddress(address), address)
        }
    }

    // MARK: - telling people's ink apart

    func testEveryColourSlotHasAColourAndTheyAreAllDifferent() {
        XCTAssertEqual(Set(InkLayers.palette).count, InkLayers.palette.count,
                       "two people would get the same ink")
    }

    func testAnUnslottedParticipantGetsTheAppsOwnColourRatherThanBlack() {
        // Black is what the engraving already is, so an unknown participant
        // drawn in it is invisible as a person.
        XCTAssertEqual(InkLayers.colour(slot: nil), InkLayers.palette[0])
        XCTAssertEqual(InkLayers.colour(slot: 99), InkLayers.palette[0])
    }

    func testColoursFollowTheSlotRuleSoTwoDevicesAgree() {
        let band = ["u-zoe", "u-ali", "u-son"]
        for person in band {
            let slot = InkLayers.colourSlot(for: person, participants: band,
                                            slots: InkLayers.palette.count)
            let shuffled = InkLayers.colourSlot(for: person,
                                                participants: band.reversed(),
                                                slots: InkLayers.palette.count)
            XCTAssertEqual(slot, shuffled,
                           "the slot is derived from the sorted ids, so the "
                           + "order a device happens to read them in cannot "
                           + "change anybody's colour")
            XCTAssertEqual(InkLayers.colour(slot: slot),
                           InkLayers.colour(slot: shuffled))
        }
    }

    // MARK: - an invitation that was pasted rather than tapped

    // The second iPad's way in. A custom scheme is not something Messages
    // turns into a tappable link, so what the invitee holds is the whole
    // message, and copying it has to work.

    func testTheWholeMessageTheAppSendsYieldsTheId() {
        let message = SharedInviteLink.message(setlistName: "Tuesday",
                                               email: "echo@example.com",
                                               inviteId: "inv_9")
        XCTAssertEqual(SharedInviteLink.inviteId(inPastedText: message), "inv_9")
    }

    func testTheLinkStopsAtTheWhitespaceAfterIt() {
        // The message puts prose on the line below the link. Reading to the
        // end of the string would take that with it.
        let pasted = """
        Open this on your iPad:
        scoranger://invite?id=inv_9
        See you Tuesday.
        """
        XCTAssertEqual(SharedInviteLink.inviteId(inPastedText: pasted), "inv_9")
    }

    func testTheIdAloneIsAccepted() {
        // What a person copies when the link will not survive the app it is
        // being sent through.
        XCTAssertEqual(SharedInviteLink.inviteId(inPastedText: "  inv_9\n"), "inv_9")
    }

    func testNothingOnTheClipboardIsNotAnInvitation() {
        XCTAssertNil(SharedInviteLink.inviteId(inPastedText: ""))
        XCTAssertNil(SharedInviteLink.inviteId(inPastedText: "   \n  "))
    }

    func testProseWithNoLinkInItIsNotAnInvitation() {
        XCTAssertNil(SharedInviteLink.inviteId(inPastedText: "see you tuesday"))
    }

    func testAPathIsNotAnId() {
        // `inviteId(in:)` refuses a slash because a value with one addresses a
        // different collection. The pasted reading has to refuse it too, or
        // the permissive path is a way around the strict one.
        XCTAssertNil(SharedInviteLink.inviteId(inPastedText: "invites/inv_9"))
    }
}
