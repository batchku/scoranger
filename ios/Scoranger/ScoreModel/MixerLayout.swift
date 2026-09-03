import CoreGraphics
import Foundation

/// The mixer panel's geometry and where it parks.
///
/// Every number is from design/PLAYBACK_0.6.md §1 and §4. They live here rather
/// than in the view so the layout can be asserted without a screen -- a strip
/// that reserves the wrong height for its label is the kind of thing a
/// screenshot shows and a test pins.
enum MixerLayout {

    // MARK: - One strip (§1, halved in 0.6.3)

    /// The panel the spec drew was 308pt tall and it covered a third of an
    /// iPad's score. The reader asked for half. Every vertical number below is
    /// cut to roughly half its §1 value; the WIDTHS are untouched, because a
    /// 64pt strip is already the narrowest a two-line staff label reads at.
    ///
    /// What the halving costs, stated so it is a decision and not an accident:
    /// the fader keeps 20pt of travel for eleven notches, so a DRAG is coarse.
    /// Precision did not go with it -- a tap anywhere on the track jumps to
    /// that notch, the `.adjustable` VoiceOver action steps one at a time, and
    /// the value is printed under the cap. The fader can still be set exactly;
    /// it just cannot be set exactly by dragging.
    static let specPanelHeight: CGFloat = 308

    static let stripWidth: CGFloat = 64
    static let muteHeight: CGFloat = 16
    static let muteSize = CGSize(width: 26, height: 16)
    static let faderHeight: CGFloat = 30
    static let faderTrackWidth: CGFloat = 6
    static let capSize = CGSize(width: 20, height: 10)
    static let ledWidth: CGFloat = 8
    static let ledInset: CGFloat = 6
    static let valueHeight: CGFloat = 12
    /// The sound row: which General MIDI patch the channel is played with, and
    /// the way to change it (0.6.5). One 16pt row under the value, the same
    /// height as the mute and the label -- the strip already has two rows at
    /// that height and a third does not introduce a new one.
    ///
    /// This is the ONLY thing the panel grew for. 154 -> 170: the fader kept
    /// its 30pt, the label kept its 16, nothing was squeezed to pay for it,
    /// because a 14pt fader to save 2pt would have cost the control the reader
    /// uses most to buy back a fifth of a row.
    static let soundHeight: CGFloat = 16
    /// The chip is the strip minus its side padding, which is what the label
    /// already measures.
    static let soundWidth: CGFloat = stripWidth - 8
    /// One line now, not two. At 16pt a second line does not fit; the full
    /// staff name stays in the strip's accessibility label, which is where a
    /// truncated caption is supposed to survive.
    static let labelHeight: CGFloat = 16
    static let headerHeight: CGFloat = 24
    static let footerHeight: CGFloat = 24
    /// The tempo band: one horizontal slider in a row of its own, between the
    /// strips and the scrubber, with a rule above and below it. It is NOT a
    /// channel -- it belongs to the whole performance, like the scrubber --
    /// so it is separated from the rack and drawn in a different colour.
    static let tempoHeight: CGFloat = 24
    static let tempoTrackHeight: CGFloat = 4
    static let dividerWidth: CGFloat = 1
    static let padding: CGFloat = 4

    /// A muted strip does not vanish -- it dims. The LED keeps lighting at this
    /// opacity, because the staff IS playing and the reader simply cannot hear
    /// it, which is how they confirm the mute is working (§1).
    static let mutedOpacity: CGFloat = 0.42

    /// The fader's detent: the default sits here.
    static let detent = PlaybackGain.defaultFader

    /// How many strips are shown before the rack scrolls sideways.
    static let visibleStrips = 6
    static let visibleStripsCompact = 4

    /// The rack: what one strip occupies, top to bottom, plus its padding.
    static var rackHeight: CGFloat {
        muteHeight + faderHeight + valueHeight + soundHeight + labelHeight
            + padding * 2
    }

    /// 24 header + 16 mute + 30 fader + 12 value + 16 sound + 16 label
    /// + 8 padding + 24 tempo + 24 scrubber = 170.
    ///
    /// It was 154, exactly half of the 308 §1 drew. The sound row is 16pt of
    /// that half back, and the number is said out loud rather than buried
    /// because the reader asked for half and will measure it by eye: the panel
    /// is 170pt, 55% of the spec, one row taller than the version they signed
    /// off. Nothing else moved.
    static var panelHeight: CGFloat {
        headerHeight + rackHeight + tempoHeight + footerHeight
    }

    // MARK: - The sound picker (0.6.5)

    /// The picker opens OVER the rack, in the panel that opened it, rather
    /// than as a sheet or a popover: this app has no modals left (§7.3 of
    /// NAV_MODAL_FREE_0.4.2), and a stock `Picker` would put a wheel of 128
    /// rows in a panel whose every other control is drawn by hand.
    ///
    /// Two columns, the way the catalogue is shaped: General MIDI's sixteen
    /// families on the left, the eight sounds of the chosen one on the right.
    /// A flat 128-row list is the thing the grouping exists to avoid.
    static let pickerWidth: CGFloat = 300
    static let pickerFamilyWidth: CGFloat = 116
    static let pickerRowHeight: CGFloat = 22
    /// Seven rows. The instrument column never needs more -- a family is eight
    /// sounds and the drum kits are nine -- so only the family column scrolls,
    /// and the reader is never hunting in two scrolling lists at once.
    static let pickerListHeight: CGFloat = 154
    /// "Back to the guess" and "every staff on this sound", which is the ask
    /// the whole feature came from.
    static let pickerFooterHeight: CGFloat = 30

    /// 24 header + 154 lists + 30 footer = 208, and only while it is open.
    static var pickerPanelHeight: CGFloat {
        headerHeight + pickerListHeight + pickerFooterHeight
    }

    /// What the panel measures right now. The picker is taller than the rack
    /// and wider than a one-strip panel, so the layer that parks the panel has
    /// to ask rather than assume -- a panel that grew without its parking
    /// knowing would open off the bottom of the canvas.
    static func panelSize(channels: Int, compact: Bool = false,
                          picking: Bool = false) -> CGSize {
        guard picking else {
            return CGSize(width: panelWidth(channels: channels, compact: compact),
                          height: panelHeight)
        }
        return CGSize(width: max(pickerWidth,
                                 panelWidth(channels: channels, compact: compact)),
                      height: pickerPanelHeight)
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
