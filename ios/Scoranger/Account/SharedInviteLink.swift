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

    /// The invitation id in something a person PASTED.
    ///
    /// The second iPad's way in when the link does not arrive AS a link.
    /// `message(setlistName:email:inviteId:)` wraps the URL in two sentences,
    /// and a custom scheme is not a thing Messages turns into something
    /// tappable -- so what reaches the invitee is prose with a URL sitting in
    /// the middle of it, and the only move available to them is to copy the
    /// whole bubble.
    ///
    /// Permissive, deliberately, and in the opposite direction from
    /// `inviteId(in:)`. That one guards a door every AirDropped file comes
    /// through and must recognise an invitation positively. This one is
    /// reached only by somebody who pressed a button that says they are
    /// pasting an invitation, so nothing else is competing for the text. A
    /// wrong id costs one refusal from `claimInvite`, which is the only thing
    /// that can settle the question anyway; a strict read that rejects the id
    /// somebody is actually holding costs them the only way in.
    static func inviteId(inPastedText text: String) -> String? {
        if let start = text.range(of: "\(scheme)://\(host)", options: .caseInsensitive) {
            let token = text[start.lowerBound...].prefix { !$0.isWhitespace }
            if let url = URL(string: String(token)), let id = inviteId(in: url) {
                return id
            }
        }
        // Somebody who copied the id alone, which is what a person does when
        // the link will not survive the app it is being sent through.
        let bare = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bare.isEmpty, bare.count <= 128,
              !bare.contains(where: \.isWhitespace), !bare.contains("/")
        else { return nil }
        return bare
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
