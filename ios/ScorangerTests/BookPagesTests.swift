import XCTest

// No import of the app module: this bundle compiles BookPages.swift in.

/// Choosing a page range out of a book by looking at it.
///
/// The screen asked for two numbers and showed nothing, which in a
/// four-hundred-page fake book is a guessing game. What is asserted here is
/// the arithmetic that lets the two presses under the page fill the fields in,
/// and that the fields keep working for a reader who knows the number already
/// — the old way of reaching this has to survive the build that replaces it.
final class BookPagesTests: XCTestCase {

    func testARangeIsTwoNumbersInsideTheBookAndInOrder() {
        XCTAssertEqual(BookPages.range(from: "12", to: "14", pages: 420)?.from, 12)
        XCTAssertEqual(BookPages.range(from: "12", to: "14", pages: 420)?.to, 14)
        // one page is a range
        XCTAssertNotNil(BookPages.range(from: "7", to: "7", pages: 420))
        // and these are not
        XCTAssertNil(BookPages.range(from: "14", to: "12", pages: 420))
        XCTAssertNil(BookPages.range(from: "0", to: "3", pages: 420))
        XCTAssertNil(BookPages.range(from: "1", to: "421", pages: 420))
        XCTAssertNil(BookPages.range(from: "", to: "3", pages: 420))
        XCTAssertNil(BookPages.range(from: "Misty", to: "3", pages: 420))
        // a book whose page count is not known yet cannot have a range checked
        XCTAssertNil(BookPages.range(from: "1", to: "3", pages: nil))
        // whitespace is not a typo
        XCTAssertNotNil(BookPages.range(from: " 12 ", to: "14 ", pages: 420))
    }

    func testStartsHereAndEndsHereFillTheFieldsIn() {
        // the first press on an empty form takes both ends, so a one-page tune
        // is one press and not two
        var fields = BookPages.starting(at: 137, from: "", to: "")
        XCTAssertEqual(fields.from, "137")
        XCTAssertEqual(fields.to, "137")
        // flipping on and pressing the second sets only the end
        fields = BookPages.ending(at: 139, from: fields.from, to: fields.to)
        XCTAssertEqual(fields.from, "137")
        XCTAssertEqual(fields.to, "139")
        // and pressing "starts here" past the end drags the end with it, so
        // the fields never name a backwards range
        fields = BookPages.starting(at: 200, from: fields.from, to: fields.to)
        XCTAssertEqual(fields.from, "200")
        XCTAssertEqual(fields.to, "200")
        // the same in the other direction
        fields = BookPages.ending(at: 40, from: "137", to: "139")
        XCTAssertEqual(fields.from, "40")
        XCTAssertEqual(fields.to, "40")
    }

    func testATypedPageTurnsTheBookToIt() {
        XCTAssertEqual(BookPages.page(inField: "137", pages: 420), 137)
        XCTAssertEqual(BookPages.page(inField: " 1 ", pages: 420), 1)
        // and nothing that is not a page in this book moves it
        XCTAssertNil(BookPages.page(inField: "", pages: 420))
        XCTAssertNil(BookPages.page(inField: "0", pages: 420))
        XCTAssertNil(BookPages.page(inField: "421", pages: 420))
        XCTAssertNil(BookPages.page(inField: "Misty", pages: 420))
    }

    func testTheChosenSpanIsMarkedAsASpan() {
        XCTAssertTrue(BookPages.isChosen(137, from: "137", to: "139", pages: 420))
        XCTAssertTrue(BookPages.isChosen(138, from: "137", to: "139", pages: 420))
        XCTAssertTrue(BookPages.isChosen(139, from: "137", to: "139", pages: 420))
        XCTAssertFalse(BookPages.isChosen(136, from: "137", to: "139", pages: 420))
        XCTAssertFalse(BookPages.isChosen(140, from: "137", to: "139", pages: 420))
        // a half-typed range marks nothing rather than marking everything
        XCTAssertFalse(BookPages.isChosen(137, from: "137", to: "", pages: 420))
    }

    func testThePageNeverRunsOffTheEnds() {
        XCTAssertEqual(BookPages.clamp(0, pages: 420), 1)
        XCTAssertEqual(BookPages.clamp(500, pages: 420), 420)
        XCTAssertEqual(BookPages.clamp(137, pages: 420), 137)
        // an empty book has no page 0 either
        XCTAssertEqual(BookPages.clamp(3, pages: 0), 1)
    }

    func testWhatIsOnScreenSaysWhichOfHowMany() {
        // "137" alone is the number that is hard to guess; "of 420" is why
        XCTAssertEqual(BookPages.label(page: 137, pages: 420), "Page 137 of 420")
        XCTAssertEqual(BookPages.summary(from: 137, to: 137), "page 137")
        XCTAssertEqual(BookPages.summary(from: 137, to: 139),
                       "pages 137–139 (3 pages)")
    }
}
