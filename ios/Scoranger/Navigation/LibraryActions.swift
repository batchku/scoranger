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
    case newArrangement, moveToPiece, addToSetlist, duplicate, delete

    /// Actions that only make sense on exactly one row. They grey to 42% rather
    /// than disappearing, so the bar never re-flows as the selection changes.
    var needsExactlyOne: Bool {
        switch self {
        case .newArrangement: return true
        case .moveToPiece, .addToSetlist, .duplicate, .delete: return false
        }
    }

    var isDestructive: Bool { self == .delete }

    var identifier: String {
        switch self {
        case .newArrangement: return "bar-new-arrangement"
        case .moveToPiece:    return "bar-move"
        case .addToSetlist:   return "bar-setlists"
        case .duplicate:      return "bar-duplicate"
        case .delete:         return "bar-delete"
        }
    }

    func title(count: Int, kind: LibrarySelectionKind) -> String {
        switch self {
        case .newArrangement: return "New arrangement"
        case .moveToPiece:    return "Move to piece…"
        case .addToSetlist:   return "Add to set list…"
        case .duplicate:      return "Duplicate"
        case .delete:
            guard count > 1 else { return "Delete" }
            return "Delete \(count) \(kind.plural)"
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
}

enum LibraryActions {

    /// The bar, in fixed order, destructive last.
    static func bar(for kind: LibrarySelectionKind) -> [LibraryAction] {
        switch kind {
        case .pieces:
            // a folder: rename it, put something in it, or throw it away
            return [.newArrangement, .delete]
        case .setlists:
            return [.delete]
        case .arrangements:
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
        return action.needsExactlyOne ? count == 1 : true
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
