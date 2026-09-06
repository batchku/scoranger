import CoreGraphics
import SwiftUI

/// The mixer window's geometry: minimums, tiers, placement and clamping.
///
/// Implements design/MIXER_WINDOW.md, which supersedes PLAYBACK_0.6 §1's
/// geometry and §4's parking. It is a separate file from the old `MixerLayout`
/// numbers on purpose -- the two describe different objects, and the shipped
/// ones are what Ali's iPad clips.
///
/// **The rule the whole thing reduces to: nothing here returns a height.** It
/// returns MINIMUMS, and the view takes `.frame(minHeight:)` around text that
/// is free to be as tall as it needs. The shipped layout returned heights --
/// `valueHeight = 12`, `labelHeight = 16` -- and a fixed frame around scaling
/// text is a clip waiting for a content size.
///
/// The width story is the same fault in the other axis and is what Ali
/// actually hit: `panelWidth` was `8 + strips * 64 + dividers`, so a
/// two-staff score computed 137pt while its header drew 198.5pt, and the
/// panel was positioned by the number rather than by the drawing. Hence
/// `headerFloor`, measured and never below 280.
extension MixerLayout {

    // MARK: - Minimums (§2). Never heights.

    /// The header's touch target. 44 because the grab bar, park, collapse and
    /// close all live in it and each is a 44pt square.
    static let headerMinimum: CGFloat = 44
    static let muteRowMinimum: CGFloat = 24
    static let soundRowMinimum: CGFloat = 24
    static let labelRowMinimum: CGFloat = 20
    static let tempoRowMinimum: CGFloat = 28
    static let scrubberRowMinimum: CGFloat = 32
    static let rackPaddingMinimum: CGFloat = 8

    /// The fader absorbs the slack and is the first thing to give.
    static let faderIdeal: CGFloat = 44
    static let faderFloor: CGFloat = 32
    static let faderCeiling: CGFloat = 120

    /// Every control in the header, and the master column's buttons.
    static let controlSide: CGFloat = 44
    /// `All on` / `All off`, pinned at the rack's leading edge, outside the
    /// horizontal scroll (§1.5).
    static let masterColumnWidth: CGFloat = 45
    static let masterButtonMinimum: CGFloat = 22

    /// The panel's width floor: its four header controls, and the padding.
    ///
    /// This was 280 -- what the header needed for a title, a voices summary
    /// and three trailing controls -- and 280 on a 393pt phone is most of the
    /// screen. MIXER_WINDOW §12 found the loop that made: the panel was
    /// full-width BECAUSE it was anchored, and anchored BECAUSE it was
    /// full-width. One mistake wearing two faces.
    ///
    /// So the floor is the four controls it cannot do without -- grab,
    /// collapse, park, close -- and the title and the summary appear only once
    /// the rack has bought room for them (`headerShowsTitle`). At the floor
    /// the header IS its controls, with no inert middle to measure.
    static let windowFloor: CGFloat = controlSide * 4 + padding * 2

    /// Kept under the name the view's `minWidth` already used, now meaning
    /// the floor above rather than the 280 that caused the bug.
    static var headerFloorMinimum: CGFloat { windowFloor }

    /// Above this the header can afford its title and its voices summary.
    ///
    /// It is the rack at three strips: a three-channel score already needs
    /// 248pt, so the words cost nothing there. At two channels the panel is at
    /// its floor and they would be the only reason it was wider.
    static let headerTitleMinimum: CGFloat = 248

    static func headerShowsTitle(width: CGFloat) -> Bool {
        width >= headerTitleMinimum
    }

    /// The strip's own width, scaled by text and bounded.
    static let stripWidthFloor: CGFloat = 64
    static let stripWidthCeiling: CGFloat = 96

    /// Collapsed: header + scrubber, and nothing else (§1.3).
    static var collapsedMinimum: CGFloat { headerMinimum + scrubberRowMinimum }

    /// A row is the larger of its minimum and what its text needs.
    ///
    /// The one function every row in the panel goes through, so a row that
    /// clips is a row that did not call it.
    static func rowHeight(minimum: CGFloat, lineHeight: CGFloat,
                          padding: CGFloat) -> CGFloat {
        max(minimum, lineHeight + padding)
    }

    /// The text factor this layout scales by. Measured, never a table.
    static func textScale(_ size: DynamicTypeSize) -> CGFloat {
        TextScale.factor(size)
    }

