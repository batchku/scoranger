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

    // MARK: - Which layout the canvas may draw with (Ali, 2026-09-14 #2)

    /// One page and a spread are the same pages counted out differently.
    func testTheTwoPagedLayoutsShareAnEngraving() {
        XCTAssertEqual(ScoreLayout.page.engraving, ScoreLayout.spread.engraving)
        XCTAssertNotEqual(ScoreLayout.page.engraving, ScoreLayout.continuous.engraving)
    }

    /// Nothing held, nothing to mismatch.
    func testWithNoPagesTheChoiceIsDrawnAtOnce() {
        XCTAssertEqual(ScoreLayout.displayed(chosen: .continuous, engraved: nil), .continuous)
        XCTAssertEqual(ScoreLayout.displayed(chosen: .spread, engraved: nil), .spread)
    }

    /// Switching between the two paged layouts needs no new engraving, so it
    /// takes effect on the next frame.
    func testPageAndSpreadSwitchWithoutWaiting() {
        XCTAssertEqual(ScoreLayout.displayed(chosen: .spread, engraved: .page), .spread)
        XCTAssertEqual(ScoreLayout.displayed(chosen: .page, engraved: .spread), .page)
    }

    /// The flash itself: a paged document drawn as a strip, or a strip drawn
    /// as pages, for the frame between the choice publishing and the new
    /// engraving arriving. The canvas keeps drawing what it is holding.
    func testAStripIsNotDrawnBeforeItExists() {
        XCTAssertEqual(ScoreLayout.displayed(chosen: .continuous, engraved: .page), .page)
        XCTAssertEqual(ScoreLayout.displayed(chosen: .continuous, engraved: .spread), .spread)
    }

    func testPagesAreNotDrawnBeforeTheyExist() {
        XCTAssertEqual(ScoreLayout.displayed(chosen: .page, engraved: .continuous), .continuous)
        XCTAssertEqual(ScoreLayout.displayed(chosen: .spread, engraved: .continuous), .continuous)
    }

    /// ...but only while the new engraving is COMING.
    ///
    /// Whiskey In A Jar came back from Ali's iPad as one system with every bar
    /// of the tune crushed onto it, the rest of the page blank, in 1-page
    /// mode. That is the continuous strip -- `breaks: none`, reproduced
    /// exactly against his own MusicXML -- drawn inside a page frame. The
    /// transient above is meant to last one frame; with no engrave in flight
    /// it lasted until the app was relaunched, because ONE PAGE AND A SPREAD
    /// SHARE AN ENGRAVING and his two obvious recoveries asked for nothing.
    func testAFailedHandoverDoesNotStrandTheReaderOnTheWrongEngraving() {
        XCTAssertEqual(ScoreLayout.displayed(chosen: .page, engraved: .continuous,
                                             awaiting: false), .page)
        XCTAssertEqual(ScoreLayout.displayed(chosen: .spread, engraved: .continuous,
                                             awaiting: false), .spread)
        XCTAssertEqual(ScoreLayout.displayed(chosen: .continuous, engraved: .page,
                                             awaiting: false), .continuous)
    }

    /// And the transient is still a transient: with an engrave in flight the
    /// canvas keeps what it has, so the flash Ali reported earlier stays fixed.
    func testTheFlashFixSurvivesTheStrandingFix() {
        XCTAssertEqual(ScoreLayout.displayed(chosen: .page, engraved: .continuous,
                                             awaiting: true), .continuous)
        XCTAssertEqual(ScoreLayout.displayed(chosen: .continuous, engraved: .page,
                                             awaiting: true), .page)
    }

    /// Once the document the choice asked for has arrived, the choice is what
    /// is drawn -- or the canvas would be stuck in the old layout for ever.
    func testWhenTheEngravingArrivesTheChoiceIsDrawn() {
        XCTAssertEqual(ScoreLayout.displayed(chosen: .continuous, engraved: .continuous), .continuous)
        XCTAssertEqual(ScoreLayout.displayed(chosen: .page, engraved: .page), .page)
    }

    /// Every pair, so a fourth layout cannot quietly break the rule: what is
    /// drawn always matches the ENGRAVING that is held.
    func testWhatIsDrawnAlwaysMatchesTheEngravingThatIsHeld() {
        for chosen in ScoreLayout.allCases {
            for engraved in ScoreLayout.allCases {
                let drawn = ScoreLayout.displayed(chosen: chosen, engraved: engraved)
                XCTAssertEqual(drawn.engraving, engraved.engraving,
                               "chose \(chosen) holding \(engraved): drew \(drawn)")
            }
        }
    }
}
