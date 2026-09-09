import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// An invitation as a square somebody can point a camera at.
///
/// design/FIREBASE.md §13.6. **A QR code here is the invite URL and nothing
/// else** -- the same `scoranger://invite?id=…` that `SharedInviteLink` builds,
/// encoded as pixels. So it inherits every property the link already has,
/// needs no server work, and grants nothing on its own: the invitation names
/// one verified email address and `claimInvite` refuses it from anybody else
/// (§8.2 guard rail 1).
///
/// Why it earns its place, given the link already exists: two iPads in a room
/// with no network cannot exchange a tapped link, because there is no
/// messaging app to tap it in. A camera pointed at a screen is a working data
/// channel with no infrastructure whatsoever -- which is exactly principle 6's
/// case, and why the owner named QR and offline sharing in the same breath.
enum InviteQRCode {

    /// The invitation, as a CoreImage image, or nil if it cannot be encoded.
    ///
    /// `correctionLevel` "M" -- 15% recoverable -- because this is read off a
    /// glossy screen at arm's length rather than printed on a box. "L" is
    /// smaller and fails on a reflection; "H" wastes a third of the modules on
    /// a payload that is already short.
    static func image(forInviteId inviteId: String) -> CIImage? {
        guard let url = SharedInviteLink.url(inviteId: inviteId) else { return nil }
        return image(forPayload: url.absoluteString)
    }

    static func image(forPayload payload: String) -> CIImage? {
        guard !payload.isEmpty, let data = payload.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        return filter.outputImage
    }

    /// The generator emits one pixel per module, so a raw render is about 25pt
    /// square and unreadable. Scaled with NEAREST-NEIGHBOUR rather than any
    /// smoothing filter: a QR code is a grid of hard squares, and an
    /// interpolated edge is a module a scanner has to guess at.
    static func scaled(_ image: CIImage, toWidth width: CGFloat) -> CIImage {
        let extent = image.extent
        guard extent.width > 0 else { return image }
        let factor = max(1, (width / extent.width).rounded(.down))
        return image.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
    }

    /// What a scanner read, if it is an invitation.
    ///
    /// Deliberately routed through `SharedInviteLink.inviteId(in:)` rather than
    /// trusting the payload: a QR code is untrusted input like any other, and
    /// anybody can print one. The strict URL parse is what decides, so a code
    /// carrying a file path, a web link or somebody else's scheme is refused by
    /// the same rule that refuses those from `onOpenURL`.
    static func inviteId(inScanned payload: String) -> String? {
        guard let url = URL(string: payload) else { return nil }
        return SharedInviteLink.inviteId(in: url)
    }
}