    /// The strip's own width at a text size, which is the form a view wants.
    static func stripWidth(text size: DynamicTypeSize) -> CGFloat {
        stripWidth(textScale: textScale(size))
    }

    /// The strip scales with text between 64 and 96 (§2).
    static func stripWidth(textScale: CGFloat) -> CGFloat {
        min(max(stripWidthFloor * textScale, stripWidthFloor), stripWidthCeiling)
    }

    /// What the rack needs for `n` strips: its padding, the pinned master
    /// column and its divider, the strips, and a divider between each pair.
    static func rackWidth(strips: Int, stripWidth: CGFloat) -> CGFloat {
        let n = max(1, strips)
        return padding * 2 + masterColumnWidth + dividerWidth
            + CGFloat(n) * stripWidth
            + CGFloat(n - 1) * dividerWidth
    }

    /// The panel's width: SIZED TO ITS CHANNELS (§12).
    ///
    /// Two channels want 184, three 248, four 313; five and more get 313 and
    /// the rack scrolls inside it. That is the whole ruling, and it is why
    /// there is no anchored tier any more -- a 184pt window has somewhere to
    /// go on a 393pt phone, so nothing needs pinning.
    ///
    /// The measured header no longer appears here. It was the 0.6.12 fix for a
    /// panel positioned by a number while drawing wider, and it stops being
    /// needed once the header at floor width is nothing but its four squares:
    /// there is no text left in it to outgrow the number.
    static func panelWidth(channels: Int, stripWidth: CGFloat,
                           freeWidth: CGFloat, compact: Bool) -> CGFloat {
        let cap = compact ? visibleStripsCompact : visibleStrips
        let shown = max(1, min(channels, cap))
        let wanted = max(windowFloor, rackWidth(strips: shown,
                                                stripWidth: stripWidth))
        // The ceiling is the rack at its visible-strip cap, so a fifteen-staff
        // score is the same window as a four-staff one with more to scroll.
        let ceiling = max(windowFloor, rackWidth(strips: cap,
                                                 stripWidth: stripWidth))
        // And never wider than the space it must fit inside, which is the
        // other half of "no clipping".
        return min(min(wanted, ceiling), max(freeWidth - 16, 0))
    }

    // MARK: - The three tiers (§4), chosen by the container

    /// Which layout the mixer takes.
    ///
    /// From the CONTAINER and the text size, never from the device: a resized
    /// window, a Slide Over and an iPhone all get the right answer for free,
    /// and there is no device check to be wrong about a device that does not
    /// exist yet.
    enum Tier: Equatable {
        /// A floating window that can be picked up (§4.1). Every width.
        case window
        /// One channel per row with a horizontal fader (§4.3). A vertical
        /// fader with 33pt labels is not an object anyone can use.
        case list
    }

    /// Whether the rack shows four strips rather than six.
    ///
    /// It is about how many STRIPS fit, which is the only thing it decides --
    /// not about what kind of device this is. The old test asked
    /// `container.width < 700`, and an iPhone in landscape is 852 points
    /// wide: the phone was therefore "compact" in portrait and "regular" on
    /// its side. That is the same defect IPHONE_0.6.14 §0 found in the score
    /// view, and it is why the mixer could not be dragged in either
    /// orientation -- the width clause caught portrait and the height clause
    /// caught landscape.
    static func narrowRack(freeWidth: CGFloat, stripWidth: CGFloat) -> Bool {
        freeWidth - 16 < rackWidth(strips: visibleStrips, stripWidth: stripWidth)
    }

    /// Which layout the mixer takes.
    ///
    /// A WINDOW, everywhere. §12's ruling: the panel is sized to its channels
    /// -- 184pt at two, 313 at four -- and a window that small has somewhere
    /// to go on the narrowest phone, so there is nothing left for anchoring to
    /// solve. The anchored tier is gone rather than left unreachable; a dead
    /// tier is an invitation to bring it back.
    ///
    /// `.list` stays, and it is the one case that was never about room: at an
    /// accessibility size a vertical fader with 33pt labels is not an object
    /// anyone can use at any width.
    static func tier(container: CGSize, text: DynamicTypeSize) -> Tier {
        text >= .accessibility1 ? .list : .window
    }

