import XCTest

/// The three import actions (`ImportIntent`).
///
/// These pin a bug that shipped in every build that had Import Folder and
/// Import Book: both did nothing whatsoever. One `.fileImporter` served all
/// three actions, presented by an optional kind that its own isPresented
/// binding cleared on dismissal -- and SwiftUI runs that setter BEFORE the
/// completion handler. The completion read the cleared value, fell back to
/// `.file`, and passed a folder to the file path, which threw on a directory
/// into an error the library did not render. Nothing happened, twice over.
///
/// The order below is the order SwiftUI uses. That is the whole test.
final class ImportIntentTests: XCTestCase {

    /// Dismissal must not take the request with it: the completion handler
    /// runs afterwards and it is the only thing that knows what to do.
    func testTheRequestSurvivesTheDismissalThatPrecedesTheCompletion() {
        var intent = ImportIntent()

        intent.ask(for: .folder)          // reader taps Import Folder
        intent.dismissed()                // SwiftUI closes the picker

        XCTAssertEqual(intent.requested, .folder,
                       "the completion would import a FOLDER as a file")
        XCTAssertFalse(intent.isPresented)
    }

    /// The same for a book, which was broken by the identical mechanism.
    func testABookIsStillABookAfterTheSheetCloses() {
        var intent = ImportIntent()

        intent.ask(for: .book)
        intent.dismissed()

        XCTAssertEqual(intent.requested, .book)
    }

    /// Asking presents; nothing presents on its own.
    func testAskingIsWhatPresentsThePicker() {
        var intent = ImportIntent()
        XCTAssertFalse(intent.isPresented, "the picker cannot open unasked")

        intent.ask(for: .file)

        XCTAssertTrue(intent.isPresented)
        XCTAssertEqual(intent.requested, .file)
    }

    /// Two actions in a row: the second is what the completion acts on.
    func testTheLatestRequestWins() {
        var intent = ImportIntent()

        intent.ask(for: .folder)
        intent.dismissed()
        intent.ask(for: .book)
        intent.dismissed()

        XCTAssertEqual(intent.requested, .book)
    }

    /// What each action asks the picker for. A folder is one thing; a library
    /// of loose files is many.
    func testEachKindAsksThePickerForTheRightThing() {
        XCTAssertEqual(ImportKind.folder.contentTypes, [.folder])
        XCTAssertEqual(ImportKind.book.contentTypes, [.pdf])
        XCTAssertFalse(ImportKind.folder.allowsMultiple)
        XCTAssertFalse(ImportKind.book.allowsMultiple)
        XCTAssertTrue(ImportKind.file.allowsMultiple)
    }
}
