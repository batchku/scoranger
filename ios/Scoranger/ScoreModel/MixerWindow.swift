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

    /// The panel's width floor when the header has not been measured yet, and
    /// the floor under any measurement. 280 is what the header needs at
    /// normal text with room for the three trailing controls.
    static let headerFloorMinimum: CGFloat = 280

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

    /// The strip scales with text between 64 and 96 (§2).
    static func stripWidth(textScale: CGFloat) -> CGFloat {
        min(max(stripWidthFloor * textScale, stripWidthFloor), stripWidthCeiling)
    }

    /// The panel's width.
    ///
    /// `headerFloor` is MEASURED by the view and passed in; the floor under it
    /// is `headerFloorMinimum`. The rack's contribution can exceed the floor,
    /// which is why this is a `max` and not a fixed width -- a six-strip rack
    /// still gets its room. Capped at the free rect less 16 so the panel can
    /// never be asked to be wider than the space it must fit inside.
    static func panelWidth(channels: Int, stripWidth: CGFloat,
                           headerFloor: CGFloat, freeWidth: CGFloat,
                           compact: Bool) -> CGFloat {
        let shown = max(1, min(channels, compact ? visibleStripsCompact
                                                 : visibleStrips))
        let rack = padding * 2 + masterColumnWidth + dividerWidth
            + CGFloat(shown) * stripWidth
            + CGFloat(max(0, shown - 1)) * dividerWidth
        let wanted = max(max(headerFloor, headerFloorMinimum), rack)
        return min(wanted, max(freeWidth - 16, 0))
    }

    // MARK: - The three tiers (§4), chosen by the container

    /// Which layout the mixer takes.
    ///
    /// From the CONTAINER and the text size, never from the device: a resized
    /// window, a Slide Over and an iPhone all get the right answer for free,
    /// and there is no device check to be wrong about a device that does not
    /// exist yet.
    enum Tier: Equatable {
        /// A floating window that can be picked up (§4.1).
        case window
        /// Anchored full-width above the chrome; nowhere to move it, so no
        /// grab bar and no park button (§4.2).
        case anchored
        /// One channel per row with a horizontal fader (§4.3). A vertical
        /// fader with 33pt labels is not an object anyone can use.
        case list
    }

    /// Below this the container is compact and the window has nowhere to go.
    static let compactWidth: CGFloat = 700
    /// Below this there is not enough height for a window either.
    static let shortHeight: CGFloat = 500

    static func tier(container: CGSize, text: DynamicTypeSize) -> Tier {
        // Text first: at accessibility sizes the DAW layout stops being
        // legible at any width, and that outranks how much room there is.
        if text >= .accessibility1 { return .list }
        if container.width < compactWidth || container.height < shortHeight {
            return .anchored
        }
        return .window
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
