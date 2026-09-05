import XCTest

/// What the "+" on the score bar offers, and what a tap on it means.
///
/// Ali, 0.6.11 #1: a "+" in the score top bar that adds the current
/// ARRANGEMENT to setlists, opening a checklist of setlists with checkboxes to
/// select and unselect membership.
///
/// The direction matters and is the whole reason this type exists.
/// `SetlistPickerView` already lists arrangements for ONE setlist -- setlist to
/// arrangements -- and it is reached from the library. This is the inverse:
/// one arrangement, every setlist, from the score. Same two engine ops
/// underneath (`assign-setlist`, `unassign-setlist`), opposite axis.
final class SetlistMembershipTests: XCTestCase {

    private func setlist(_ slug: String, _ name: String,
                         _ arrangements: [String]) -> SetlistDoc {
        SetlistDoc(slug: slug, name: name, arrangements: arrangements)
    }

    private var library: [SetlistDoc] {
        [setlist("friday", "Friday night", ["sous-le-ciel", "autumn-leaves"]),
         setlist("busking", "Busking set", ["autumn-leaves"]),
         setlist("empty", "Nothing in it yet", [])]
    }

    // MARK: - What the checklist shows

    /// Note the order is by NAME: "Busking set", "Friday night", "Nothing in
    /// it yet" -- which is not the slug order (busking, empty, friday). This
    /// assertion was written the wrong way round first, by sorting the slugs
    /// by eye, and the test caught it.
    func testEverySetlistIsOfferedWhetherOrNotTheScoreIsInIt() {
        let rows = SetlistMembership.rows(for: "sous-le-ciel", in: library)
        XCTAssertEqual(rows.map(\.slug), ["busking", "friday", "empty"])
        XCTAssertEqual(rows.map(\.name),
                       ["Busking set", "Friday night", "Nothing in it yet"])
    }

    /// The check is the membership, and nothing else says it.
    func testTheCheckMarksTheSetlistsTheScoreIsAlreadyIn() {
        let rows = SetlistMembership.rows(for: "sous-le-ciel", in: library)
        XCTAssertEqual(rows.first { $0.slug == "friday" }?.isMember, true)
        XCTAssertEqual(rows.first { $0.slug == "busking" }?.isMember, false)
        XCTAssertEqual(rows.first { $0.slug == "empty" }?.isMember, false)
    }

    /// **Alphabetical, and NOT members-first.** A checklist that sorts by
    /// membership reorders itself under the finger: check a box and the row
    /// you just tapped jumps to the top, so the next tap lands on a different
    /// setlist than the one aimed at. The order must not depend on the thing
    /// the control changes.
    func testTheOrderDoesNotChangeWhenMembershipDoes() {
        let before = SetlistMembership.rows(for: "sous-le-ciel", in: library)
        var after = library
        after[1].arrangements.append("sous-le-ciel")   // now in Busking too
        let rows = SetlistMembership.rows(for: "sous-le-ciel", in: after)
        XCTAssertEqual(rows.map(\.slug), before.map(\.slug),
                       "the rows moved when a box was checked")
        XCTAssertEqual(rows.first { $0.slug == "busking" }?.isMember, true)
    }

    /// Sorted by NAME, which is what the reader sees, not by slug.
    func testItSortsByTheNameOnScreenRatherThanTheSlug() {
        let odd = [setlist("zzz", "Aardvark", []), setlist("aaa", "Zebra", [])]
        XCTAssertEqual(SetlistMembership.rows(for: "x", in: odd).map(\.name),
                       ["Aardvark", "Zebra"])
    }

    /// Case-insensitively, or "busking" sorts after "Friday night" and the
    /// list looks shuffled to anyone who names a setlist in lower case.
    func testTheSortIgnoresCase() {
        let mixed = [setlist("b", "banjo night", []), setlist("a", "Accordion", []),
                     setlist("c", "Cello", [])]
        XCTAssertEqual(SetlistMembership.rows(for: "x", in: mixed).map(\.name),
                       ["Accordion", "banjo night", "Cello"])
    }

    /// How many arrangements are in it, so a reader can tell a big set from an
    /// empty one without opening it.
    func testEachRowSaysHowFullTheSetlistIs() {
        let rows = SetlistMembership.rows(for: "sous-le-ciel", in: library)
        XCTAssertEqual(rows.first { $0.slug == "friday" }?.count, 2)
        XCTAssertEqual(rows.first { $0.slug == "empty" }?.count, 0)
    }

    func testALibraryWithNoSetlistsOffersNothing() {
        XCTAssertEqual(SetlistMembership.rows(for: "x", in: []).count, 0)
    }

    // MARK: - What a tap means

    /// A tap toggles, and the direction is read from the row rather than
    /// guessed: tapping a member removes, tapping a non-member adds.
    func testATapOnAMemberRemovesAndOnANonMemberAdds() {
        let rows = SetlistMembership.rows(for: "sous-le-ciel", in: library)
        let member = rows.first { $0.slug == "friday" }!
        let other = rows.first { $0.slug == "busking" }!
        XCTAssertEqual(SetlistMembership.tap(member), .remove(setlist: "friday"))
        XCTAssertEqual(SetlistMembership.tap(other), .add(setlist: "busking"))
    }

    /// The one-line summary the "+" button reads out, so a reader with
    /// VoiceOver knows the state before opening anything.
    func testTheButtonSaysHowManySetlistsTheScoreIsIn() {
        XCTAssertEqual(SetlistMembership.summary(for: "sous-le-ciel", in: library),
                       "In 1 set list")
        XCTAssertEqual(SetlistMembership.summary(for: "autumn-leaves", in: library),
                       "In 2 set lists")
        XCTAssertEqual(SetlistMembership.summary(for: "nowhere", in: library),
                       "In no set lists")
    }

    /// With no setlists at all the button still says something true, rather
    /// than "In no set lists" implying some exist to be added to.
    func testWithNoSetlistsTheSummarySaysSo() {
        XCTAssertEqual(SetlistMembership.summary(for: "x", in: []),
                       "No set lists yet")
    }
}
