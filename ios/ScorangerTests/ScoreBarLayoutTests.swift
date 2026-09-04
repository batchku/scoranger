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
            + ScoreBarLayout.switchesWidth + ScoreBarLayout.titleMinimum
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

    // MARK: - The two switches (0.6.8)

    /// They yield as ONE step. A bar showing Performance mode and not Show
    /// transport, or the other way round, reads as arbitrary -- and Options
    /// carries whichever the bar has not got, so a half-yield would leave one
    /// switch in both places.
    func testTheTwoSwitchesAreNeverSplit() {
        for width in stride(from: CGFloat(1400), through: 260, by: -1) {
            let fit = ScoreBarLayout.fit(barWidth: width)
            XCTAssertEqual(fit.showsTransportToggle, fit.showsPerformanceToggle,
                           "the switches came apart at \(width)pt: \(fit)")
        }
    }

    /// An iPad seats both, which is the point of the move: the two switches
    /// that were two screens from the music are one tap away.
    func testAnIPadSeatsBothSwitches() {
        for width in [iPadPortrait, iPadLandscape] {
            let fit = ScoreBarLayout.fit(barWidth: width)
            XCTAssertTrue(fit.showsPerformanceToggle, "no Performance mode at \(width)")
            XCTAssertTrue(fit.showsTransportToggle, "no Show transport at \(width)")
            XCTAssertTrue(ScoreBarLayout.fits(fit, in: width),
                          "the bar overflows at \(width) with both switches on it")
        }
    }

    /// Nothing comes back as the bar narrows, the performance toggle included.
    func testThePerformanceToggleNeverReappears() {
        var previous = ScoreBarLayout.fit(barWidth: 1400)
        for width in stride(from: CGFloat(1400), through: 300, by: -5) {
            let fit = ScoreBarLayout.fit(barWidth: width)
            XCTAssertFalse(fit.showsPerformanceToggle && !previous.showsPerformanceToggle,
                           "the performance toggle came back at \(width)pt")
            previous = fit
        }
    }

    // MARK: - The transcription chip (0.6.8)

    /// It is drawn only while OMR is running. A chip that is always there says
    /// nothing.
    func testTheChipIsAbsentUnlessOMRIsRunning() {
        for width in [iPhoneSE, iPhonePortrait, iPadPortrait, iPadLandscape] {
            XCTAssertFalse(ScoreBarLayout.fit(barWidth: width).showsOMRProgress,
                           "a chip at \(width) with nothing transcribing")
        }
    }

    /// An iPad seats it, and seating it does not push anything off the bar.
    func testAnIPadSeatsTheChipWithoutOverflowing() {
        for width in [iPadPortrait, iPadLandscape] {
            let fit = ScoreBarLayout.fit(barWidth: width, omrBusy: true)
            XCTAssertTrue(fit.showsOMRProgress, "no transcription chip at \(width)")
            XCTAssertTrue(ScoreBarLayout.fits(fit, in: width),
                          "the bar overflows at \(width) with the chip on it: \(fit)")
        }
    }

    /// The chip outranks both switches: while a transcription runs it is the
    /// only sign in the score view that anything is happening, and a switch is
    /// a shortcut to something reachable elsewhere.
    func testTheChipIsSeatedBeforeTheSwitchesAre() {
        // A width that seats the switches with nothing running.
        let width = ScoreBarLayout.essentials + ScoreBarLayout.threeCells
            + ScoreBarLayout.versionsWidth + ScoreBarLayout.switchesWidth
            + ScoreBarLayout.titleMinimum
        XCTAssertTrue(ScoreBarLayout.fit(barWidth: width).showsTransportToggle,
                      "the fixture is wrong: this width should seat the switches")
        let busy = ScoreBarLayout.fit(barWidth: width, omrBusy: true)
        XCTAssertTrue(busy.showsOMRProgress, "the chip yielded to a switch")
        XCTAssertFalse(busy.showsTransportToggle,
                       "the switches should have made room for the chip")
    }

    /// And it yields itself rather than pushing ✕ off the bar. #60 is the rule
    /// nothing on this bar is exempt from, the newest thing on it least of all.
    func testANarrowBarYieldsTheChipRatherThanTheWayOut() {
        for width in [iPhoneSE, iPhonePortrait] {
            let fit = ScoreBarLayout.fit(barWidth: width, omrBusy: true)
            XCTAssertFalse(fit.showsOMRProgress,
                           "a phone cannot seat the chip at \(width): "
                           + "ContentView draws it over the canvas instead")
            XCTAssertTrue(ScoreBarLayout.fits(fit, in: width),
                          "the bar overflows at \(width) while transcribing")
        }
    }

    /// Whatever the width, transcribing or not, the bar fits. This is the whole
    /// of #60 as one sweep, and it is a sweep rather than five widths because
    /// five widths missed a 40pt band where the thresholds and `fits` disagreed
    /// about the numeral for two releases.
    ///
    /// From 375, the narrowest bar the app has to seat: below that the last
    /// fallback has nothing left to give up and cannot fit anything at all.
    func testNoWidthOverflowsWhetherOrNotSomethingIsTranscribing() {
        for busy in [false, true] {
            for width in stride(from: iPhoneSE, through: 1400, by: 1) {
                let fit = ScoreBarLayout.fit(barWidth: width, omrBusy: busy)
                XCTAssertTrue(ScoreBarLayout.fits(fit, in: width),
                              "the bar overflows at \(width)pt (omrBusy: \(busy)): \(fit)")
            }
        }
    }
}

