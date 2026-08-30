import XCTest

/// The three-way layout control, replacing the spread boolean.
final class ScoreLayoutTests: XCTestCase {
    func testASpreadIsTheOnlyLayoutShowingTwoPages() {
        XCTAssertEqual(ScoreLayout.page.pagesPerUnit, 1)
        XCTAssertEqual(ScoreLayout.spread.pagesPerUnit, 2)
        XCTAssertEqual(ScoreLayout.continuous.pagesPerUnit, 1)
    }

    /// The impossible state the boolean pair allowed: spread AND continuous.
    /// It cannot be written down any more.
    func testTheLayoutCannotBeBothSpreadAndContinuous() {
        for layout in ScoreLayout.allCases {
            XCTAssertFalse(layout == .spread && layout.isContinuous)
        }
    }

    func testAPhoneIsOfferedPageAndContinuousOnly() {
        XCTAssertEqual(ScoreLayout.available(isCompact: true), [.page, .continuous])
        XCTAssertEqual(ScoreLayout.available(isCompact: false),
                       [.page, .spread, .continuous])
    }

    func testSteppingWalksTheOptionsAndStopsAtTheEnds() {
        XCTAssertEqual(ScoreLayout.page.stepped(by: 1, isCompact: false), .spread)
        XCTAssertEqual(ScoreLayout.spread.stepped(by: 1, isCompact: false), .continuous)
        XCTAssertEqual(ScoreLayout.continuous.stepped(by: 1, isCompact: false), .continuous)
        XCTAssertEqual(ScoreLayout.page.stepped(by: -1, isCompact: false), .page)
    }

    /// Stepping on a phone skips the spread rather than landing on a value
    /// that screen has no cell for.
    func testSteppingOnAPhoneSkipsTheSpread() {
        XCTAssertEqual(ScoreLayout.page.stepped(by: 1, isCompact: true), .continuous)
    }

    /// Ink is keyed to a page index; continuous mode has one surface.
    func testContinuousDoesNotOfferAnnotation() {
        XCTAssertTrue(ScoreLayout.page.allowsAnnotation)
        XCTAssertTrue(ScoreLayout.spread.allowsAnnotation)
        XCTAssertFalse(ScoreLayout.continuous.allowsAnnotation)
    }

    func testContinuousHasNoPageCounter() {
        XCTAssertFalse(ScoreLayout.continuous.showsPageCounter)
        XCTAssertTrue(ScoreLayout.page.showsPageCounter)
    }

    /// It is persisted, so the raw values are a stored format and may not drift.
    func testTheStoredValuesAreStable() {
        XCTAssertEqual(ScoreLayout.page.rawValue, "page")
        XCTAssertEqual(ScoreLayout.spread.rawValue, "spread")
        XCTAssertEqual(ScoreLayout.continuous.rawValue, "continuous")
    }
}
