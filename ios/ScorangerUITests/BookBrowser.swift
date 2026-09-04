import XCTest

/// Looking through a book the size of a Real Book.
///
/// The browser had no test at all, and the report that it "got stuck" arrived
/// from a reader with a 512-page fake book. Nothing smaller reproduces it: the
/// fault was that every cell the lazy strip built rasterised a PDF page on the
/// main thread, so the cost of a flick was the number of pages it swept and
/// there was nothing to call off. A ten-page book sweeps ten cells.
///
/// So this seeds a 512-page book (`-seedBigBook`, `BigBookFixture`) and asks
/// the one question that matters: after a hard flick through it, does the app
/// still answer?
///
/// It asserts NO latency budget -- there is none agreed, and inventing one
/// here would be inventing a requirement. It asserts that a control tapped
/// after the flick does its job inside a very generous deadline, which is a
/// hang test and not a speed test.
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
    /// Before the fix the tap had to wait behind one PDF raster for every cell
    /// the flick had swept over, on the main thread, with no way to skip the
    /// ones the reader had already passed.
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
