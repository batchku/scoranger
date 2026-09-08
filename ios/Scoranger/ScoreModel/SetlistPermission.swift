import Foundation

/// Who may do what to a shared setlist.
///
/// design/FIREBASE.md §6.2, which principle 4 of §0 rewrote: *"anyone in the
/// playlist can add / reorder / share with others … But ONLY the owner who
/// created the setlist can DELETE the playlist."*
///
/// The flat model is deliberate. A band's running order is edited by the band,
/// and a permission system in which one person is the bottleneck on adding a
/// tune is one nobody will use. The single asymmetry is deletion, and it is the
/// right one: deleting is the only act that destroys other people's work --
/// everyone's ink, on every entry, at once.
///
/// **This type is the client's answer, and it is not the enforcement.** The
/// enforcement is the Firestore security rules, which are the only thing a
/// modified client cannot talk its way past. Both have to say the same thing,
/// and this exists so that what they must agree ON is written down once, in
/// something a test can read.
enum SetlistRole: String, Codable, CaseIterable, Equatable {
    case owner
    case member
    /// Defined, and not issued in 0.7 (§0.5).
    ///
    /// A dep player who marks their own part and cannot touch the running order
    /// is the first thing a working band asks for. The value exists from the
    /// start because adding a case to a stored field is cheap and introducing
    /// the field later is not.
    case reader
}

/// One thing a person might try to do.
enum SetlistAction: Equatable, CaseIterable {
    case read
    /// Draw on one's OWN layer. Nobody ever writes anyone else's (§6.3).
    case annotate
    case addEntry
    case reorder
    /// Move an entry to a different version of the same arrangement (§6.4).
    case repin
    /// Remove an entry somebody may not have added. §12.9.
    case removeEntry
    /// Add a person, which is what "share" means here: a share adds an account
    /// to the group, never a link (§8.2 guard rail 1).
    case invite
    /// Remove SOMEBODY ELSE. Leaving is `mayLeave` and is always allowed.
    case removeMember
    case deleteSetlist
}

enum SetlistPermission {

    /// The membership cap, enforced in the security rules and not here (§8.2
    /// guard rail 2).
    ///
    /// Twelve. A band, a section or a school ensemble is smaller, so the cap is
    /// not a limit anyone reaches legitimately -- it is what makes
    /// "distribution" hard to arrive at by accident. It matters MORE under the
    /// flat model, not less: owner-only invitation was itself a brake on
    /// growth, and member invitation removes it, so this is the only structural
    /// limit left between a band and a mailing list.
    /// The most people one shared set list may have, INCLUDING its owner.
    ///
    /// TWELVE. The owner's copyright posture is written as an inequality --
    /// "sharing is limited to groups of UNDER 12 people", "Enforce the
    /// <12-member cap" -- and he has since confirmed that the intent is
    /// **max 12 including the owner**: twelve people in a group, not eleven.
    ///
    /// Recorded because this went the other way first. Read cold, "<12" is
    /// eleven, and on a limit whose purpose is keeping private sharing from
    /// becoming distribution the stricter reading looked like the right
    /// default. It was not what he meant, and the deployed `claimInvite`
    /// already enforced 12 -- so the eleven reading would also have put this
    /// app permanently one below its own server.
    ///
    /// It is a COPYRIGHT limit and not a capacity limit, which is why it lives
    /// beside the permission model rather than in a config: the posture is
    /// "private small-group sharing, no distribution of copyrighted content,
    /// no bundled library", and this number is the "small group" half of it.
    static let membershipCap = 12

    /// Whether a member may remove an entry another member added. §12.9, OPEN.
    ///
    /// Recommended true, and set true here: a list anyone can add to and nobody
    /// can prune fills with mistakes, the act is attributed and the entry keeps
    /// its ink, so nothing is destroyed. One line to change if the owner
    /// decides otherwise, which is the reason it is a constant rather than
    /// scattered through the table below.
    static let membersMayRemoveEntries = true

    /// Whether a member may remove ANOTHER member. §12.9, OPEN.
    ///
    /// Recommended false, and set false here: removing a person is the mirror
    /// of deleting the setlist -- it ends someone's access to their own markup
    /// -- so it belongs with the one accountable person. Leaving is always
    /// allowed and is `mayLeave`.
    static let membersMayRemoveMembers = false

    /// The table.
    static func allows(_ role: SetlistRole, _ action: SetlistAction) -> Bool {
        switch role {
        case .owner:
            // The owner can do everything, including the two things nobody else
            // can: delete the setlist, and remove another person.
            return true
        case .member:
            switch action {
            case .read, .annotate, .addEntry, .reorder, .repin, .invite:
                return true
            case .removeEntry:
                return membersMayRemoveEntries
            case .removeMember:
                return membersMayRemoveMembers
            case .deleteSetlist:
                // Principle 4, the one asymmetry. Not a policy constant: this
                // is the rule, not a preference.
                return false
            }
        case .reader:
            // Reads and marks their own part. Touches nothing shared.
            switch action {
            case .read, .annotate: return true
            default:               return false
            }
        }
    }

    /// Anyone may leave, at any time, whatever their role.
    ///
    /// The owner is the exception, and not out of privilege: a setlist with no
    /// owner has nobody who can delete it, and §12.6 (also open) is where that
    /// is settled -- transfer to the longest-standing member rather than
    /// orphan the band's running order.
    static func mayLeave(_ role: SetlistRole) -> Bool { role != .owner }

    /// Whether one more person can be added.
    static func mayAdmit(currentCount: Int) -> Bool { currentCount < membershipCap }
}
