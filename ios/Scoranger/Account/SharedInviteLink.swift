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

    /// The domain the AASA is served from.
    ///
    /// Firebase Hosting's default site for the project, which already existed
    /// and needed no domain purchase and no DNS: `apple-app-site-association`
    /// is live at `/.well-known/`, over HTTPS, 200, `application/json`, with
    /// no redirect -- all four of which Apple requires.
    static let webHost = "scoranger.web.app"

    /// THE LINK TO SEND. An https universal link.
    ///
    /// **This is what makes SMS work, and it is the whole reason it exists.**
    /// Messages and Mail do not linkify a custom scheme, so
    /// `scoranger://invite?id=…` arrived as dead text -- the reader could only
    /// copy the message and paste it, which is a step nobody should need. An
    /// https URL they render as tappable, and the AASA makes the tap open the
    /// app rather than a browser.
    static func webURL(inviteId: String) -> URL? {
        guard !inviteId.isEmpty, !inviteId.contains("/") else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = webHost
        components.path = "/invite/" + inviteId
        return components.url
    }

    /// The custom-scheme form, KEPT as a fallback.
    ///
    /// Universal links do not resolve everywhere -- a link pasted into a
    /// context that strips the association, or an AirDrop of a file rather
    /// than a URL -- and this still works there. It is no longer what gets
    /// shared.
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
        // The universal link first, since it is the one people will send.
        // Matched on host AND path shape, so an https link to any other page
        // on the same site is not mistaken for an invitation.
        if url.scheme?.lowercased() == "https",
           url.host?.lowercased() == webHost {
            let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            guard parts.count == 2, parts[0] == "invite" else { return nil }
            return sane(String(parts[1]))
        }
        guard url.scheme?.lowercased() == scheme else { return nil }
        guard url.host?.lowercased() == host else { return nil }
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems else { return nil }
        guard let raw = items.first(where: { $0.name == "id" })?.value else { return nil }
        return sane(raw)
    }

    /// One rule for what an id may be, used by both link forms.
    ///
    /// A document id, not a path: a value with a slash in it would address a
    /// different collection.
    private static func sane(_ raw: String) -> String? {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
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
        // Both link forms, and the https one FIRST because it is what
        // `message(setlistName:email:inviteId:)` actually sends. Looking only
        // for the custom scheme was a real break: the day the message became
        // an https universal link, pasting the message stopped working and
        // nothing but a test said so.
        for prefix in ["https://\(webHost)/invite/", "\(scheme)://\(host)"] {
            guard let start = text.range(of: prefix, options: .caseInsensitive)
            else { continue }
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
        // The https form: this text is going into Messages or Mail.
        let link = webURL(inviteId: inviteId)?.absoluteString ?? ""
        return """
        I've shared the set list "\(setlistName)" with you in Scoranger.

        Open this on your iPad, signed in as \(email):
        \(link)
        """
    }
}
