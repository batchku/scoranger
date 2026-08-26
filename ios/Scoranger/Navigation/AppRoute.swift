import Foundation

/// Where the user is.
///
/// Browsing and reading are separate places now (NAVIGATION_SYSTEM.md §3): a
/// bottom tab bar holds Home and My Library, and a score opens OVER them as its
/// own place, closing back to wherever it came from. That "wherever" is the
/// reason this is a model rather than a pair of booleans -- the old screen kept
/// a library overlay, a canvas and a chat overlay alive at once and had nowhere
/// to put the answer to "what does X do?".
enum AppTab: String, CaseIterable, Equatable {
    case home
    case library
    /// Drawn, labelled and disabled, so the bar is not re-laid-out when sharing
    /// lands (§1). We have no accounts and no sharing.
    case shared

    var title: String {
        switch self {
        case .home:    return "Home"
        case .library: return "My Library"
        case .shared:  return "Shared · later"
        }
    }

    var glyph: String {
        switch self {
        case .home:    return "house"
        case .library: return "line.3.horizontal"
        case .shared:  return "arrow.left.arrow.right"
        }
    }

    var isAvailable: Bool { self != .shared }
}

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
