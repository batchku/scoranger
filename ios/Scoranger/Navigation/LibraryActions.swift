import Foundation

/// What the Edit-mode action bar offers, and for what.
///
/// NAV_REVISION_0.4.1 §2.2. The verbs are NOT interchangeable, and the spec
/// says plainly that getting this wrong was the first draft's mistake, so it is
/// stated here where it can be tested rather than inferred from a view.
///
/// **A piece is a folder.** It cannot be moved into a piece, duplicated, or put
/// in a set list -- those verbs belong to arrangements, one level down. A set
/// list is a running order, so it can be renamed and deleted and nothing else.
/// Rename is deliberately absent. A name is edited by TAPPING IT on the
/// item's own screen -- the value is the control, so a button whose only job
/// was to make it editable has nothing left to do.
enum LibraryAction: String, CaseIterable, Equatable {
    case newArrangement, moveToPiece, addToSetlist, newSetlist, combine, duplicate, delete

    /// Actions that only make sense on exactly one row. They grey to 42% rather
    /// than disappearing, so the bar never re-flows as the selection changes.
    var needsExactlyOne: Bool {
        switch self {
        case .newArrangement: return true
        case .moveToPiece, .addToSetlist, .newSetlist, .combine,
             .duplicate, .delete: return false
        }
    }

    /// Actions that need SEVERAL rows. Combining one piece is not an
    /// operation, so the button greys until there is a second -- the same
    /// 42% the one-row verbs grey to, and for the same reason: the bar must
    /// not re-flow as the selection changes.
    var needsSeveral: Bool { self == .combine }

    var isDestructive: Bool { self == .delete }

    var identifier: String {
        switch self {
        case .newArrangement: return "bar-new-arrangement"
        case .moveToPiece:    return "bar-move"
        case .addToSetlist:   return "bar-setlists"
        case .newSetlist:     return "bar-new-setlist"
        case .combine:        return "bar-combine"
        case .duplicate:      return "bar-duplicate"
        case .delete:         return "bar-delete"
        }
    }

    func title(count: Int, kind: LibrarySelectionKind) -> String {
        switch self {
        case .newArrangement: return "New arrangement"
        case .moveToPiece:    return "Move to piece…"
        case .addToSetlist:   return "Add to set list…"
        case .newSetlist:     return "New set list"
        case .combine:        return "Combine…"
        case .duplicate:      return "Duplicate"
        case .delete:         return deleteTitle(count: count, kind: kind, counted: true)
        }
    }

    /// The short form the bar yields to when the full labels do not fit
    /// (REDESIGN_BRIEF_0.8 §7.3, rung 2): a noun, the selection supplying the
    /// verb. Delete keeps its count here; losing it is rung 3.
    func shortTitle(count: Int, kind: LibrarySelectionKind) -> String {
        switch self {
        case .newArrangement: return "Arrangement"
        case .moveToPiece:    return "Move…"
        case .addToSetlist:   return "Set list…"
        case .newSetlist:     return "Set list"
        case .combine:        return "Combine…"
        case .duplicate:      return "Duplicate"
        case .delete:         return deleteTitle(count: count, kind: kind, counted: true)
        }
    }

    /// Delete with or without its count. The count is the safety on the
    /// destructive verb, so it is the last thing the bar gives up.
    func deleteTitle(count: Int, kind: LibrarySelectionKind, counted: Bool) -> String {
        guard counted, count > 1 else { return "Delete" }
        return "Delete \(count) \(kind.plural)"
    }

    /// The whole sentence, for VoiceOver, whatever the visible label yielded
    /// to: "New set list from 5 pieces".
    func accessibilityTitle(count: Int, kind: LibrarySelectionKind) -> String {
        switch self {
        case .newSetlist:
            guard count > 1 else { return "New set list from this \(kind.singular)" }
            return "New set list from \(count) \(kind.plural)"
        case .combine:
            guard count > 1 else { return "Combine pieces" }
            return "Combine \(count) pieces into one"
        default:
            return title(count: count, kind: kind)
        }
    }
}

/// What kind of thing is selected. Mixed selections get the intersection of the
/// verbs, because a verb that is wrong for half of what is highlighted is worse
/// than one fewer button.
enum LibrarySelectionKind: Equatable {
    case pieces, setlists, arrangements, mixed

    var plural: String {
        switch self {
        case .pieces:       return "pieces"
        case .setlists:     return "set lists"
        case .arrangements: return "arrangements"
        case .mixed:        return "items"
        }
    }
    var singular: String {
        switch self {
        case .pieces:       return "piece"
        case .setlists:     return "set list"
        case .arrangements: return "arrangement"
        case .mixed:        return "item"
        }
    }
}

enum LibraryActions {

    /// The bar, in fixed order, destructive last.
    static func bar(for kind: LibrarySelectionKind) -> [LibraryAction] {
        switch kind {
        case .pieces:
            // a folder: rename it, put something in it, fold it into another
            // one, or throw it away. Combine is here because every import
            // mints a piece now, so two pieces for one tune is a thing a
            // reader will accumulate and has to be able to fix.
            return [.newArrangement, .newSetlist, .combine, .delete]
        case .setlists:
            return [.delete]
        case .arrangements:
            // Add to set list is already here, and it is a different verb with
            // a different target; a set list FROM a selection is the pieces
            // bar's (REDESIGN_BRIEF_0.8 §7.3).
            return [.moveToPiece, .addToSetlist, .duplicate, .delete]
        case .mixed:
            // only what is true of everything highlighted
            return [.delete]
        }
    }

    /// Whether an action can be used, given how many rows are selected. False
    /// means greyed, not absent.
    static func isEnabled(_ action: LibraryAction, count: Int) -> Bool {
        guard count > 0 else { return false }
        if action.needsExactlyOne { return count == 1 }
        if action.needsSeveral { return count > 1 }
        return true
    }

    /// What is highlighted, from what the library knows about each row.
    static func kind(of ids: Set<String>, pieces: Set<String>,
                     setlists: Set<String>) -> LibrarySelectionKind {
        guard !ids.isEmpty else { return .mixed }
        let kinds = Set(ids.map { id -> LibrarySelectionKind in
            if pieces.contains(id) { return .pieces }
            if setlists.contains(id) { return .setlists }
            return .arrangements
        })
        return kinds.count == 1 ? (kinds.first ?? .mixed) : .mixed
    }
}
