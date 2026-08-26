import Foundation

/// Every screen you can push to (NAV_MODAL_FREE_0.4.2 §1, §3).
///
/// Nothing floats. A destination is a screen, and a choice happens in place --
/// so what used to be a sheet is a case here, and what used to be an alert is
/// an inline reveal that needs no route at all.
///
/// The score view is deliberately NOT in this enum. It is presented over the
/// tabs rather than pushed into a stack, which is what lets its page, zoom and
/// selection survive going back to the library and returning (§8.6).
enum Route: Hashable {
    /// A piece and its arrangements (§3.1).
    case piece(String)
    /// One arrangement's actions -- the per-item screen the row's ☰ opens (§3.2).
    case arrangement(String)
    /// Where an arrangement (or a selection) should be filed (§3.3).
    case moveToPiece([String])
    /// Which set lists an arrangement belongs to (§3.4).
    case setlistsFor(String)
    /// A set list, its running order, and what can be done to it (§3.5).
    case setlist(String)
    /// Which arrangements a set list holds.
    case addArrangements(String)
    /// The version history of an arrangement (§3.6).
    case versions(String)
    /// Parts and ranges.
    case parts(String)
    /// Title, composer, arranger, slug.
    case details(String)
    /// Where an import should land, asked before the file picker (item 9).
    case importDestination
    /// Settings, and its second layer (§6).
    case settings
    case settingsSection(String)

    /// What the back button says you are returning to. A back label that names
    /// the place is the difference between a stack you can trust and one you
    /// count taps out of.
    var backLabel: String {
        switch self {
        case .piece, .setlist, .importDestination, .settings:
            return "My library"
        case .arrangement, .moveToPiece, .setlistsFor, .addArrangements,
             .versions, .parts, .details, .settingsSection:
            return "Back"
        }
    }
}

/// Which of a row's actions decides how its ☰ behaves (§3.5).
///
/// > *if any action on the row needs a second screen, `☰` pushes; if they are
/// > all one tap, `☰` expands.*
///
/// Stated here so the rule is one line and testable, rather than a habit that
/// drifts between two view files.
enum RowMenuBehaviour: Equatable {
    /// Opens the item's own screen.
    case push
    /// Expands in place: every action is immediate and positional.
    case expand

    /// `needsATarget` means at least one action leads to a list of somewhere
    /// else to put this, or to more detail.
    static func forRow(needsATarget: Bool) -> RowMenuBehaviour {
        needsATarget ? .push : .expand
    }
}
