import Foundation

/// What a set list made from checked PIECES holds (REDESIGN_BRIEF_0.8 §7.4).
///
/// A set list holds arrangements and a piece is a folder, so the action has
/// to choose an arrangement per piece, and the choice is stated rather than
/// silent: arrangement #1 of each piece, in the order the pieces appear under
/// the list's current sort; a piece with no arrangements is skipped; nothing
/// is made if every piece was skipped. The notices say what was assumed, and
/// only when something was.
enum SetlistFromSelection {

    struct Plan: Equatable {
        var members: [String] = []
        var skipped: [String] = []
        var severalArrangements = 0

        var notices: [String] {
            var lines: [String] = []
            if severalArrangements > 0 {
                let pieces = severalArrangements == 1 ? "1 piece" : "\(severalArrangements) pieces"
                lines.append("Added #1 of \(pieces) with several arrangements. Change them in the set list.")
            }
            if !skipped.isEmpty {
                lines.append(skipped.count == 1
                             ? "\(skipped[0]) had no arrangements and was skipped."
                             : "\(skipped.count) pieces had no arrangements and were skipped.")
            }
            return lines
        }
    }

    /// `pieces` in the order they are listed, already narrowed to the selection.
    static func plan(pieces: [PieceDoc]) -> Plan {
        var plan = Plan()
        for piece in pieces {
            guard let first = piece.arrangements.first else {
                plan.skipped.append(piece.name)
                continue
            }
            plan.members.append(first)
            if piece.arrangements.count > 1 { plan.severalArrangements += 1 }
        }
        return plan
    }
}
