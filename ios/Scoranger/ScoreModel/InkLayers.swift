import Foundation

/// Whose markup is drawn over a shared setlist entry, and in what colour.
///
/// design/FIREBASE.md §6.3 and §0.6. Principle 5: *"What's shared must include
/// ANNOTATIONS, and ALL setlist participants can annotate."*
///
/// **Per-participant layers, not one shared canvas.** Each participant owns one
/// ink document per entry, writes only their own and reads everyone's. That is
/// conflict-free by construction rather than by a CRDT that has to be right --
/// no two people ever write the same document, so there is no merge function
/// anywhere in it. It also answers "who wrote that?", which on a band's chart is
/// most of the question, and it lets a participant clear their own marks without
/// touching anybody else's. A merged canvas can express none of those.
///
/// The band layer of §6.3 -- one shared canvas as a grow-only stroke set -- stays
/// deferred. Its analysis is still in the document, because if these layers turn
/// out to be the wrong shape the alternative is already worked out.
enum InkLayers {

    /// What the reader has asked to see. Three states, not a checklist per
    /// person (§0.6).
    enum Visibility: Equatable {
        case mine
        case everyone
        /// One person's marks. Used for "show me what Aisha wrote".
        case only(String)
    }

    /// Which layers to draw, bottom to top, for a given viewer.
    ///
    /// `me` is drawn LAST, so a participant's own marks sit on top of everyone
    /// else's. Drawing your own ink underneath four other people's is the same
    /// as not having drawn it.
    ///
    /// Participants are ordered by id, not by join time or by name: the order
    /// has to be identical on every device, and an id is the only thing here
    /// that no rename or re-invite can change.
    static func drawOrder(visibility: Visibility, me: String,
                          participants: [String]) -> [String] {
        let others = participants.filter { $0 != me }.sorted()
        switch visibility {
        case .mine:
            return participants.contains(me) ? [me] : []
        case .everyone:
            return others + (participants.contains(me) ? [me] : [])
        case .only(let who):
            // Deliberately just that person, which is what "one person's marks"
            // says. Whether the viewer's OWN layer should stay visible
            // underneath is a UI question nobody has answered yet; it is not
            // decided here by accident.
            return participants.contains(who) ? [who] : []
        }
    }

    /// A stable colour slot per participant.
    ///
    /// Derived from the sorted participant ids, so every device assigns the
    /// same colour to the same person with no coordination and no stored
    /// mapping. A participant leaving DOES re-slot the others, which is the
    /// cost of deriving it; the alternative is a stored assignment that has to
    /// be migrated and can run out.
    ///
    /// Returns nil for somebody who is not a participant, rather than a slot
    /// that would collide with a real one.
    static func colourSlot(for user: String, participants: [String],
                           slots: Int) -> Int? {
        guard slots > 0, participants.contains(user) else { return nil }
        guard let index = participants.sorted().firstIndex(of: user) else { return nil }
        return index % slots
    }

    /// The colours a slot can be, as RGB.
    ///
    /// Here rather than in `Theme` because the mapping from a participant to a
    /// colour is a rule (`colourSlot`), and a rule and the values it indexes
    /// that live in different files drift. Kept as numbers so this file stays
    /// free of SwiftUI and testable in the pure model target.
    ///
    /// Six, against a cap of twelve people (§8.2): more than six distinguishable
    /// ink colours over engraved music is a fiction, and two people sharing one
    /// is honest where a twelfth indistinguishable shade would not be. The
    /// visibility control -- one person at a time -- is what actually separates
    /// them (§6.3).
    static let palette: [UInt32] = [
        0xCC5C2E,  // clay, the app's own accent: whoever made the set list
        0x2E6FCC,  // blue
        0x2E8B57,  // green
        0x8B2E8B,  // violet
        0xC79A1E,  // ochre
        0x1E8B8B,  // teal
    ]

    /// The colour for a slot, and clay for anything unslotted -- never a
    /// silent black, which is what a page's engraving already is.
    static func colour(slot: Int?) -> UInt32 {
        guard let slot, palette.indices.contains(slot) else { return palette[0] }
        return palette[slot]
    }

    /// The key one participant's ink is filed under, for one page of one entry.
    ///
    /// `entries/{entryId}/ink/{userId}` with the page inside the document
    /// (§4.2). The page is a component here rather than a field so the local
    /// store and the remote document address the same thing the same way -- the
    /// lesson of the annotation re-key, where a slug in the key meant markup
    /// could not travel (§13.3).
    static func key(entry: String, user: String, page: Int) -> String {
        "\(entry)/\(user)/p\(page)"
    }
}
