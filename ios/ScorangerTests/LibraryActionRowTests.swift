import CoreGraphics
import XCTest

/// §4C: Home is gone and its four actions move into My Library as a compact
/// row. What can be checked without a screen is the row's contract -- what is
/// in it, in what order, under which identifiers, and when Ask can be used.
final class LibraryActionRowTests: XCTestCase {

    /// Three ways in, then the two ways to make something: a file, a whole
    /// exported folder, and a book to take arrangements out of.
    func testTheRowCarriesEveryActionInThePanelsOldOrder() {
        XCTAssertEqual(LibraryQuickAction.ordered,
                       [.importScore, .importPhoto, .importFolder,
                        .importBook, .new, .newSetlist])
        XCTAssertEqual(LibraryQuickAction.ordered.count,
                       LibraryQuickAction.allCases.count,
                       "an action exists that the row does not show")
    }

    /// The ids move with the actions; `home-*` and `library-add` retire.
    ///
    /// Three of the five kept the identifier they had -- §14.3 says so in
    /// terms. The other two had to change: `importScore` was `library-import`
    /// and `new` was `library-new`, and those two names now belong to the VERB
    /// buttons on the row. Two elements under one identifier is a test that
    /// taps whichever SwiftUI listed first, so the band's items say which kind
    /// they are, in the same shape as their siblings.
    func testTheIdentifiersAreTheLibrarysNotHomes() {
        XCTAssertEqual(LibraryQuickAction.ordered.map(\.identifier),
                       ["library-import-score", "library-import-photo",
                        "library-import-folder", "library-import-book",
                        "library-new-arrangement", "library-new-setlist"])
        XCTAssertFalse(LibraryQuickAction.allCases
            .contains { $0.identifier.hasPrefix("home-") })
    }

    /// And no action shares an identifier with the verb that opens its band,
    /// which is the collision the two renames above exist to prevent.
    func testNoActionCollidesWithItsVerb() {
        let verbs = Set(LibraryVerb.allCases.map(\.identifier))
        for action in LibraryQuickAction.allCases {
            XCTAssertFalse(verbs.contains(action.identifier),
                           "\(action) shares \(action.identifier) with a verb "
                           + "button, so a test cannot say which it tapped")
        }
        XCTAssertEqual(Set(LibraryQuickAction.allCases.map(\.identifier)).count,
                       LibraryQuickAction.allCases.count,
                       "two actions share an identifier")
    }

    func testEveryActionHasAGlyphAndAShortLabel() {
        for action in LibraryQuickAction.allCases {
            XCTAssertFalse(action.glyph.isEmpty, "\(action) has no glyph")
            XCTAssertFalse(action.title.isEmpty, "\(action) has no title")
            XCTAssertLessThanOrEqual(action.title.count, 12,
                                     "\(action)'s label is too long for a 32pt button")
        }
    }

    // MARK: the row's measurements (§4C)

    func testTheRowIsCompactOnANarrowScreenAndNotOnAWideOne() {
        XCTAssertTrue(LibraryActionRow.isCompact(width: 390))   // iPhone
        XCTAssertTrue(LibraryActionRow.isCompact(width: 699))
        XCTAssertFalse(LibraryActionRow.isCompact(width: 700))
        XCTAssertFalse(LibraryActionRow.isCompact(width: 1024)) // iPad
    }

    /// A width of zero is a view that has not been measured yet. It must not
    /// read as "very narrow" and flip the row to icons for one frame.
    func testAnUnmeasuredWidthIsNotTreatedAsNarrow() {
        XCTAssertFalse(LibraryActionRow.isCompact(width: 0))
    }

    func testTheButtonsFitTheRowWithRoomAboveAndBelow() {
        XCTAssertEqual(LibraryActionRow.height, 44)
        XCTAssertEqual(LibraryActionRow.buttonHeight, 32)
        XCTAssertEqual((LibraryActionRow.height - LibraryActionRow.buttonHeight) / 2, 6,
                       "6pt above and below, per the spec")
    }

    /// The buttons line up with the list rows' thumbnails, which is the whole
    /// reason the side padding is stated rather than chosen.
    func testItLinesUpWithTheListRows() {
        XCTAssertEqual(LibraryActionRow.sidePadding, Theme.Metric.s20)
    }

    func testTheClustersAreHeldFurtherApartThanTheirOwnButtons() {
        XCTAssertGreaterThan(LibraryActionRow.clusterGap, LibraryActionRow.gap)
    }

    // The Ask tests went with Ask (#47). It was removed from the library
    // action row -- the score's own Ask is where a question about an
    // arrangement belongs -- and `LastOpened`, which existed only to give it
    // something to open, went with it.
}
