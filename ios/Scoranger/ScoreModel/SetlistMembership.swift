import Foundation

/// Which set lists an arrangement is in, and what a tap on the checklist means.
///
/// The "+" on the score bar (0.6.11 #1) opens a list of every set list with a
/// check against the ones this arrangement is already in. Pure, and here
/// rather than in the view, because the two decisions worth arguing about are
/// both decisions rather than drawing: what order the rows are in, and what a
/// tap does.
///
/// **The axis is the point.** `SetlistPickerView` already lists arrangements
/// for one set list -- set list to arrangements -- and is reached from the
/// library. This is the inverse: one arrangement, every set list, reached from
/// the score. The same two engine ops sit under both (`assign-setlist`,
/// `unassign-setlist`); only the axis the reader is thinking along differs.
/// Neither replaces the other, and the house rule about keeping the current
/// access path is satisfied by leaving the library's route exactly as it is.
enum SetlistMembership {

    /// One row of the checklist.
    struct Row: Identifiable, Equatable {
        let slug: String
        let name: String
        /// Whether the arrangement is already in this set list -- what the
        /// check draws, and what a tap inverts.
        let isMember: Bool
        /// How many arrangements it holds, so a reader can tell a full set
        /// from an empty one without opening it.
        let count: Int

        var id: String { slug }
    }

    /// What a tap on a row asks the engine to do.
    ///
    /// Named rather than a bare Bool: `addToSetlist` and `removeFromSetlist`
    /// are different calls, and a caller reading `tap(row)` should not have to
    /// remember which way round `true` meant.
    enum Action: Equatable {
        case add(setlist: String)
        case remove(setlist: String)
    }

    /// Every set list, with this arrangement's membership marked.
    ///
    /// **Sorted by name, and deliberately NOT members first.** A checklist
    /// ordered by the thing the checkbox changes reorders itself under the
    /// finger: check a box, the row jumps to the top, and the next tap lands
    /// on a different set list than the one aimed at. The order must not
    /// depend on the state the control edits. Case-insensitive, or a set list
    /// named in lower case sorts below every capitalised one and the list
    /// reads as shuffled.
    static func rows(for scoreSlug: String, in setlists: [SetlistDoc]) -> [Row] {
        setlists
            .map { setlist in
                Row(slug: setlist.slug, name: setlist.name,
                    isMember: setlist.arrangements.contains(scoreSlug),
                    count: setlist.arrangements.count)
            }
            .sorted {
                let left = $0.name.lowercased(), right = $1.name.lowercased()
                // The slug breaks a tie, so two set lists sharing a name have
                // a stable order rather than whichever the sort happened to
                // leave first.
                return left == right ? $0.slug < $1.slug : left < right
            }
    }

    /// What tapping a row does. Read off the row rather than recomputed, so
    /// the action always matches the check the reader was looking at.
    static func tap(_ row: Row) -> Action {
        row.isMember ? .remove(setlist: row.slug) : .add(setlist: row.slug)
    }

    /// What the "+" button reads out before it is opened.
    ///
    /// "No set lists yet" and "In no set lists" are different facts and are
    /// said differently: one means there is nothing to add to, the other means
    /// there is and this arrangement is in none of them.
    /// The value a "Set lists" ROW shows, as PieceScreen has always shown it.
    ///
    /// Named a single set list rather than counting to one: "Friday night" says
    /// more than "1 set list", and the row has the width for it. Shared because
    /// the score's Options screen shows the same row leading to the same screen
    /// (§16), and two spellings of one answer is how the two entrances would
    /// start disagreeing about what the reader is looking at.
    static func rowValue(for scoreSlug: String, in setlists: [SetlistDoc]) -> String {
        let holding = setlists.filter { $0.arrangements.contains(scoreSlug) }
        if holding.isEmpty { return "none" }
        return holding.count == 1 ? holding[0].name : "\(holding.count) set lists"
    }

    /// The same fact as a SENTENCE, for the "+" button's accessibility value,
    /// where it stands on its own with no row title in front of it.
    static func summary(for scoreSlug: String, in setlists: [SetlistDoc]) -> String {
        guard !setlists.isEmpty else { return "No set lists yet" }
        let count = setlists.filter { $0.arrangements.contains(scoreSlug) }.count
        switch count {
        case 0: return "In no set lists"
        case 1: return "In 1 set list"
        default: return "In \(count) set lists"
        }
    }
}
