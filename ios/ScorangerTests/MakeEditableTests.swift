import XCTest

/// The OMR entry point read as a label and behaved as a button.
final class MakeEditableTests: XCTestCase {

    func testIdleItOffersTheRunAndTakesATap() {
        let control = MakeEditable.control(status: nil)
        XCTAssertFalse(control.isOn)
        XCTAssertTrue(control.acceptsTap)
        XCTAssertEqual(control.detail, MakeEditable.offer)
        XCTAssertNil(control.fraction)
        XCTAssertFalse(control.showsSpinner)
    }

    /// The regression: pressing it looked like nothing happened.
    func testRunningItSaysWhatItIsDoing() {
        let control = MakeEditable.control(
            status: .running(stage: "converting…", fraction: nil))
        XCTAssertTrue(control.isOn)
        XCTAssertEqual(control.detail, "converting…")
        XCTAssertTrue(control.showsSpinner, "no fraction, so something must move")
    }

    func testAStageWithAFractionDrawsABarInsteadOfASpinner() {
        let control = MakeEditable.control(
            status: .running(stage: "uploading…", fraction: 0.4))
        XCTAssertEqual(control.fraction, 0.4)
        XCTAssertFalse(control.showsSpinner)
    }

    /// A second tap must not start a second run on the same page.
    func testRunningItIsInert() {
        XCTAssertFalse(MakeEditable.control(
            status: .running(stage: "converting…", fraction: nil)).acceptsTap)
    }

    /// Busy with nothing to report is still busy, and must not read as idle.
    func testBusyWithNoStageStillSaysSomething() {
        for stage in ["", "   "] {
            let control = MakeEditable.control(
                status: .running(stage: stage, fraction: nil))
            XCTAssertTrue(control.isOn)
            XCTAssertFalse(control.detail.isEmpty)
            XCTAssertNotEqual(control.detail, MakeEditable.offer)
        }
    }

    /// A transcription WAITING its turn reads as on. The reader asked for it;
    /// a switch that flicks back off until the queue reaches it looks like the
    /// tap was lost.
    func testWaitingItsTurnTheSwitchIsOnAndSaysWhere() {
        let control = MakeEditable.control(status: .waiting(place: 2, of: 3))
        XCTAssertTrue(control.isOn)
        XCTAssertFalse(control.acceptsTap)
        XCTAssertEqual(control.detail, "waiting, 2nd of 3")
        XCTAssertNil(control.fraction, "nothing has started, so there is no bar")
        XCTAssertTrue(control.showsSpinner)
    }

    /// One waiting job has no position worth stating.
    func testOneWaitingJobJustWaits() {
        XCTAssertEqual(MakeEditable.control(status: .waiting(place: 1, of: 1)).detail,
                       "waiting")
    }
}

/// The bar that sat full while the work ran (0.6.8).
///
/// Reproduced end to end against the real service and the real Audiveris on an
/// 8-page score: 40 of 40 polls over 78 seconds of converting reported
/// page == pages, so the client drew "reading page 8 of 8" and a full bar from
/// the first poll. Two faults met there -- `SHEET_MARK` in
/// omr-service/server.py was matching the sheet LIST Audiveris prints in its
/// first second, and this side was reading `page` as a count of FINISHED pages.
/// These are this side's half.
final class OMRConvertingProgressTests: XCTestCase {

    /// The regression, stated: the last page must not read as finished.
    func testTheLastPageIsNotAFullBar() {
        let (stage, fraction) = MakeEditable.converting(page: 8, pages: 8)
        XCTAssertEqual(stage, "reading p. 8 / 8")
        let bar = try? XCTUnwrap(fraction)
        XCTAssertNotNil(bar)
        XCTAssertLessThan(bar ?? 1, 1,
                          "a full bar while the page is still being read is the "
                          + "bug this exists to stop")
    }

    /// And no page, at any count, fills it: `done` is what fills it, and this
    /// function never sees `done`.
    func testNoPageOfAnyScoreEverFillsTheBar() {
        for pages in [1, 2, 8, 40, 400] {
            for page in 0...(pages + 2) {
                let fraction = MakeEditable.converting(page: page, pages: pages).fraction
                let bar = fraction ?? 0
                XCTAssertLessThanOrEqual(bar, MakeEditable.convertingCeiling,
                                         "page \(page) of \(pages) drew \(bar)")
                XCTAssertGreaterThanOrEqual(bar, MakeEditable.convertingFloor,
                                            "page \(page) of \(pages) drew nothing at all")
            }
        }
    }

