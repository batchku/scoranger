import XCTest
final class LibraryLabels: XCTestCase {
    func testDumpLabels() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedTestLibrary"]
        app.launch()
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 120)
        settle(app.descendants(matching: .any)["library-search"], still: 1.2)
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "row-"))
        print("ROWS: \(rows.count)")
        for i in 0..<rows.count {
            let r = rows.element(boundBy: i)
            print("  row[\(i)] id=\(r.identifier) label=\(r.label)")
        }
        // and the arrangement choices behind the first row
        rows.firstMatch.tap()
        let choices = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "arrangement-choice-"))
        _ = choices.firstMatch.waitForExistence(timeout: 60)
        print("CHOICES: \(choices.count)")
        for i in 0..<choices.count {
            let c = choices.element(boundBy: i)
            print("  choice[\(i)] id=\(c.identifier) label=\(c.label)")
        }
    }
}
