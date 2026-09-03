import XCTest

/// The OMR entry point read as a label and behaved as a button.
final class MakeEditableTests: XCTestCase {

    func testIdleItOffersTheRunAndTakesATap() {
        let control = MakeEditable.control(busy: false, stage: nil, fraction: nil)
        XCTAssertFalse(control.isOn)
        XCTAssertTrue(control.acceptsTap)
        XCTAssertEqual(control.detail, MakeEditable.offer)
        XCTAssertNil(control.fraction)
        XCTAssertFalse(control.showsSpinner)
    }

    /// The regression: pressing it looked like nothing happened.
    func testRunningItSaysWhatItIsDoing() {
        let control = MakeEditable.control(busy: true, stage: "converting…",
                                           fraction: nil)
        XCTAssertTrue(control.isOn)
        XCTAssertEqual(control.detail, "converting…")
        XCTAssertTrue(control.showsSpinner, "no fraction, so something must move")
    }

    func testAStageWithAFractionDrawsABarInsteadOfASpinner() {
        let control = MakeEditable.control(busy: true, stage: "uploading…",
                                           fraction: 0.4)
        XCTAssertEqual(control.fraction, 0.4)
        XCTAssertFalse(control.showsSpinner)
    }

    /// A second tap must not start a second run on the same page.
    func testRunningItIsInert() {
        XCTAssertFalse(MakeEditable.control(busy: true, stage: nil,
                                            fraction: nil).acceptsTap)
    }

    /// Busy with nothing to report is still busy, and must not read as idle.
    func testBusyWithNoStageStillSaysSomething() {
        for stage in [nil, "", "   "] {
            let control = MakeEditable.control(busy: true, stage: stage, fraction: nil)
            XCTAssertTrue(control.isOn)
            XCTAssertFalse(control.detail.isEmpty)
            XCTAssertNotEqual(control.detail, MakeEditable.offer)
        }
    }
}
