import CoreGraphics
import XCTest

/// §4C: Home is gone and its four actions move into My Library as a compact
/// row. What can be checked without a screen is the row's contract -- what is
/// in it, in what order, under which identifiers, and when Ask can be used.
final class LibraryActionRowTests: XCTestCase {

    func testTheRowCarriesTheFourActionsInThePanelsOldOrder() {
        XCTAssertEqual(LibraryQuickAction.ordered,
                       [.importScore, .new, .newSetlist])
        XCTAssertEqual(LibraryQuickAction.ordered.count,
                       LibraryQuickAction.allCases.count,
                       "an action exists that the row does not show")
    }

    /// The ids move with the actions; `home-*` and `library-add` retire.
    func testTheIdentifiersAreTheLibrarysNotHomes() {
        XCTAssertEqual(LibraryQuickAction.ordered.map(\.identifier),
                       ["library-import", "library-new", "library-new-setlist"])
        XCTAssertFalse(LibraryQuickAction.allCases
            .contains { $0.identifier.hasPrefix("home-") })
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
