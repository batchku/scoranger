import XCTest

/// Looking through a book the size of a Real Book.
///
/// The browser shipped in 0.6.4 with NO test of any kind. This is that test:
/// a 512-page book opens, the strip is there, it survives being flicked
/// through, the pager moves and a typed page number turns the book to it.
///
/// # What it is NOT
///
/// It is not the guard for the fault it was written alongside. That was
/// checked the way this repository checks things -- the fix was reverted and
/// the test run again -- and it PASSED on the broken code, in the same time.
/// It has to, and the reason is worth writing down rather than papering over:
///
///  - The cost that broke the browser is DECODING A SCAN. A page of a real
///    fake book is a full-page JPEG and takes about 4 ms; `BigBookFixture` is
///    vector and takes a quarter of a millisecond. Making the fixture heavy
///    enough to hurt would mean inventing a slow book.
///  - Even at a scan's 4 ms, eight flicks sweep a few hundred cells: seconds,
///    not the tens of seconds a deadline here could sanely allow. To fail on
///    that this would have to assert a LATENCY BUDGET, and there is no agreed
///    one -- the same reason `PerfSweep` asserts nothing.
///
/// So the fault is guarded where it can actually fail, in the unit suite:
/// `ThumbnailRequestTests` (an ask withdrawn draws 7 pages of 120 instead of
/// 120; a peek never rasterises; the store holds its budget in bytes) and
/// `PageThumbnailsTests` (the count bound it replaces was five times the
/// budget). This is end-to-end coverage of a screen that had none.
final class BookBrowser: XCTestCase {

    private var app: XCUIApplication!

    private func launch() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary", "-seedBigBook"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    /// Open the seeded book. The library files books under their own segment.
    private func openTheBook() -> Bool {
        guard app.descendants(matching: .any)["library-search"]
            .waitForExistence(timeout: 240) else {
            XCTFail("the library never appeared")
            return false
        }
        let books = app.descendants(matching: .any)["segment-books"].firstMatch
        guard books.waitForExistence(timeout: 30) else {
            XCTFail("no books segment")
            return false
        }
        books.tap()
        let row = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "row-")).firstMatch
        guard row.waitForExistence(timeout: 240) else {
            XCTFail("the seeded book never appeared")
            return false
        }
        row.tap()
        return app.descendants(matching: .any)["book-thumbnails"]
            .waitForExistence(timeout: 120)
    }

    private func label() -> String {
        app.descendants(matching: .any)["book-page-label"].firstMatch.label
    }

    /// A hard flick through the strip of a 512-page book, and then a tap.
    ///
    /// The deadline is deliberately generous: see the note on the class. This
    /// says the browser works on a book of that size, not how fast.
    func testTheBrowserStillAnswersAfterFlickingThroughABigBook() {
        launch()
        guard openTheBook() else { return }

        let strip = app.descendants(matching: .any)["book-thumbnails"].firstMatch
        XCTAssertTrue(strip.exists)
        XCTAssertTrue(label().contains("of 512"),
                      "the seeded book is not 512 pages: \(label())")

        for _ in 0..<8 {
            strip.swipeLeft(velocity: .fast)
        }

        // The question: does anything still work? A generous deadline, because
        // this is a hang test and not a latency budget.
        let next = app.buttons["book-next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 30),
                      "the pager was gone after flicking the strip")
        let before = label()
        next.tap()
        let moved = NSPredicate(format: "label != %@", before)
        expectation(for: moved, evaluatedWith:
                        app.descendants(matching: .any)["book-page-label"].firstMatch)
        waitForExpectations(timeout: 30) { error in
            XCTAssertNil(error, "the browser stopped answering after a flick "
                         + "through a 512-page book")
        }
    }

    /// Typing a page number turns the book to it — a jump of four hundred
    /// pages, which is what a reader looking for one tune does.
    func testTypingAFarPageNumberTurnsTheBookToIt() {
        launch()
        guard openTheBook() else { return }

        let field = app.textFields["book-from-page"].firstMatch
        guard field.waitForExistence(timeout: 30) else {
            XCTFail("no from-page field")
            return
        }
        field.tap()
        field.typeText("437")

        let arrived = NSPredicate(format: "label CONTAINS %@", "Page 437")
        expectation(for: arrived, evaluatedWith:
                        app.descendants(matching: .any)["book-page-label"].firstMatch)
        waitForExpectations(timeout: 60) { error in
            XCTAssertNil(error, "typing a page did not turn the book to it "
                         + "(label was \(self.label()))")
        }
    }
}
