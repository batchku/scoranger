import CoreGraphics
import Foundation

/// The four library-level actions, and how their row is laid out (§4C).
///
/// They were four large coloured panels on Home, taking two thirds of a screen
/// for four occasional actions. Home is gone; these move into My Library as a
/// compact row of bordered buttons under the search field, deliberately quiet:
/// the lists are what the screen is for.
enum LibraryQuickAction: String, CaseIterable, Identifiable {
    case importScore, new, newSetlist, ask

    var id: String { rawValue }

    /// The panels' old order, kept so the muscle memory survives the move.
    static let ordered: [LibraryQuickAction] = [.importScore, .new, .newSetlist, .ask]

    /// Identifiers move with the actions. The `home-*` ids retire with Home,
    /// and `library-add` with the `+` that used to offer the same two things.
    var identifier: String {
        switch self {
        case .importScore: return "library-import"
        case .new:         return "library-new"
        case .newSetlist:  return "library-new-setlist"
        case .ask:         return "library-ask"
        }
    }

    var glyph: String {
        switch self {
        case .importScore: return "arrow.down.to.line"
        case .new:         return "square"
        case .newSetlist:  return "line.3.horizontal"
        case .ask:         return "bubble.left"
        }
    }

    var title: String {
        switch self {
        case .importScore: return "Import"
        case .new:         return "New"
        case .newSetlist:  return "New set list"
        case .ask:         return "Ask"
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

/// The last arrangement opened, so `Ask` has something to open (§4C).
///
/// This is what is left of `RecentSetlists`. The library IS the list of
/// everything, and recency there is a sort rather than a remembered set, so the
/// only recency the app still keeps is the one thing the engine cannot tell it:
/// which arrangement was last on screen.
enum LastOpened {
    private static let key = "lastOpenedArrangement"

    static var arrangement: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    /// What `Ask` would open, or nil when there is nothing to ask about.
    ///
    /// Nil when nothing has been opened, and nil when what was opened has since
    /// been deleted -- an Ask that opens a slug the manifest no longer has is
    /// a button that does nothing. Ask is then DISABLED rather than hidden, so
    /// the row does not re-flow under a finger.
    static func askTarget(lastOpened: String?, known: [String]) -> String? {
        guard let lastOpened, known.contains(lastOpened) else { return nil }
        return lastOpened
    }
}
