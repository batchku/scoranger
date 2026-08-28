import Foundation

// `AppTab` is gone with the tab bar (§4C). There is one place -- My Library --
// so where the user is no longer needs a model: a score is open or it is not,
// and X returns to the library because there is nowhere else to return to.

/// Which half of My Library is showing.
enum LibrarySegment: String, CaseIterable, Equatable {
    case pieces, setlists
    var title: String { self == .pieces ? "Pieces" : "Setlists" }
}

/// How the library is ordered.
///
/// The A–Z rail is shown ONLY under `.name`: under any other sort the letters
/// would not agree with the order of the rows, so it would be pointing at
/// nothing. It hides rather than lies (§4.2).
enum LibrarySort: String, CaseIterable, Equatable {
    case name, composer, recent, arrangements

    var label: String {
        switch self {
        case .name:         return "name"
        case .composer:     return "composer"
        case .recent:       return "recently changed"
        case .arrangements: return "arrangement count"
        }
    }

    var showsAlphabetRail: Bool { self == .name }
}

/// Derived filters -- computed from what the library already knows, not from a
/// tag store. Real tags need an engine change and are not in this release (§7).
enum LibraryFilter: String, CaseIterable, Equatable {
    case unfiled, omrDrafts, hasSources, inASetlist

    var label: String {
        switch self {
        case .unfiled:    return "unfiled"
        case .omrDrafts:  return "OMR drafts"
        case .hasSources: return "has sources"
        case .inASetlist: return "in a setlist"
        }
    }
}

/// What the Pencil means right now.
///
/// The whole of §6 rests on this: the Pencil does exactly ONE thing per mode,
/// and the mode is stated in the top bar. Page turning and lassoing cannot be
/// told apart by timing or distance -- they are the same gesture -- so they are
/// separated by mode instead of by a guess.
enum ScoreMode: String, CaseIterable, Equatable {
    /// Pencil selects music.
    case read
    /// Pencil inks.
    case edit
    /// Pencil turns pages; selection and ink are off, which is what frees it.
    case performance

    var title: String {
        switch self {
        case .read:        return "Read"
        case .edit:        return "Edit"
        case .performance: return "Performance"
        }
    }

    /// What the top bar says the Pencil is for.
    var pencilMeaning: String {
        switch self {
        case .read:        return "Pencil: select"
        case .edit:        return "Pencil: ink"
        case .performance: return "Pencil: turn"
        }
    }
}
