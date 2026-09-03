import CoreGraphics
import XCTest

/// #60: the way out of the score may never be squeezed off the bar.
final class ScoreBarLayoutTests: XCTestCase {
    /// The widths that actually matter, bar-width (not screen) in points.
    /// The narrowest bar the app has to seat: an iPhone SE.
    private let iPhoneSE: CGFloat = 375
    private let iPhonePortrait: CGFloat = 390
    private let iPhoneLandscape: CGFloat = 844
    private let iPadPortrait: CGFloat = 834
    private let iPadLandscape: CGFloat = 1210

    /// The bug, stated as a test: whatever else goes, ✕ and the actions fit.
    func testEveryRealWidthSeatsTheWayOutAndTheActions() {
        for width in [iPhoneSE, iPhonePortrait, iPhoneLandscape,
                      iPadPortrait, iPadLandscape] {
            let fit = ScoreBarLayout.fit(barWidth: width)
            XCTAssertTrue(ScoreBarLayout.fits(fit, in: width),
                          "the bar overflows at \(width)pt: \(fit) — this is how ✕ "
                          + "got pushed off the phone")
        }
    }

    /// A phone drops the extras but keeps the score leaveable and usable.
    func testAPhoneKeepsTheEssentialsAndDropsTheExtras() {
        let fit = ScoreBarLayout.fit(barWidth: iPhonePortrait)
        XCTAssertFalse(fit.showsVersions, "the version count is what pushed ✕ off")
        XCTAssertFalse(fit.showsModeChip)
        XCTAssertEqual(fit.layoutCells, 2, "a spread across 390pt is two thumbnails")
        XCTAssertFalse(fit.showsTransportToggle,
                       "the toggle yields on a phone -- Options still carries it")
        XCTAssertTrue(ScoreBarLayout.fits(fit, in: iPhonePortrait))
    }

    /// An iPad seats the transport toggle, which is the point of putting it on
    /// the bar: the switch that was two screens down is now one tap away.
    func testAnIPadSeatsTheTransportToggle() {
        XCTAssertTrue(ScoreBarLayout.fit(barWidth: iPadLandscape).showsTransportToggle)
        XCTAssertTrue(ScoreBarLayout.fit(barWidth: iPadPortrait).showsTransportToggle)
    }

    /// It yields AFTER the version count and BEFORE a layout cell: the layout
    /// control is the only route to continuous, and the toggle is not the only
    /// route to anything.
    func testTheTransportToggleYieldsBeforeALayoutCell() {
        var seenTransportDrop = false
        for width in stride(from: CGFloat(1400), through: 300, by: -5) {
            let fit = ScoreBarLayout.fit(barWidth: width)
            if !fit.showsTransportToggle { seenTransportDrop = true }
            if fit.layoutCells < 3 {
                XCTAssertTrue(seenTransportDrop,
                              "a layout cell went before the transport toggle at "
                              + "\(width)pt")
            }
        }
        XCTAssertTrue(seenTransportDrop)
    }

    func testAnIPadShowsTheWholeBar() {
        let fit = ScoreBarLayout.fit(barWidth: iPadLandscape)
        XCTAssertEqual(fit, ScoreBarLayout.Fit(showsVersions: true, showsModeChip: true,
                                               layoutCells: 3))
    }

    /// The stated order: the chip yields before the version count, and the
    /// version count before the spread cell.
    func testThingsYieldInTheStatedOrder() {
        var seenChipDrop = false, seenVersionsDrop = false, seenCellDrop = false
        var width = ScoreBarLayout.essentials + ScoreBarLayout.threeCells
            + ScoreBarLayout.versionsWidth + ScoreBarLayout.modeChipWidth
            + ScoreBarLayout.transportWidth + ScoreBarLayout.titleMinimum
        while width > 200 {
            let fit = ScoreBarLayout.fit(barWidth: width)
            if !fit.showsModeChip { seenChipDrop = true }
            if !fit.showsVersions {
                seenVersionsDrop = true
                XCTAssertTrue(seenChipDrop, "the version count went before the chip did")
            }
            if fit.layoutCells < 3 {
                seenCellDrop = true
                XCTAssertTrue(seenVersionsDrop,
                              "a layout cell went before the version count did")
            }
            width -= 10
        }
        XCTAssertTrue(seenChipDrop && seenVersionsDrop && seenCellDrop,
                      "the sweep should have exercised every step")
    }

    /// #62: with the version count already yielded, the title block is the
    /// only route to the version dropdown — so on a phone the title's
    /// COMPANIONS go rather than the title itself.
    func testAPhoneKeepsTheTitleAndDropsWhatSitsBesideIt() {
        for width in [iPhoneSE, iPhonePortrait] {
            let fit = ScoreBarLayout.fit(barWidth: width)
            XCTAssertFalse(fit.showsNumeral, "the #N badge should yield at \(width)")
            XCTAssertFalse(fit.showsSubtitle, "the subtitle should yield at \(width)")
            XCTAssertTrue(fit.titleExpands,
                          "the title must take the slack, or the spacers do and "
                          + "it collapses to an ellipsis")
            XCTAssertTrue(ScoreBarLayout.fits(fit, in: width))
        }
    }

    /// And an iPad keeps them: it has the room, and the title stays centred.
    func testAnIPadKeepsTheNumeralAndSubtitle() {
        let fit = ScoreBarLayout.fit(barWidth: iPadLandscape)
        XCTAssertTrue(fit.showsNumeral)
        XCTAssertTrue(fit.showsSubtitle)
        XCTAssertFalse(fit.titleExpands, "the spacers still centre it on an iPad")
    }

    /// Narrower and narrower must never start putting things BACK.
    func testNothingReappearsAsTheBarNarrows() {
        var previous = ScoreBarLayout.fit(barWidth: 1400)
        for width in stride(from: CGFloat(1400), through: 300, by: -5) {
            let fit = ScoreBarLayout.fit(barWidth: width)
            XCTAssertFalse(fit.showsModeChip && !previous.showsModeChip,
                           "the chip came back at \(width)pt")
            XCTAssertFalse(fit.showsVersions && !previous.showsVersions,
                           "the version count came back at \(width)pt")
            XCTAssertLessThanOrEqual(fit.layoutCells, previous.layoutCells,
                                     "a layout cell came back at \(width)pt")
            XCTAssertFalse(fit.showsNumeral && !previous.showsNumeral,
                           "the numeral came back at \(width)pt")
            XCTAssertFalse(fit.showsSubtitle && !previous.showsSubtitle,
                           "the subtitle came back at \(width)pt")
            XCTAssertFalse(fit.showsTransportToggle && !previous.showsTransportToggle,
                           "the transport toggle came back at \(width)pt")
            previous = fit
        }
    }

    /// Before the bar has been measured, show everything: a stripped bar that
    /// fills in on the second frame reads as a glitch.
    func testAnUnmeasuredBarShowsEverything() {
        XCTAssertEqual(ScoreBarLayout.fit(barWidth: 0),
                       ScoreBarLayout.Fit(showsVersions: true, showsModeChip: true,
                                          layoutCells: 3))
    }
}
