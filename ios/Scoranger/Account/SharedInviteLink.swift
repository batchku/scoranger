import Foundation

/// The link that carries an invitation.
///
/// An invitation is a Firestore document, and the client cannot go looking for
/// its own: the deployed rules refuse `list` on `invites/` outright, because a
/// listable invite collection is a way to enumerate other people's addresses.
/// So the invitee has to be TOLD the document's id, and this is how -- a link
/// sent by whatever the inviter already uses to reach them.
///
/// **The link is not the permission.** It names an invitation addressed to one
/// verified email address, and `claimInvite` refuses it from anybody else
/// (design/FIREBASE.md §8.2 guard rail 1: an invitation is to an account,
/// never a link). Somebody who intercepts one gets a document id they cannot
/// use. That is what lets the link travel over Messages without weakening the
/// membership model -- and it is also why this type never carries a token.
enum SharedInviteLink {

    static let scheme = "scoranger"
    static let host = "invite"

    static func url(inviteId: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "id", value: inviteId)]
        return components.url
    }

    /// The invitation id in a URL, or nil if this is not an invitation link.
    ///
    /// Deliberately strict. `onOpenURL` receives every kind of thing the app
    /// can be handed -- a `.scorbundle` from AirDrop, a PDF, a sign-in
    /// callback -- and anything this does not positively recognise has to fall
    /// through to the file path unchanged.
    static func inviteId(in url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        guard url.host?.lowercased() == host else { return nil }
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems else { return nil }
        guard let raw = items.first(where: { $0.name == "id" })?.value else { return nil }
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // A document id, not a path: a value with a slash in it would address
        // a different collection.
        guard !id.isEmpty, !id.contains("/"), id.count <= 128 else { return nil }
        return id
    }

    /// What the inviter sends. The address is in it so the person receiving it
    /// knows which of their addresses to sign in with -- the one mismatch that
    /// otherwise reads as a broken link.
    static func message(setlistName: String, email: String, inviteId: String) -> String {
        let link = url(inviteId: inviteId)?.absoluteString ?? ""
        return """
        I've shared the set list "\(setlistName)" with you in Scoranger.

        Open this on your iPad, signed in as \(email):
        \(link)
        """
    }
}