    /// `page` is the sheet being WORKED ON, so the bar behind it is page - 1.
    /// Reading it as finished pages is what put the bar a whole page ahead.
    func testTheBarCountsThePagesBEHINDTheOneBeingRead() {
        XCTAssertEqual(MakeEditable.converting(page: 1, pages: 4).fraction,
                       MakeEditable.convertingFloor,
                       "the first page is not a quarter done the moment it starts")
        XCTAssertEqual(MakeEditable.converting(page: 3, pages: 4).fraction, 0.5,
                       "two of four pages are behind page three")
    }

    /// The words and the bar tell the same story, page by page.
    func testTheWordsNameThePageBeingRead() {
        for page in 1...6 {
            XCTAssertEqual(MakeEditable.converting(page: page, pages: 6).stage,
                           "reading p. \(page) / 6")
        }
    }

    /// Nonsense from the service is clamped rather than drawn: a page number
    /// past the end, or before the start, is still one of the pages.
    func testAPageOutsideTheScoreIsClampedIntoIt() {
        XCTAssertEqual(MakeEditable.converting(page: 99, pages: 6).stage,
                       "reading p. 6 / 6")
        XCTAssertEqual(MakeEditable.converting(page: 0, pages: 6).stage,
                       "reading p. 1 / 6")
        XCTAssertEqual(MakeEditable.converting(page: -3, pages: 6).stage,
                       "reading p. 1 / 6")
    }

    /// No page count is a spinner, not a bar: a bar with no denominator is a
    /// number the app does not have.
    func testNoPageCountIsASpinner() {
        for pages in [0, -1] {
            let progress = MakeEditable.converting(page: 3, pages: pages)
            XCTAssertNil(progress.fraction)
            XCTAssertEqual(progress.stage, "reading…")
        }
    }

    /// It never goes backwards as the pages go by -- a progress bar that
    /// retreats reads as a failure.
    func testItOnlyEverMovesForward() {
        var previous = -1.0
        for page in 1...40 {
            let bar = MakeEditable.converting(page: page, pages: 40).fraction ?? 0
            XCTAssertGreaterThanOrEqual(bar, previous, "the bar went back at page \(page)")
            previous = bar
        }
    }
}

// MARK: - The offer as a panel state (0.8.2, SC13)

/// When the scan's own question opens, and what More's row says instead.
final class ConvertOfferTests: XCTestCase {

    func testAScanOpensTheOffer() {
        XCTAssertTrue(ConvertOffer.opens(artifact: .scan, slug: "waltz",
                                         answered: [], status: nil))
        XCTAssertTrue(ConvertOffer.opens(artifact: .image, slug: "waltz",
                                         answered: [], status: nil))
    }

    /// Notation has nothing to convert, so the question would be nonsense.
    func testNotationNeverOpensIt() {
        XCTAssertFalse(ConvertOffer.opens(artifact: .notation, slug: "quartet",
                                          answered: [], status: nil))
    }

    /// EITHER answer counts. A reader who said "read as is" is not asked again
    /// every time they open the same scan; More's row is how they change
    /// their mind.
    func testAnAnsweredOfferDoesNotReopen() {
        XCTAssertFalse(ConvertOffer.opens(artifact: .scan, slug: "waltz",
                                          answered: ["waltz"], status: nil))
        XCTAssertTrue(ConvertOffer.opens(artifact: .scan, slug: "other",
                                         answered: ["waltz"], status: nil),
                      "answering one scan must not answer another")
    }

    /// A transcription already running is not a question.
    func testItDoesNotOpenOverAJobThatIsAlreadyRunning() {
        XCTAssertFalse(ConvertOffer.opens(
            artifact: .scan, slug: "waltz", answered: [],
            status: .running(stage: "uploading…", fraction: 0.2)))
        XCTAssertFalse(ConvertOffer.opens(
            artifact: .scan, slug: "waltz", answered: [],
            status: .waiting(place: 1, of: 2)),
            "a job already in the queue is not a question either")
    }

    /// No arrangement, no question -- and no empty slug written into the
    /// answered set, which would answer every future one.
    func testNoSlugNoOffer() {
        XCTAssertFalse(ConvertOffer.opens(artifact: .scan, slug: "",
                                          answered: [], status: nil))
    }

    /// More's row states its answer, so the screen reads as a summary (L34).
    func testTheRowStatesItsAnswer() {
        XCTAssertEqual(ConvertOffer.rowValue(status: nil), "not yet")
        XCTAssertEqual(
            ConvertOffer.rowValue(status: .running(stage: "reading p. 4 / 9",
                                                   fraction: 0.3)),
            "reading p. 4 / 9")
        XCTAssertEqual(ConvertOffer.rowValue(status: .waiting(place: 3, of: 4)),
                       "waiting, 3rd of 4")
        XCTAssertEqual(ConvertOffer.rowValue(status: .running(stage: "  ",
                                                              fraction: nil)),
                       "reading…",
                       "a blank stage must not leave the row blank")
    }
}
