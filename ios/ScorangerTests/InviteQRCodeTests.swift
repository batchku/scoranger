import CoreImage
import XCTest

/// The QR code carries the invitation, and a real scanner can read it back.
///
/// **These tests DECODE what they encode.** Asserting that
/// `image(forInviteId:)` returned non-nil would pass on a blank square, and a
/// blank square is exactly what a wrong correction level or a bad scale
/// produces -- something that looks like a QR code on screen and reads as
/// nothing through a lens. `CIDetector` is the same CoreImage machinery a
/// scanner uses, so a round trip through it is evidence rather than optimism.
final class InviteQRCodeTests: XCTestCase {

    /// What a camera would get out of the image.
    private func decode(_ image: CIImage) -> [String] {
        let detector = CIDetector(ofType: CIDetectorTypeQRCode,
                                  context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: image) as? [CIQRCodeFeature] ?? []
        return features.compactMap(\.messageString)
    }

    func testTheCodeDecodesBackToTheInvitationUrl() throws {
        let image = try XCTUnwrap(InviteQRCode.image(forInviteId: "inv_42"))
        let scanned = decode(InviteQRCode.scaled(image, toWidth: 240))
        XCTAssertEqual(scanned, ["scoranger://invite?id=inv_42"],
                       "a camera pointed at this must read the invitation URL")
    }

    /// The whole point: what comes off the lens resolves to the same id the
    /// inviter generated, through the same strict parse a tapped link uses.
    func testAScannedCodeResolvesToTheInviteId() throws {
        let image = try XCTUnwrap(InviteQRCode.image(forInviteId: "inv_42"))
        let payload = try XCTUnwrap(decode(InviteQRCode.scaled(image, toWidth: 240)).first)
        XCTAssertEqual(InviteQRCode.inviteId(inScanned: payload), "inv_42")
    }

    /// A long id still round-trips. Firestore document ids are 20 characters,
    /// and a code that only worked for short test values would fail on every
    /// real invitation.
    func testARealLengthFirestoreIdRoundTrips() throws {
        let id = "aBcDeFgHiJkLmNoPqRsT"          // 20 chars, as Firestore mints
        let image = try XCTUnwrap(InviteQRCode.image(forInviteId: id))
        let payload = try XCTUnwrap(decode(InviteQRCode.scaled(image, toWidth: 320)).first)
        XCTAssertEqual(InviteQRCode.inviteId(inScanned: payload), id)
    }

    // MARK: - scaling

    /// One pixel per module is unreadable, and the fix must not blur.
    func testTheCodeIsScaledUpAndStaysDecodable() throws {
        let raw = try XCTUnwrap(InviteQRCode.image(forInviteId: "inv_42"))
        XCTAssertLessThan(raw.extent.width, 60, "the generator emits one pixel per module")
        let big = InviteQRCode.scaled(raw, toWidth: 240)
        XCTAssertGreaterThanOrEqual(big.extent.width, 200)
        XCTAssertFalse(decode(big).isEmpty, "scaling must not destroy it")
    }

    func testScalingUsesWholeMultiplesSoModuleEdgesStaySharp() throws {
        let raw = try XCTUnwrap(InviteQRCode.image(forInviteId: "inv_42"))
        let big = InviteQRCode.scaled(raw, toWidth: 240)
        let factor = big.extent.width / raw.extent.width
        XCTAssertEqual(factor, factor.rounded(), accuracy: 0.0001,
                       "a fractional scale puts module edges between pixels, "
                       + "which is what a scanner then has to guess at")
    }

    // MARK: - a code is untrusted input

    /// Anybody can print a QR code, so what it carries goes through the same
    /// strict parse as a tapped link -- not a looser one.
    func testACodeCarryingSomethingElseIsRefused() {
        for payload in ["https://example.com/invite?id=inv_42",
                        "scoranger://open?id=inv_42",
                        "file:///var/mobile/Inbox/Tuesday.scorbundle",
                        "scoranger://invite?id=a%2Fb",
                        "inv_42",
                        ""] {
            XCTAssertNil(InviteQRCode.inviteId(inScanned: payload), payload)
        }
    }

    func testAnEmptyPayloadMakesNoImage() {
        XCTAssertNil(InviteQRCode.image(forPayload: ""))
    }
}
