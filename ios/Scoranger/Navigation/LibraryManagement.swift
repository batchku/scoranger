import SwiftUI

/// Where the old sidebar's management went (NAVIGATION_SYSTEM.md §8).
///
/// The sidebar carried rename, delete, filing, setlist membership, version
/// browsing and "add an arrangement to this piece" on expandable rows. The new
/// IA has no sidebar, so those did not move by themselves -- and a redesign
/// that quietly drops working features is a regression wearing new chrome.
/// Each one has a home here.
enum RowAction: Equatable {
    case open, versions, details, addToSetlist, delete, newArrangement
}