/// One switch, one place, at every width (0.6.8).
///
/// Performance mode and Show transport are top-bar controls now, and
/// `ScoreOptionsScreen` renders each one only where `Fit` says the bar could
/// not seat it. Both views read ONE `Fit` from ONE measurement, which is what
/// this pins: a width where a switch is in both places is a control that will
/// drift, and a width where it is in neither is a feature that is gone.
final class SwitchesHaveExactlyOneHomeTests: XCTestCase {

    func testEveryWidthPutsEachSwitchInExactlyOnePlace() {
        for busy in [false, true] {
            for width in stride(from: CGFloat(320), through: 1400, by: 1) {
                let fit = ScoreBarLayout.fit(barWidth: width, omrBusy: busy)
                // The two properties the two views actually read.
                XCTAssertNotEqual(fit.showsPerformanceToggle,
                                  fit.optionsCarriesPerformanceToggle,
                                  "Performance mode is in both places or neither "
                                  + "at \(width)pt")
                XCTAssertNotEqual(fit.showsTransportToggle,
                                  fit.optionsCarriesTransportToggle,
                                  "Show transport is in both places or neither "
                                  + "at \(width)pt")
            }
        }
    }

    /// An unmeasured bar shows everything, so Options must show nothing --
    /// otherwise the first frame of every score has two of each switch.
    func testAnUnmeasuredBarLeavesOptionsWithNeitherSwitch() {
        let fit = ScoreBarLayout.fit(barWidth: 0, omrBusy: true)
        XCTAssertTrue(fit.showsPerformanceToggle)
        XCTAssertTrue(fit.showsTransportToggle)
    }
}

/// Versions must stay reachable when the bar sheds its version count.
///
/// `ScoreBarLayout` has always said that dropping the count "drops a shortcut,
/// never a feature", because the title block opened the same dropdown. 0.6.3's
/// split of that band into two columns -- title opens arrangements, count opens
/// versions -- ended the guarantee without noticing, and a phone at reading
/// width was left with NO route to versions: the count yields below 390pt, and
/// the Versions section in Options leads only to a row that lives inside the
/// version column itself.
final class VersionsStayReachableTests: XCTestCase {

    /// The width at which the count goes is the width at which the title must
    /// take over. If this ever fails, a phone has lost version switching.
    func testAPhoneThatLosesTheCountKeepsTheTitleAsItsRoute() {
        let phone = ScoreBarLayout.fit(barWidth: 390)

        XCTAssertFalse(phone.showsVersions,
                       "the fixture is wrong: this width should shed the count")
        // The rule the title block implements: when the count has gone, the
        // title opens versions rather than arrangements.
        let opens: TitleBandLayout.Mode = phone.showsVersions ? .arrangements : .versions
        XCTAssertEqual(opens, .versions, "a phone has no route to versions")
    }

    /// On a bar wide enough to show both, they stay separate -- which is what
    /// 0.6.3 #8 asked for and must not be undone by the narrow-bar rule.
    func testAWideBarKeepsTheTwoColumnsApart() {
        let wide = ScoreBarLayout.fit(barWidth: 1180)

        XCTAssertTrue(wide.showsVersions)
        let opens: TitleBandLayout.Mode = wide.showsVersions ? .arrangements : .versions
        XCTAssertEqual(opens, .arrangements,
                       "the title should still open arrangements where the count exists")
    }
}
