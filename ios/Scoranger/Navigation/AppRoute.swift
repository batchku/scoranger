import Foundation

// `AppTab` is gone with the tab bar (§4C). There is one place -- My Library --
// so where the user is no longer needs a model: a score is open or it is not,
// and X returns to the library because there is nowhere else to return to.

/// Which half of My Library is showing.
enum LibrarySegment: String, CaseIterable, Equatable {
    case pieces, setlists, books

    var title: String {
        switch self {
        case .pieces:   return "Pieces"
        case .setlists: return "Setlists"
        case .books:    return "Books"
        }
    }
}

/// How the library is ordered.
///
/// The A–Z rail is shown ONLY under `.name`: under any other sort the letters
/// would not agree with the order of the rows, so it would be pointing at
/// nothing. It hides rather than lies (§4.2).
enum LibrarySort: String, CaseIterable, Equatable {
    case name, composer, recent, arrangements

    /// Sentence case. These read as options in a revealed list, and a list of
    /// lowercase fragments reads as debug output rather than as choices.
    var label: String {
        switch self {
        case .name:         return "Name"
        case .composer:     return "Composer"
        case .recent:       return "Recently changed"
        case .arrangements: return "Arrangement count"
        }
    }

    /// How the Sort button says it, where the label is the ANSWER rather than
    /// the name of a choice: "Sort: name".
    var buttonLabel: String { label.lowercased() }

    /// The same answer, said shortly (§14.4 step 5).
    ///
    /// "Sort: recently changed" is 84pt wider than "Sort: name" on a phone,
    /// which is most of the reason the row overflowed under one sort and not
    /// another. This is the fifth thing the row gives up, and it is still the
    /// ANSWER -- which is why it comes before giving the value up entirely.
    var shortButtonLabel: String {
        switch self {
        case .name:         return "name"
        case .composer:     return "composer"
        case .recent:       return "recent"
        case .arrangements: return "count"
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
        case .unfiled:    return "Unfiled"
        case .omrDrafts:  return "OMR drafts"
        case .hasSources: return "Has sources"
        case .inASetlist: return "In a set list"
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
}
