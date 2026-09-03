import XCTest

/// An empty segment must speak about ITSELF.
///
/// The reader picked a 52MB fake book, tapped Go, and landed on a Books screen
/// that read "No set lists yet" and offered "New set list". The copy was a
/// two-way choice -- pieces, or everything else -- and Books fell into the
/// else. So the one screen that had to explain what had just gone wrong
/// advertised an unrelated feature instead.
final class LibraryEmptyStateTests: XCTestCase {

    func testTheBooksSegmentTalksAboutBooks() {
        let empty = LibraryModel.emptyState(segment: .books)
        XCTAssertEqual(empty.title, "No books yet")
        XCTAssertTrue(empty.message.lowercased().contains("book"))
        XCTAssertEqual(empty.actionTitle, "Import book")
    }

    /// The regression itself: no set list may be mentioned anywhere on it.
    func testTheBooksSegmentNeverMentionsSetLists() {
        let empty = LibraryModel.emptyState(segment: .books)
        for text in [empty.title, empty.message, empty.actionTitle] {
            XCTAssertFalse(text.lowercased().contains("set list"),
                           "the Books empty state says \(text.debugDescription)")
        }
    }

    func testEachSegmentGetsItsOwnState() {
        let states = [LibrarySegment.pieces, .setlists, .books]
            .map { LibraryModel.emptyState(segment: $0) }
        XCTAssertEqual(Set(states.map(\.title)).count, 3)
        XCTAssertEqual(Set(states.map(\.actionTitle)).count, 3)
        XCTAssertEqual(Set(states.map(\.systemImage)).count, 3)
    }

    func testTheOtherTwoAreUnchanged() {
        XCTAssertEqual(LibraryModel.emptyState(segment: .pieces).title, "No music yet")
        XCTAssertEqual(LibraryModel.emptyState(segment: .setlists).title,
                       "No set lists yet")
    }
}
