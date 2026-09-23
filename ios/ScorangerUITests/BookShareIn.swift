import XCTest

/// A book shared into the app: asked about, its tunes found, kept, and read
/// one at a time (0.14.0).
///
/// Before 0.14.0 a PDF from another app's share sheet could only become a
/// scan arrangement, so a book could not be shared in at all. The chooser is
/// driven here by `-shareInSampleBook`, which hands a twelve-page book to
/// `AppState.offerImport` -- the door `onOpenURL` uses -- because the
/// simulator has no share sheet to drive.
final class BookShareIn: XCTestCase {

    private var app: XCUIApplication!

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testASharedBookIsAskedAboutFoundKeptAndRead() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-shareInSampleBook"]
        app.launch()

        // Asked, not imported.
        let asBook = element("import-as-new-book")
        XCTAssertTrue(asBook.waitForExistence(timeout: 120),
                      "a shared file was not asked about")
        XCTAssertTrue(element("import-as-new-piece").exists)
        XCTAssertTrue(element("import-as-existing-piece").exists)
        snap("import-as")
        asBook.tap()

        // The book opens on its proposal: twelve titled pages, twelve tunes.
        let review = element("book-review")
        XCTAssertTrue(review.waitForExistence(timeout: 180),
                      "the book did not open on its proposed tunes")
        // Counted from the sentence above the list: the list is lazy, and a
        // row below the fold does not exist to be found.
        let found = element("book-review-found")
        XCTAssertTrue(found.waitForExistence(timeout: 10))
        XCTAssertTrue(found.label.hasPrefix("12 tunes, from the titles printed on its pages"),
                      "twelve titled pages should propose twelve tunes: \(found.label)")
        XCTAssertTrue(element("book-review-row-1").exists)
        snap("book-review")

        // Kept as the book's contents: the book stays one book.
        element("book-review-keep").tap()
        let first = element("book-tune-1")
        XCTAssertTrue(first.waitForExistence(timeout: 60),
                      "the kept contents were not listed")
        XCTAssertTrue(element("book-tune-12").exists)
        snap("book-contents")

        // Read like a set list: a tune, then the next one.
        first.tap()
        XCTAssertTrue(element("book-entry-page-1").waitForExistence(timeout: 30),
                      "the first tune's page was not shown")
        let next = element("book-entry-next")
        XCTAssertTrue(next.isEnabled)
        XCTAssertFalse(element("book-entry-previous").isEnabled)
        snap("book-entry-1")
        next.tap()
        XCTAssertTrue(element("book-entry-page-2").waitForExistence(timeout: 30),
                      "Next did not turn to the second tune")
        snap("book-entry-2")
    }

    /// A scanned book has no text layer, so its titles are read on the device
    /// with Vision and judged by the engine's scan rule (BookOCR, booksplit).
    func testAScannedBooksTunesAreReadFromItsPages() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-shareInScannedBook"]
        app.launch()
        let asBook = element("import-as-new-book")
        XCTAssertTrue(asBook.waitForExistence(timeout: 120))
        asBook.tap()
        let found = element("book-review-found")
        XCTAssertTrue(found.waitForExistence(timeout: 240),
                      "the scanned book did not open on its proposed tunes")
        XCTAssertTrue(found.label.hasPrefix("6 tunes, from titles read from its scanned pages"),
                      "six scanned pages, each titled, should propose six tunes: \(found.label)")
        snap("scanned-book-review")
    }

    /// Taking the tunes out asks once more, then says what it made.
    func testTakingTheTunesOutMakesAPieceForEach() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-shareInSampleBook"]
        app.launch()
        let asBook = element("import-as-new-book")
        XCTAssertTrue(asBook.waitForExistence(timeout: 120))
        asBook.tap()
        let takeOut = element("book-review-take-out")
        XCTAssertTrue(takeOut.waitForExistence(timeout: 180))
        takeOut.tap()
        let confirm = element("book-review-take-out-confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "taking out did not ask first")
        XCTAssertEqual(confirm.label, "Take out 12 tunes")
        confirm.tap()
        let note = element("book-tunes-note")
        XCTAssertTrue(note.waitForExistence(timeout: 180), "taking out said nothing")
        XCTAssertTrue(note.label.hasPrefix("Took out 12 tunes: 12 new pieces"), note.label)
        snap("book-taken-out")
    }

    /// Cancel means nothing was imported.
    func testCancellingTheChoiceImportsNothing() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-shareInSampleBook"]
        app.launch()
        XCTAssertTrue(element("import-as-new-book").waitForExistence(timeout: 120))
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertFalse(element("screen-import-as").waitForExistence(timeout: 3))
        app.buttons["Books"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["Sample Tunebook"].waitForExistence(timeout: 5),
                       "cancelling still imported the book")
    }
}
