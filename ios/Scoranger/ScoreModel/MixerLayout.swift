import CoreGraphics
import Foundation

/// The mixer panel's geometry and where it parks.
///
/// Every number is from design/PLAYBACK_0.6.md §1 and §4. They live here rather
/// than in the view so the layout can be asserted without a screen -- a strip
/// that reserves the wrong height for its label is the kind of thing a
/// screenshot shows and a test pins.
enum MixerLayout {

    // MARK: - One strip (§1)

    static let stripWidth: CGFloat = 64
    static let muteHeight: CGFloat = 24
    static let muteSize = CGSize(width: 28, height: 24)
    static let faderHeight: CGFloat = 150
    static let faderTrackWidth: CGFloat = 6
    static let capSize = CGSize(width: 20, height: 12)
    static let ledWidth: CGFloat = 8
    static let ledInset: CGFloat = 6
    static let valueHeight: CGFloat = 18
    static let labelHeight: CGFloat = 28
    static let headerHeight: CGFloat = 32
    static let footerHeight: CGFloat = 40
    static let dividerWidth: CGFloat = 1
    static let padding: CGFloat = 8

    /// A muted strip does not vanish -- it dims. The LED keeps lighting at this
    /// opacity, because the staff IS playing and the reader simply cannot hear
    /// it, which is how they confirm the mute is working (§1).
    static let mutedOpacity: CGFloat = 0.42

    /// The fader's detent: the default sits here.
    static let detent = PlaybackGain.defaultFader

    /// How many strips are shown before the rack scrolls sideways.
    static let visibleStrips = 6
    static let visibleStripsCompact = 4

    /// 32 header + 24 mute + 150 fader + 18 value + 28 label + padding.
    static var panelHeight: CGFloat {
        headerHeight + muteHeight + faderHeight + valueHeight + labelHeight
            + padding * 2 + footerHeight
    }

    /// 8pt padding + n x 64 + 1pt dividers, capped at what fits.
    static func panelWidth(channels: Int, compact: Bool = false) -> CGFloat {
        let shown = max(1, min(channels, compact ? visibleStripsCompact : visibleStrips))
        return padding * 2 + CGFloat(shown) * stripWidth
            + CGFloat(max(0, shown - 1)) * dividerWidth
    }

    /// The rack scrolls when there are more channels than fit. The header and
    /// the footer do not scroll with it -- the scrubber belongs to the whole
    /// performance, not to whichever strips happen to be in view.
    static func scrolls(channels: Int, compact: Bool = false) -> Bool {
        channels > (compact ? visibleStripsCompact : visibleStrips)
    }

    // MARK: - The fader

    /// Where the cap sits for a fader value, as a fraction of travel from the
    /// BOTTOM. The track fills from the bottom, so 0 is empty and 10 is full.
    static func capOffset(forFader value: Int) -> CGFloat {
        let clamped = min(max(value, PlaybackGain.minimumFader), PlaybackGain.maximumFader)
        return CGFloat(clamped) / CGFloat(PlaybackGain.maximumFader)
    }

    /// The fader value for a drag, given how far up the track the finger is.
    ///
    /// Rounded, because the scale is 0-10 notches and not a continuum: a fader
    /// that lands between two numbers cannot be read back off the value under
    /// it. The gesture arrives in view coordinates where DOWN is positive, so
    /// the caller passes the fraction already flipped.
    static func fader(forOffset fraction: CGFloat) -> Int {
        let clamped = min(max(fraction, 0), 1)
        return Int((clamped * CGFloat(PlaybackGain.maximumFader)).rounded())
    }

    // MARK: - Parking (§1, §4)

    /// The four corners the grip cycles through.
    ///
    /// A tap-to-cycle, not only a drag: VoiceOver and Switch Control cannot
    /// drag, and a panel reachable only by dragging is a panel those readers
    /// cannot move at all. Same reasoning as the ink bar's tap-to-redock.
    enum Corner: Int, CaseIterable, Codable {
        case bottomTrailing, bottomLeading, topLeading, topTrailing

        var next: Corner {
            Corner(rawValue: (rawValue + 1) % Corner.allCases.count) ?? .bottomTrailing
        }

        var label: String {
            switch self {
            case .bottomTrailing: return "bottom right"
            case .bottomLeading: return "bottom left"
            case .topLeading: return "top left"
            case .topTrailing: return "top right"
            }
        }
    }

    /// Where a parked corner puts the panel, in the canvas's own space.
    ///
    /// `lanesInset` is how much of the bottom is already spoken for -- the ink
    /// bar's lane and the sync chip's, measured from whichever fixed chrome is
    /// showing. The mixer sits above the highest occupied lane (§4.4), so it
    /// never lands on top of a control that cannot move out of its way.
    static func origin(for corner: Corner, panel: CGSize, in bounds: CGSize,
                       lanesInset: CGFloat) -> CGPoint {
        let x: CGFloat
        switch corner {
        case .bottomTrailing, .topTrailing: x = bounds.width - panel.width - padding
        case .bottomLeading, .topLeading: x = padding
        }
        let y: CGFloat
        switch corner {
        case .bottomTrailing, .bottomLeading:
            y = bounds.height - panel.height - padding - lanesInset
        case .topLeading, .topTrailing:
            y = padding
        }
        return CGPoint(x: max(x, 0), y: max(y, 0))
    }

    /// Keep a dragged panel reachable.
    ///
    /// Deliberately the ink bar's rule and not a second one: `mustRemainVisible`
    /// of it stays on screen, so a panel pushed at an edge can always be taken
    /// hold of again. Two movable panels with two different escape rules is how
    /// a reader learns that one of them traps them.
    static func clamp(_ origin: CGPoint, panel: CGSize, in bounds: CGSize) -> CGPoint {
        let keep = InkBarPlacement.mustRemainVisible
        let minX = -(panel.width - min(keep, panel.width))
        let maxX = bounds.width - min(keep, panel.width)
        let minY: CGFloat = 0
        let maxY = bounds.height - min(keep, panel.height)
        return CGPoint(x: min(max(origin.x, minX), max(maxX, minX)),
                       y: min(max(origin.y, minY), max(maxY, minY)))
    }
}
