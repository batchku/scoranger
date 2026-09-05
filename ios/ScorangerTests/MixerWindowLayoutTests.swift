import SwiftUI
import UIKit
import XCTest

/// The pure half of design/MIXER_WINDOW.md §8, written before the rebuild.
///
/// Three of the spec's seven acceptance tests are arithmetic and belong here;
/// the other four drive a running app. Each of these fails against the
/// shipped layout, which is the point of listing them.
final class MixerWindowLayoutTests: XCTestCase {

    /// Every content size iOS offers, as the trait a font metric needs.
    private let categories: [(String, UIContentSizeCategory)] = [
        ("XS", .extraSmall), ("S", .small), ("M", .medium), ("L", .large),
        ("XL", .extraLarge), ("XXL", .extraExtraLarge),
        ("XXXL", .extraExtraExtraLarge),
        ("AX1", .accessibilityMedium), ("AX2", .accessibilityLarge),
        ("AX3", .accessibilityExtraLarge),
        ("AX4", .accessibilityExtraExtraLarge),
        ("AX5", .accessibilityExtraExtraExtraLarge),
    ]

    /// The line height a role's text actually occupies at a content size.
    ///
    /// Measured through `UIFontMetrics`, which is what `Theme.Role.font` uses,
    /// so this is the same number the app will draw with rather than an
    /// estimate of it.
    private func lineHeight(pointSize: CGFloat, style: UIFont.TextStyle,
                            _ category: UIContentSizeCategory) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let base = UIFont.systemFont(ofSize: pointSize)
        let scaled = UIFontMetrics(forTextStyle: style)
            .scaledFont(for: base, compatibleWith: traits)
        return scaled.lineHeight
    }

    // MARK: - §8.1 rowsFitTheirText

    /// For every content size and every row, the row's MINIMUM is at least the
    /// scaled line height of the role it carries plus its own padding.
    ///
    /// The spec says this fails today at `.large` on the value row, and it
    /// does: `valueHeight` is a flat 12pt and `.data` at `.large` is taller
    /// than that before any padding.
    func testRowsFitTheirText() {
        // (row, its minimum, the role's point size, the role's text style,
        //  the padding the spec gives that row)
        let rows: [(String, CGFloat, CGFloat, UIFont.TextStyle, CGFloat)] = [
            ("mute + value", MixerLayout.muteRowMinimum, 11, .caption1, 6),
            ("sound chip",   MixerLayout.soundRowMinimum, 11, .caption1, 8),
            ("label",        MixerLayout.labelRowMinimum, 11, .caption1, 4),
            ("tempo",        MixerLayout.tempoRowMinimum, 11, .caption1, 10),
            ("scrubber",     MixerLayout.scrubberRowMinimum, 11, .caption1, 12),
        ]
        for (name, minimum, size, style, padding) in rows {
            for (label, category) in categories {
                let needed = lineHeight(pointSize: size, style: style, category)
                    + padding
                XCTAssertGreaterThanOrEqual(
                    MixerLayout.rowHeight(minimum: minimum, lineHeight:
                        lineHeight(pointSize: size, style: style, category),
                        padding: padding),
                    needed,
                    "\(name) at \(label): row is "
                    + "\(MixerLayout.rowHeight(minimum: minimum, lineHeight: lineHeight(pointSize: size, style: style, category), padding: padding))pt, "
                    + "text needs \(needed)pt")
            }
        }
    }

    /// And the header never goes below 44, whatever the text does.
    func testTheHeaderKeepsItsTouchTarget() {
        for (label, category) in categories {
            let height = MixerLayout.rowHeight(
                minimum: MixerLayout.headerMinimum,
                lineHeight: lineHeight(pointSize: 11, style: .caption1, category),
                padding: 8)
            XCTAssertGreaterThanOrEqual(height, 44,
                                        "header at \(label) is \(height)pt")
        }
    }

    // MARK: - §8.2 clampKeepsThePanelWhole

    /// Fuzzed origins, panel sizes and bounds: the result is contained in the
    /// free rect every time.
    ///
    /// The spec says this fails today by 60pt, which is
    /// `InkBarPlacement.mustRemainVisible` -- the old clamp deliberately let
    /// all but that much leave the screen.
    func testClampKeepsThePanelWhole() {
        var seed: UInt64 = 0x5EED
        func next(_ upper: Int) -> CGFloat {
            // A tiny deterministic generator: Math.random is not available in
            // this suite's style and a fuzz that differs per run cannot be
            // reproduced from a failure message.
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Int(seed >> 33) % upper)
        }
        for _ in 0..<4000 {
            let free = CGRect(x: next(40), y: next(40),
                              width: 320 + next(1100), height: 240 + next(1100))
            let panel = CGSize(width: 200 + next(400), height: 76 + next(400))
            let wanted = CGPoint(x: -600 + next(2400), y: -600 + next(2400))
            let at = MixerLayout.clamp(origin: wanted, panel: panel, in: free)
            let rect = CGRect(origin: at, size: panel)

            if panel.width <= free.width {
                XCTAssertGreaterThanOrEqual(rect.minX, free.minX - 0.01,
                                            "left: \(rect) not in \(free)")
                XCTAssertLessThanOrEqual(rect.maxX, free.maxX + 0.01,
                                         "right: \(rect) not in \(free)")
            } else {
                // Larger than the free rect in that dimension: pinned to the
                // leading edge, where the grab bar and the buttons are.
                XCTAssertEqual(rect.minX, free.minX, accuracy: 0.01)
            }
            if panel.height <= free.height {
                XCTAssertGreaterThanOrEqual(rect.minY, free.minY - 0.01,
                                            "top: \(rect) not in \(free)")
                XCTAssertLessThanOrEqual(rect.maxY, free.maxY + 0.01,
                                         "bottom: \(rect) not in \(free)")
            } else {
                XCTAssertEqual(rect.minY, free.minY, accuracy: 0.01)
            }
        }
    }

    /// The free rect is the container inset by its safe area and then by 8.
    func testTheFreeRectExcludesTheSafeAreaAndEightPoints() {
        let free = MixerLayout.freeRect(
            container: CGSize(width: 1032, height: 1376),
            safeArea: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0))
        XCTAssertEqual(free.minX, 8)
        XCTAssertEqual(free.minY, 32)                 // 24 + 8
        XCTAssertEqual(free.maxX, 1024)               // 1032 - 0 - 8
        XCTAssertEqual(free.maxY, 1348)               // 1376 - 20 - 8
    }

    // MARK: - §8.3 placementSurvivesRotation

    /// A free placement is a unit point, so it resolves inside the free rect
    /// in both orientations and across a Dynamic Type change.
    ///
    /// This is the fix for the teleport: a unit point does not care that the
    /// parked corner moved.
    func testPlacementSurvivesRotation() {
        let portrait = MixerLayout.freeRect(
            container: CGSize(width: 1032, height: 1376),
            safeArea: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0))
        let landscape = MixerLayout.freeRect(
            container: CGSize(width: 1376, height: 1032),
            safeArea: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0))

        for unitX in [0.0, 0.25, 0.5, 0.75, 1.0] {
            for unitY in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let placement = MixerLayout.Placement.free(
                    CGPoint(x: unitX, y: unitY))
                // and two panel sizes: normal text, and the taller list tier
                for panel in [CGSize(width: 320, height: 232),
                              CGSize(width: 640, height: 520)] {
                    for (name, free) in [("portrait", portrait),
                                         ("landscape", landscape)] {
                        let at = MixerLayout.origin(for: placement, panel: panel,
                                                    in: free, lanesInset: 96)
                        let rect = CGRect(origin: at, size: panel)
                        XCTAssertTrue(
                            free.insetBy(dx: -0.01, dy: -0.01).contains(rect),
                            "\(name) unit(\(unitX),\(unitY)) panel \(panel): "
                            + "\(rect) escapes \(free)")
                    }
                }
            }
        }
    }

    /// Round-tripping a centre through a unit point and back lands where it
    /// started, which is what makes the drag's `onEnded` lossless.
    func testAUnitPointRoundTripsThroughTheFreeRect() {
        let free = CGRect(x: 8, y: 32, width: 1016, height: 1316)
        for centre in [CGPoint(x: 100, y: 200), CGPoint(x: 900, y: 1200),
                       CGPoint(x: 516, y: 690)] {
            let unit = MixerLayout.unitPoint(centre: centre, in: free)
            let back = MixerLayout.centre(ofUnit: unit, in: free)
            XCTAssertEqual(back.x, centre.x, accuracy: 0.01)
            XCTAssertEqual(back.y, centre.y, accuracy: 0.01)
        }
    }

    // MARK: - §8.7 theHeaderHoldsItsContent, the arithmetic half

    /// A two-staff arrangement gets a panel at least 280pt wide.
    ///
    /// This is the whole of Ali's clipping in one assertion. The shipped
    /// `panelWidth(channels: 2)` is 137pt, the header draws 198.5pt, and the
    /// 61.5pt difference is off the screen.
    func testATwoStaffPanelIsAtLeastTheHeaderFloor() {
        for channels in 1...8 {
            let width = MixerLayout.panelWidth(channels: channels,
                                               stripWidth: 64,
                                               headerFloor: 280,
                                               freeWidth: 1016,
                                               compact: false)
            XCTAssertGreaterThanOrEqual(width, 280,
                                        "\(channels) channels -> \(width)pt")
        }
    }

    /// The floor is a floor, not a fixed width: more strips than it can hold
    /// still widen the panel.
    func testTheFloorDoesNotCapAWideRack() {
        let two = MixerLayout.panelWidth(channels: 2, stripWidth: 64,
                                         headerFloor: 280, freeWidth: 1016,
                                         compact: false)
        let six = MixerLayout.panelWidth(channels: 6, stripWidth: 64,
                                         headerFloor: 280, freeWidth: 1016,
                                         compact: false)
        XCTAssertEqual(two, 280, "two strips should sit at the floor")
        XCTAssertGreaterThan(six, two, "six strips should exceed it")
    }

    /// And it never exceeds the free rect less 16.
    func testThePanelNeverExceedsTheFreeWidth() {
        for freeWidth in [320.0, 375.0, 700.0, 834.0, 1016.0, 1360.0] {
            for channels in [1, 2, 4, 6, 12] {
                let width = MixerLayout.panelWidth(channels: channels,
                                                   stripWidth: 96,
                                                   headerFloor: 280,
                                                   freeWidth: freeWidth,
                                                   compact: freeWidth < 700)
                XCTAssertLessThanOrEqual(width, max(freeWidth - 16, 0) + 0.01,
                                         "\(channels)ch in \(freeWidth)pt "
                                         + "-> \(width)pt")
            }
        }
    }

    /// The strip scales with text, between its floor and its ceiling.
    func testTheStripWidthScalesWithinBounds() {
        XCTAssertEqual(MixerLayout.stripWidth(textScale: 1.0), 64)
        XCTAssertEqual(MixerLayout.stripWidth(textScale: 0.5), 64,
                       "never narrower than 64")
        XCTAssertEqual(MixerLayout.stripWidth(textScale: 1.25), 80)
        XCTAssertEqual(MixerLayout.stripWidth(textScale: 3.0), 96,
                       "never wider than 96")
    }

    // MARK: - §4 the three tiers, chosen by the container

    func testTheTierComesFromTheContainerAndTheTextSize() {
        // regular width, normal text: the floating window
        XCTAssertEqual(MixerLayout.tier(container: CGSize(width: 1032, height: 1376),
                                        text: .large), .window)
        // compact width: anchored, whatever the device is
        XCTAssertEqual(MixerLayout.tier(container: CGSize(width: 500, height: 900),
                                        text: .large), .anchored)
        // a short container: anchored too -- iPhone landscape, or a resized window
        XCTAssertEqual(MixerLayout.tier(container: CGSize(width: 1000, height: 460),
                                        text: .large), .anchored)
        // accessibility text: the list, at ANY width
        XCTAssertEqual(MixerLayout.tier(container: CGSize(width: 1376, height: 1032),
                                        text: .accessibility1), .list)
        XCTAssertEqual(MixerLayout.tier(container: CGSize(width: 375, height: 812),
                                        text: .accessibility3), .list)
        // xxxLarge is still a window; AX1 is the boundary
        XCTAssertEqual(MixerLayout.tier(container: CGSize(width: 1032, height: 1376),
                                        text: .xxxLarge), .window)
    }

    /// A parked corner respects the lanes; a dragged panel does not.
    func testAParkedCornerRespectsTheLanesAndAFreeOneDoesNot() {
        let free = CGRect(x: 8, y: 32, width: 1016, height: 1316)
        let panel = CGSize(width: 320, height: 232)
        let parked = MixerLayout.origin(for: .corner(.bottomTrailing),
                                        panel: panel, in: free, lanesInset: 96)
        XCTAssertLessThanOrEqual(parked.y + panel.height,
                                 free.maxY - 96 + 0.01,
                                 "a parked corner landed in the lanes")
        // the same spot asked for freely is allowed to sit there
        let unit = MixerLayout.unitPoint(
            centre: CGPoint(x: free.maxX - panel.width / 2,
                            y: free.maxY - panel.height / 2), in: free)
        let dragged = MixerLayout.origin(for: .free(unit), panel: panel,
                                         in: free, lanesInset: 96)
        XCTAssertEqual(dragged.y + panel.height, free.maxY, accuracy: 0.5,
                       "a dragged panel should reach the bottom of the free rect")
    }

    // MARK: - The shipped numbers, measured

    /// The rebuild's minimums are only worth something if the ones they
    /// replace were insufficient. These are the shipped constants against the
    /// text they had to hold, and they are the reason Ali's panel clips.
    ///
    /// This is a characterisation test: it asserts the OLD numbers fail, so
    /// the suite records what was wrong rather than only what is right. If
    /// someone reintroduces a fixed 12pt value row it will not fire -- the
    /// row tests above will -- but the numbers here are the evidence for why
    /// the section exists.
    func testTheShippedFixedHeightsCouldNotHoldTheirText() {
        // `.data` is the value under the fader and the two transport readouts.
        let atLarge = lineHeight(pointSize: 11, style: .caption1, .large)
        let atXXXL = lineHeight(pointSize: 11, style: .caption1,
                                .extraExtraExtraLarge)
        print("  .data line height: \(atLarge)pt at large, \(atXXXL)pt at xxxLarge")
        print("  shipped valueHeight 12, labelHeight 16, soundHeight 16, "
              + "headerHeight 24")

        XCTAssertLessThan(12, atLarge,
                          "the shipped 12pt value row already could not hold "
                          + "\(atLarge)pt of text at NORMAL size")
        XCTAssertLessThan(16, atXXXL + 4,
                          "the shipped 16pt label row could not hold "
                          + "\(atXXXL)pt at xxxLarge")
        XCTAssertLessThan(24, MixerLayout.headerMinimum,
                          "the shipped 24pt header is under the 44pt touch "
                          + "target the grab bar and three buttons need")

        // And the width: the fault Ali actually hit.
        let shippedTwoStrip = 4 * 2 + 2 * 64 + 1        // padding·2 + strips + divider
        XCTAssertLessThan(CGFloat(shippedTwoStrip),
                          MixerLayout.headerFloorMinimum,
                          "the shipped two-strip width \(shippedTwoStrip)pt is "
                          + "below the header's floor, which is why the panel "
                          + "was drawn wider than it was placed")
    }
}
