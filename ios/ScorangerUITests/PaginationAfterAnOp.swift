import XCTest

/// Pagination survives an op that ADDS material to the score.
///
/// Ali: after a chat op that changes the score -- adding a staff, a tab,
/// chords -- "the layout collapses to one long squished illegible system".
///
/// "One long squished system" is exactly what `breaks: "none"` produces, and
/// that was the obvious suspect: `VerovioRenderer` keeps ONE toolkit,
/// Verovio's `setOptions` MERGES, and a continuous engrave leaking its
/// `breaks` into every paged one afterwards is a fault this app has had and
/// fixed once (`EngravingOptions`). It is NOT this one. Replaying the whole
/// sequence against the same Verovio with the iOS option sets verbatim --
/// paged, paged with an MEI reload, a continuous visit, paged again -- gives
/// 9 pages every single time. The engine's own renderer paginates through an
/// op too: 8 pages before a tab, 12 after, which is a tab adding height and
/// not a collapse.
///
/// What is left is the part Python never exercises: the SWIFT MEI transforms
/// in `engrave` -- `FingeringDiagrams.meiWithFingeringsAbove`,
/// `ChordPlacement.meiWithChartStyling`, `ChordAdjustments`,
/// `ChordDiagrams.meiWithDiagrams`, `RehearsalMarks`. Each rewrites the MEI
/// as text and sets `reload`, and the document is then re-read from what they
/// produced. Ali's three examples are exactly the three that trigger them,
/// and a score with none of them never takes that path -- which is why every
/// pagination test in this suite has passed.
///
/// So the fixtures here are scores that HAVE those elements, seeded through
/// the real engine rather than from a canned file, and the assertion is the
/// page counter the existing pagination guard already uses.
final class PaginationAfterAnOp: XCTestCase {

    private var app: XCUIApplication!

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// A plain wait, alongside the shared element-based `settle`. RenderShot
    /// carries the same private helper for the same reason: waiting on a page
    /// COUNT is waiting on a number, not on an element appearing.
    private func settle(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private var counter: String {
        let chip = app.staticTexts["counter-pages"]
        return chip.exists ? chip.label : ""
    }

    /// The total in "p. 3 / 9", or 0 when the counter is absent.
    private func pages(in label: String) -> Int {
        guard let slash = label.lastIndex(of: "/") else { return 0 }
        return Int(label[label.index(after: slash)...]
            .trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private func waitForPages(_ want: (Int) -> Bool,
                              timeout: TimeInterval = 120) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if want(pages(in: counter)) { settle(0.8); return counter }
            settle(0.5)
        }
        return counter
    }

    /// Open the score the seed put the fixture on: the first by slug, which is
    /// what both seed flags target.
    private func openTheFixture() -> Bool {
        _ = app.descendants(matching: .any)["library-search"].waitForExistence(timeout: 240)
        let row = app.descendants(matching: .any)["row-sous-le-ciel-de-paris"]
        guard row.waitForExistence(timeout: 180) else { return false }
        row.tap()
        let choice = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                  "arrangement-choice-")).firstMatch
        if choice.waitForExistence(timeout: 60) { settle(choice); choice.tap() }
        guard app.buttons["score-title"].waitForExistence(timeout: 300) else { return false }
        let page = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas-")).firstMatch
        _ = page.waitForExistence(timeout: 240)
        settle(page, still: 0.8)
        return true
    }

    /// The score paginates when it carries CHORD SYMBOLS, which is the
    /// `ChordPlacement` transform's reload path.
    func testPaginationSurvivesChordSymbols() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary", "-seedChordChart"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        guard openTheFixture() else { return XCTFail("the fixture never opened") }
        let seen = waitForPages { $0 > 0 }
        snap("pagination-with-chord-symbols")
        print("PAGINATION chords: counter = \"\(seen)\"")
        XCTAssertGreaterThan(pages(in: seen), 1,
                             "a score carrying chord symbols engraved to "
                             + "\(pages(in: seen)) page(s): \"\(seen)\"")
    }

    /// And when it carries a GUITAR TAB, which is the `FingeringDiagrams`
    /// reload path -- lyric verses moved above the staff on the MEI.
    func testPaginationSurvivesAGuitarTab() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary", "-seedGuitarTab"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        guard openTheFixture() else { return XCTFail("the fixture never opened") }
        let seen = waitForPages { $0 > 0 }
        snap("pagination-with-a-guitar-tab")
        print("PAGINATION tab: counter = \"\(seen)\"")
        XCTAssertGreaterThan(pages(in: seen), 1,
                             "a score carrying a guitar tab engraved to "
                             + "\(pages(in: seen)) page(s): \"\(seen)\"")
    }

    /// The control, and the reason the two above mean anything: the SAME
    /// score with none of those elements. If this one also came back as a
    /// single page the fixture would be wrong, not the transforms.
    func testTheSameScoreWithoutThemPaginates() {
        app = XCUIApplication()
        app.launchArguments = ["-resetLibrary", "-seedTestLibrary"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        guard openTheFixture() else { return XCTFail("the fixture never opened") }
        let seen = waitForPages { $0 > 0 }
        print("PAGINATION control: counter = \"\(seen)\"")
        XCTAssertGreaterThan(pages(in: seen), 1,
                             "the control score is \(pages(in: seen)) page(s), "
                             + "so the fixture is wrong rather than the transforms")
    }
}
