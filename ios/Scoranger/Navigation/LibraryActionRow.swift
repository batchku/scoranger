import CoreGraphics
import Foundation

/// The four library-level actions, and how their row is laid out (§4C).
///
/// They were four large coloured panels on Home, taking two thirds of a screen
/// for four occasional actions. Home is gone; these move into My Library as a
/// compact row of bordered buttons under the search field, deliberately quiet:
/// the lists are what the screen is for.
enum LibraryQuickAction: String, CaseIterable, Identifiable {
    case importScore, importFolder, importBook, new, newSetlist

    var id: String { rawValue }

    /// The panels' old order, kept so the muscle memory survives the move --
    /// less Ask, which Ali had removed (#47): the score's own Ask button is
    /// where a question about an arrangement belongs, and the library's copy
    /// was a fourth button that spent most of its life dimmed.
    static let ordered: [LibraryQuickAction] = [.importScore, .importFolder,
                                                .importBook, .new, .newSetlist]

    /// The two verbs these five actions actually are (§14.2). Three flavours
    /// of Import and two of New, which is why five permanent buttons was
    /// always a lot of toolbar for what they are.
    static let imports: [LibraryQuickAction] = [.importScore, .importFolder,
                                                .importBook]
    static let creations: [LibraryQuickAction] = [.new, .newSetlist]

    /// How the action names itself INSIDE its band, where there is room for a
    /// word and no glyph to lean on. "Import" is the button above it, so the
    /// band says what KIND -- Score, Folder, Book -- rather than repeating the
    /// verb three times.
    var bandTitle: String {
        switch self {
        case .importScore:  return "Score"
        case .importFolder: return "Folder"
        case .importBook:   return "Book"
        case .new:          return "Arrangement"
        case .newSetlist:   return "Set list"
        }
    }

    /// Identifiers move with the actions. The `home-*` ids retire with Home,
    /// and `library-add` with the `+` that used to offer the same two things.
    /// `library-import-folder`, `library-import-book` and
    /// `library-new-setlist` keep the identifiers they had -- §14.3 says so in
    /// terms, and everything that addressed them goes on working.
    ///
    /// The other two changed, and had to: `importScore` was `library-import`
    /// and `new` was `library-new`, which are now the two VERB buttons on the
    /// row. Two elements with one identifier is a test that taps whichever
    /// SwiftUI happened to put first -- so the band's own items say which kind
    /// they are, in the same shape as their siblings.
    var identifier: String {
        switch self {
        case .importScore:  return "library-import-score"
        case .importFolder: return "library-import-folder"
        case .importBook:   return "library-import-book"
        case .new:          return "library-new-arrangement"
        case .newSetlist:   return "library-new-setlist"
        }
    }

    var glyph: String {
        switch self {
        case .importScore:  return "arrow.down.to.line"
        case .importFolder: return "folder"
        case .importBook:   return "books.vertical"
        case .new:         return "square"
        case .newSetlist:  return "line.3.horizontal"
        }
    }

    var title: String {
        switch self {
        // Short, because the row now holds five. "Import" keeps the label it
        // has always had -- the two new ones sit beside it under their own
        // glyphs (a folder, a stack of books), which is what says what they
        // take. Thirteen characters would not fit the button.
        case .importScore:  return "Import"
        case .importFolder: return "Folder"
        case .importBook:   return "Book"
        case .new:         return "New"
        case .newSetlist:  return "New set list"
        }
    }
}

/// The two verbs the row's left cluster collapses to (§14.3).
enum LibraryVerb: String, CaseIterable, Identifiable {
    case importing, creating

    var id: String { rawValue }

    /// `library-import` and `library-new` keep the identifiers the two
    /// single-purpose buttons had: they still open the same work, one tap
    /// further in, and everything that addressed them goes on working.
    var identifier: String {
        switch self {
        case .importing: return "library-import"
        case .creating:  return "library-new"
        }
    }

    var title: String {
        switch self {
        case .importing: return "Import"
        case .creating:  return "New"
        }
    }

    var glyph: String {
        switch self {
        case .importing: return "arrow.down.to.line"
        case .creating:  return "plus"
        }
    }
}

enum LibraryActionRow {
    /// 32pt controls with 6pt above and below.
    static let height: CGFloat = 44
    static let buttonHeight: CGFloat = 32
    /// Within a cluster; the clusters are held apart by `clusterGap` at least.
    static let gap: CGFloat = 8
    static let clusterGap: CGFloat = 16
    /// Between the search field above and the first row below.
    static let spaceAboveRow: CGFloat = 12
    static let spaceBelowRow: CGFloat = 16
    static let sidePadding: CGFloat = 20
    static let buttonPadding: CGFloat = 10

    /// Below this the labels do not fit beside the list controls, so the left
    /// cluster becomes icons. Sort keeps its value -- it is the one control
    /// whose label is an ANSWER rather than a name.
    static let compactBelow: CGFloat = 700

    static func isCompact(width: CGFloat) -> Bool {
        width > 0 && width < compactBelow
    }
}

// `LastOpened` lived here: the one piece of "recent" the app still kept, so
// the library's Ask button had something to open. Ask is gone from the library
// (#47) and nothing else read it, so it is gone too rather than left behind as
// a store nobody consults.
