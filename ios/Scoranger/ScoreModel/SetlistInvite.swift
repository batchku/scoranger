import Foundation

/// An invitation to a shared setlist, addressed to a person who may not have an
/// account yet.
///
/// design/FIREBASE.md §4.2. Under owner-only invitation the owner could be
/// asked to wait until their bandmate had signed up. Under member invitation,
/// at a rehearsal, that is not a workable flow -- so an invite is written
/// against an email address rather than a user id, and claimed on the invitee's
/// next sign-in.
///
/// An unaccepted invite carries the setlist's NAME and nothing else about it, so
/// the invitee sees what they are joining before they join it. It must never be
/// a read grant: the entries, the ink and the artifacts stay unreachable until
/// membership exists (§4.2).
struct SetlistInvite: Codable, Equatable {
    let id: String
    let setlistId: String
    /// Shown to the invitee so they know what they are accepting. Not a grant.
    let setlistName: String
    /// Lower-cased and trimmed at construction. Addresses are compared, and
    /// "Ali@Example.com " and "ali@example.com" are one person.
    let emailLower: String
    let invitedBy: String
    let invitedAt: String
    var acceptedAt: String?
    var acceptedBy: String?
    var revokedAt: String?

    init(id: String, setlistId: String, setlistName: String, email: String,
         invitedBy: String, invitedAt: String) {
        self.id = id
        self.setlistId = setlistId
        self.setlistName = setlistName
        self.emailLower = SetlistInvite.normalise(email)
        self.invitedBy = invitedBy
        self.invitedAt = invitedAt
    }

    /// One spelling of an address, so a comparison cannot fail on case or a
    /// trailing space somebody's keyboard added.
    static func normalise(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Enough of an address to be worth sending. Deliberately NOT validation:
    /// the address is checked where it matters, against the claimant's verified
    /// token in `claimInvite`, and a client-side pattern that rejects a real
    /// address is worse than one that lets a typo through to a refusal. This
    /// only decides whether the Invite button is live.
    static func looksLikeAnAddress(_ email: String) -> Bool {
        let text = normalise(email)
        guard let at = text.firstIndex(of: "@"), text.filter({ $0 == "@" }).count == 1
        else { return false }
        let local = text[text.startIndex..<at]
        let domain = text[text.index(after: at)...]
        return !local.isEmpty && domain.contains(".")
            && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    enum State: Equatable {
        case pending
        case accepted
        case revoked
    }

    /// Revoked beats accepted when both are stamped.
    ///
    /// They should never both be set -- the server accepts or revokes, not both
    /// -- but if a race ever writes them, the safe reading is the one that
    /// grants nothing.
    var state: State {
        if revokedAt != nil { return .revoked }
        if acceptedAt != nil { return .accepted }
        return .pending
    }

    /// Why an invite cannot be claimed, or nil if it can.
    enum Refusal: Equatable {
        case alreadyAccepted
        case revoked
        case wrongAddress
        /// The setlist is full. §8.2 guard rail 2.
        case full
        /// Google SSO gives a verified address; Sign in with Apple's Hide My
        /// Email gives a relay one. An unverified address must not claim an
        /// invite, or the address is not an identity (§0.4, §12.10).
        case addressNotVerified

        var readable: String {
            switch self {
            case .alreadyAccepted:    return "That invitation has already been used."
            case .revoked:            return "That invitation was withdrawn."
            case .wrongAddress:       return "That invitation was sent to a different address."
            case .full:               return "That setlist is full."
            case .addressNotVerified: return "Confirm your email address first."
            }
        }
    }

    /// Whether this signed-in person may claim this invite.
    ///
    /// Pure, and deliberately says nothing about WHO performs the write. §12.11
    /// is still open on that: a callable Cloud Function is recommended, because
    /// membership is the one place §4.4 already names the server as
    /// authoritative and a rule that lets a client write itself into a
    /// membership map is the highest-consequence rule in the system to get
    /// subtly wrong. Either way the decision is this function, and either way
    /// the rules enforce it again.
    func refusal(claimedBy email: String, emailVerified: Bool,
                 currentMemberCount: Int) -> Refusal? {
        switch state {
        case .accepted: return .alreadyAccepted
        case .revoked:  return .revoked
        case .pending:  break
        }
        guard emailVerified else { return .addressNotVerified }
        guard SetlistInvite.normalise(email) == emailLower else { return .wrongAddress }
        guard SetlistPermission.mayAdmit(currentCount: currentMemberCount) else { return .full }
        return nil
    }
}
