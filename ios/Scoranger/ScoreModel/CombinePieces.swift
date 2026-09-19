import Foundation

/// What folding several pieces into one will do, worked out before it is done.
///
/// Combining is the curation step that makes "every import mints a piece"
/// safe. A reader who brings the same tune in twice -- two spellings, two
/// downloads, a MusicXML and an ABC -- gets two pieces for one piece of
/// music, and this is how they put it right.
///
/// It is PURE so the consequences can be stated on the screen before the
/// button is pressed, and tested without a view. The engine's
/// `combine-pieces` op makes the same four decisions; this one only describes
/// them, and `CombinePiecesTests` is what stops the two descriptions drifting.
///
/// THE FOUR, in the order a reader notices them:
///
///   THE NAME      the first piece in the list wins. Combining is not a
///                 rename, so nothing is invented; the survivor can be
///                 renamed afterwards by tapping its name.
///   THE NUMBERS   arrangements are numbered within their piece, so this
///                 renumbers. The survivor's own keep the numbers they had --
///                 #1 stays #1 -- and the absorbed ones append after them,
///                 piece by piece in the order listed.
///   THE CREDITS   a composer or arranger the survivor does not have is
///                 taken from the first absorbed piece that has one, and tags
///                 are unioned. Two records of one tune usually means one was
///                 credited and the other was not.
///   THE REST      the absorbed pieces stop existing. There is no undo for
///                 that, which is why the action leads to a screen that says
///                 so rather than to the action bar's delete-and-undo.
enum CombinePieces {

    struct Plan: Equatable {
        /// The piece that survives, slug and all.
        var survivor: String = ""
        var survivorName: String = ""
        /// The pieces folded into it, in the order they were listed.
        var absorbed: [String] = []
        var absorbedNames: [String] = []
        /// How many arrangements the survivor keeps from before.
        var kept: Int = 0
        /// How many arrive from the absorbed pieces.
        var arriving: Int = 0
        /// Credits the survivor does not have that an absorbed piece does.
        var composerFilled: String?
        var arrangerFilled: String?
        /// Tags the result will carry, survivor's first.
        var tags: [String] = []

        var total: Int { kept + arriving }
        /// Two pieces is the least that can be combined; one is not an
        /// operation and the bar greys the button rather than explaining.
        var isPossible: Bool { !survivor.isEmpty && !absorbed.isEmpty }

        /// What the screen says before the button, and what the notice says
        /// after it. Only facts that are TRUE of this selection -- a credit
        /// line appears only when a credit is actually being carried across.
        var consequences: [String] {
            guard isPossible else { return [] }
            var lines: [String] = []
            lines.append(
                absorbed.count == 1
                ? "\(absorbedNames[0]) is folded into \(survivorName) and stops existing."
                : "\(absorbed.count) pieces are folded into \(survivorName) and stop existing.")
            if arriving > 0 {
                let arrivals = arriving == 1 ? "1 arrangement" : "\(arriving) arrangements"
                lines.append(kept == 0
                             ? "\(arrivals) move across."
                             : "\(arrivals) join the \(kept) already there, "
                               + "numbered #\(kept + 1) onwards. The first \(kept) keep their numbers.")
            }
            if let composerFilled {
                lines.append("\(survivorName) takes the composer \(composerFilled).")
            }
            if let arrangerFilled {
                lines.append("\(survivorName) takes the credit \(arrangerFilled).")
            }
            lines.append("There is no undo.")
            return lines
        }
    }

    /// `pieces` in the order they are listed, already narrowed to the
    /// selection. The first is the survivor -- the same rule the engine
    /// applies when `--into` is not given.
    static func plan(pieces: [PieceDoc]) -> Plan {
        var plan = Plan()
        guard let first = pieces.first, pieces.count > 1 else { return plan }
        plan.survivor = first.slug
        plan.survivorName = first.name
        plan.kept = first.arrangements.count

        var tags = first.tags ?? []
        var seen = Set(tags.map { $0.lowercased() })
        for piece in pieces.dropFirst() {
            plan.absorbed.append(piece.slug)
            plan.absorbedNames.append(piece.name)
            plan.arriving += piece.arrangements.count
            if plan.composerFilled == nil, (first.composer ?? "").isEmpty,
               let composer = piece.composer, !composer.isEmpty {
                plan.composerFilled = composer
            }
            if plan.arrangerFilled == nil, (first.arranger ?? "").isEmpty,
               let arranger = piece.arranger, !arranger.isEmpty {
                plan.arrangerFilled = arranger
            }
            for tag in piece.tags ?? [] where !seen.contains(tag.lowercased()) {
                seen.insert(tag.lowercased())
                tags.append(tag)
            }
        }
        plan.tags = tags
        return plan
    }
}