    /// Does the mixer open COLLAPSED?
    ///
    /// The phone rule (§12): where the panel at its natural height would take
    /// more than 60% of the canvas, it opens as its header and scrubber and
    /// waits to be expanded. It bites in landscape, whose canvas is about
    /// 284pt; a 635pt portrait canvas opens expanded.
    static let collapseAbove: CGFloat = 0.6

    static func opensCollapsed(naturalHeight: CGFloat,
                               canvasHeight: CGFloat) -> Bool {
        guard canvasHeight > 0, naturalHeight > 0 else { return false }
        return naturalHeight > canvasHeight * collapseAbove
    }

    // MARK: - Placement (§5)

    /// Where the window is, as something that survives a rotation.
    ///
    /// A stored translation does not: `home` moves when the container does,
    /// and the panel teleports by the difference. A unit point of the free
    /// rect maps into any new free rect and is inside by construction.
    enum Placement: Codable, Equatable {
        case corner(Corner)
        /// The panel's CENTRE as a unit point of the free rect.
        case free(CGPoint)
    }

    /// The container inset by its safe area, then by 8pt.
    ///
    /// The safe area is why the shipped panel could sit under the home
    /// indicator and still measure "inside the window": the window frame is
    /// the whole display.
    static let freeInset: CGFloat = 8

    static func freeRect(container: CGSize, safeArea: EdgeInsets) -> CGRect {
        let x = safeArea.leading + freeInset
        let y = safeArea.top + freeInset
        let width = container.width - safeArea.leading - safeArea.trailing
            - freeInset * 2
        let height = container.height - safeArea.top - safeArea.bottom
            - freeInset * 2
        return CGRect(x: x, y: y, width: max(width, 0), height: max(height, 0))
    }

    /// The centre a unit point names, and back again.
    static func centre(ofUnit unit: CGPoint, in free: CGRect) -> CGPoint {
        CGPoint(x: free.minX + unit.x * free.width,
                y: free.minY + unit.y * free.height)
    }

    static func unitPoint(centre: CGPoint, in free: CGRect) -> CGPoint {
        guard free.width > 0, free.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: (centre.x - free.minX) / free.width,
                       y: (centre.y - free.minY) / free.height)
    }

    /// Keep the panel WHOLLY inside the free rect.
    ///
    /// No `mustRemainVisible`. That rule belongs to the ink bar, which is a
    /// 60pt object a reader deliberately shoves aside; a window whose header
    /// can leave the screen is a window that cannot be dragged back. Larger
    /// than the free rect in a dimension pins to the leading edge, where the
    /// grab bar and the three buttons are -- §2 and §3 exist so that cannot
    /// happen, and this is what it does if they ever fail.
    static func clamp(origin: CGPoint, panel: CGSize, in free: CGRect) -> CGPoint {
        let x: CGFloat = panel.width <= free.width
            ? min(max(origin.x, free.minX), free.maxX - panel.width)
            : free.minX
        let y: CGFloat = panel.height <= free.height
            ? min(max(origin.y, free.minY), free.maxY - panel.height)
            : free.minY
        return CGPoint(x: x, y: y)
    }

    /// Where a placement puts the panel, clamped.
    ///
    /// A PARKED corner respects `lanesInset` so it never lands on the ink bar
    /// or the sync chip. A FREELY dragged panel may go anywhere in the free
    /// rect -- the reader put it there, the same latitude the ink bar got.
    static func origin(for placement: Placement, panel: CGSize,
                       in free: CGRect, lanesInset: CGFloat) -> CGPoint {
        switch placement {
        case .corner(let corner):
            let lanes = free.insetBy(dx: 0, dy: 0)
            let bottom = max(lanes.maxY - lanesInset, lanes.minY + panel.height)
            let x: CGFloat
            switch corner {
            case .bottomTrailing, .topTrailing: x = free.maxX - panel.width
            case .bottomLeading, .topLeading:   x = free.minX
            }
            let y: CGFloat
            switch corner {
            case .bottomTrailing, .bottomLeading: y = bottom - panel.height
            case .topLeading, .topTrailing:       y = free.minY
            }
            return clamp(origin: CGPoint(x: x, y: y), panel: panel, in: free)
        case .free(let unit):
            let centre = centre(ofUnit: unit, in: free)
            return clamp(origin: CGPoint(x: centre.x - panel.width / 2,
                                         y: centre.y - panel.height / 2),
                         panel: panel, in: free)
        }
    }
}
