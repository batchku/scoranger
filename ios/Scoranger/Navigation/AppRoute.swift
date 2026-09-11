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
        case .setlists: return "Set lists"
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
    case name, composer, recent, added, arrangements

    var label: String {
        switch self {
        case .name:         return "Name"
        case .composer:     return "Composer"
        case .recent:       return "Recently changed"
        case .added:        return "Date added"
        case .arrangements: return "Arrangement count"
        }
    }

    var buttonLabel: String { label.lowercased() }

    var shortButtonLabel: String {
        switch self {
        case .name:         return "name"
        case .composer:     return "composer"
        case .recent:       return "recent"
        case .added:        return "added"
        case .arrangements: return "count"
        }
    }

    var showsAlphabetRail: Bool { self == .name }
}

/// A library filter (design/DESIGN_SYSTEM.md [C9]): from the data model, in
/// five groups -- the type of the latest artifact, the composer, an
/// instrument read from the parts snapshot, a tag on the piece or the
/// arrangement, and the status the app computes. Several at once: filters in
/// one group widen (any of them), groups narrow (all of them).
enum LibraryFilter: Hashable {
    enum Status: String, CaseIterable, Hashable {
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
    enum Group: String, CaseIterable, Hashable {
        case type, composer, instrument, tag, status
        var title: String {
            switch self {
            case .type:       return "Type"
            case .composer:   return "Composer"
            case .instrument: return "Instrument"
            case .tag:        return "Tag"
            case .status:     return "Status"
            }
        }
    }

    case type(ArtifactHolding)
    case composer(String)
    case instrument(String)
    case tag(String)
    case status(Status)

    var group: Group {
        switch self {
        case .type:       return .type
        case .composer:   return .composer
        case .instrument: return .instrument
        case .tag:        return .tag
        case .status:     return .status
        }
    }

    var label: String {
        switch self {
        case .type(let holding):   return ArtifactTag.label(holding)
        case .composer(let name):  return name
        case .instrument(let name): return name
        case .tag(let tag):        return tag
        case .status(let status):  return status.label
        }
    }

    /// Stable, test-addressable: the four statuses keep their old
    /// identifiers ("filter-unfiled"); the data-model ones carry their value.
    var identifier: String {
        switch self {
        case .status(let status):  return "filter-\(status.rawValue)"
        case .type(let holding):   return "filter-type-\(ArtifactTag.label(holding).lowercased())"
        case .composer(let name):  return "filter-composer-\(LibraryFilter.slug(name))"
        case .instrument(let name): return "filter-instrument-\(LibraryFilter.slug(name))"
        case .tag(let tag):        return "filter-tag-\(LibraryFilter.slug(tag))"
        }
    }

    static func slug(_ text: String) -> String {
        text.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
    }

    /// The four statuses, as the older code and tests address them.
    static let unfiled = LibraryFilter.status(.unfiled)
    static let omrDrafts = LibraryFilter.status(.omrDrafts)
    static let hasSources = LibraryFilter.status(.hasSources)
    static let inASetlist = LibraryFilter.status(.inASetlist)
}

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
