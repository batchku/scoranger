import SwiftUI

/// The window's contents: a channel as a strip, a channel as a row, the two
/// sliders and the sound picker.
///
/// Split from `MixerWindowPanel` because that file is the SHELL -- the header
/// you pick the window up by, and which tier is showing -- and these are what
/// it holds. The rule from design/MIXER_WINDOW.md §2 governs every one of
/// them: **no fixed frame around text.** Rows take `.frame(minHeight:)`, text
/// takes `.fixedSize`, and the fader absorbs the slack.
///
/// What that replaces: `valueHeight = 12` around `.data`, which is 13.13pt at
/// NORMAL text -- the value under every fader was clipped on every device
/// before Dynamic Type was involved.

// MARK: - A channel as a strip (the window and anchored tiers)

struct MixerChannelStrip: View {
    @ObservedObject var playback: PlaybackEngine
    let part: PlaybackTimeline.Part
    let label: String
    let width: CGFloat
    var onPickSound: () -> Void

    private var isOn: Bool { playback.voices.isOn(part.index) }
    private var fader: Int { playback.voices.fader(part.index) }
    /// The staff IS playing when muted -- that is how a reader confirms the
    /// mute works -- so the lamp follows the music and dims with the strip.
    private var isSounding: Bool { part.isSounding(at: playback.beat) }

    var body: some View {
        VStack(spacing: 0) {
            MixerMuteButton(playback: playback, part: part)
            HStack(spacing: MixerLayout.ledInset) {
                MixerFader(playback: playback, part: part)
                MixerLED(on: isSounding, part: part)
            }
            .frame(minHeight: MixerLayout.faderIdeal)
            Text("\(fader)").typeRole(.data)
                .foregroundStyle(Theme.Ink.ink3)
                .fixedSize()
                .frame(minHeight: MixerLayout.muteRowMinimum - 12)
                .accessibilityIdentifier("mixer-value-\(part.index)")
                .accessibilityHidden(true)
            MixerSoundChip(playback: playback, part: part, action: onPickSound)
            // Two lines, and `.fixedSize` so the text decides its own height.
            // It was one line in a 16pt frame, which is where "Accordi…" came
            // from on Ali's two-staff score.
            Text(label).typeRole(.meta)
                .foregroundStyle(Theme.Ink.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: MixerLayout.labelRowMinimum)
                .padding(.horizontal, 2)
                .accessibilityIdentifier("mixer-label-\(part.index)")
                .accessibilityHidden(true)
        }
        .frame(width: width)
        .padding(.vertical, MixerLayout.rackPaddingMinimum / 2)
        .opacity(isOn ? 1 : MixerLayout.mutedOpacity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("strip-\(part.index)")
        .accessibilityLabel(part.name)
    }
}

// MARK: - A channel as a row (the list tier, §4.3)

/// One channel per row, with a HORIZONTAL fader.
///
/// A vertical fader with 33pt labels is not an object anyone can use, so at
/// accessibility sizes the layout changes rather than the type shrinking. The
/// DAW rack is a rendering of the model, not the model.
struct MixerChannelRow: View {
    @ObservedObject var playback: PlaybackEngine
    let part: PlaybackTimeline.Part
    let label: String
    var onPickSound: () -> Void

    private var isOn: Bool { playback.voices.isOn(part.index) }
    private var fader: Int { playback.voices.fader(part.index) }

    var body: some View {
        HStack(spacing: Theme.Metric.s8) {
            MixerMuteButton(playback: playback, part: part)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).typeRole(.row)
                    .foregroundStyle(Theme.Ink.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mixer-label-\(part.index)")
                MixerSoundChip(playback: playback, part: part, action: onPickSound)
            }
            Spacer(minLength: Theme.Metric.s8)
            MixerHorizontalFader(playback: playback, part: part)
                .frame(minWidth: 100)
            Text("\(fader)").typeRole(.data)
                .foregroundStyle(Theme.Ink.ink3)
                .fixedSize()
                .frame(minWidth: 22, alignment: .trailing)
                .accessibilityIdentifier("mixer-value-\(part.index)")
        }
        .padding(.horizontal, Theme.Metric.s12)
        .padding(.vertical, 6)
        .frame(minHeight: MixerLayout.controlSide)
        .opacity(isOn ? 1 : MixerLayout.mutedOpacity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("strip-\(part.index)")
    }
}

// MARK: - The shared controls

struct MixerMuteButton: View {
    @ObservedObject var playback: PlaybackEngine
    let part: PlaybackTimeline.Part

    private var isOn: Bool { playback.voices.isOn(part.index) }

    var body: some View {
        Button { playback.voices.toggle(part.index) } label: {
            Text("M").typeRole(.label)
                .foregroundStyle(isOn ? Theme.Ink.ink2 : Theme.Surface.panel)
                .fixedSize()
                .padding(.horizontal, 6)
                .frame(minWidth: 26, minHeight: MixerLayout.muteRowMinimum)
                .background(isOn ? Theme.Surface.well : Theme.Ink.ink2)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(Theme.Line.line2, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("strip-mute-\(part.index)")
        .accessibilityLabel("\(part.name), mute")
        .accessibilityValue(isOn ? "off" : "on")
    }
}

/// The activity lamp. Not decorative: whether a staff is sounding right now
/// is the one thing in the strip a non-visual reader cannot get any other
/// way, so it is an element with a value rather than a hidden circle.
struct MixerLED: View {
    let on: Bool
    let part: PlaybackTimeline.Part

    var body: some View {
        ZStack {
            Circle().fill(on ? Theme.Status.ok : Theme.Line.line2)
            if on {
                Circle().stroke(Theme.Status.ok.opacity(0.22), lineWidth: 3)
                    .frame(width: MixerLayout.ledWidth + 3,
                           height: MixerLayout.ledWidth + 3)
            }
        }
        .frame(width: MixerLayout.ledWidth, height: MixerLayout.ledWidth)
        .accessibilityIdentifier("strip-led-\(part.index)")
        .accessibilityLabel("\(part.name), sounding")
        .accessibilityValue(on ? "yes" : "no")
    }
}

/// The vertical fader. Fills from the bottom; a tap anywhere jumps to that
/// notch, which is what keeps it precise now that the travel is short.
struct MixerFader: View {
    @ObservedObject var playback: PlaybackEngine
    let part: PlaybackTimeline.Part

    private var fader: Int { playback.voices.fader(part.index) }

    var body: some View {
        GeometryReader { geo in
            let fraction = MixerLayout.capOffset(forFader: fader)
            ZStack(alignment: .bottom) {
                Capsule().fill(Theme.Surface.well)
                    .frame(width: MixerLayout.faderTrackWidth)
                Capsule().fill(Theme.Accent.clay)
                    .frame(width: MixerLayout.faderTrackWidth,
                           height: geo.size.height * fraction)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.Surface.panel)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Theme.Line.line2, lineWidth: 1)
                    }
                    .frame(width: MixerLayout.capSize.width,
                           height: MixerLayout.capSize.height)
                    .offset(y: -(geo.size.height - MixerLayout.capSize.height)
                               * fraction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let up = 1 - (value.location.y / max(geo.size.height, 1))
                        playback.setFader(MixerLayout.fader(forOffset: up),
                                          channel: part.index)
                    })
        }
        .frame(minHeight: MixerLayout.faderFloor)
        .accessibilityElement()
        .accessibilityIdentifier("strip-fader-\(part.index)")
        .accessibilityLabel("\(part.name), level")
        // "N of 10" and not a bare number: a value with no scale does
        // not say whether 7 is loud. Read by
        // testTheMixerOpensWithAStripPerStaff.
        .accessibilityValue("\(fader) of \(PlaybackGain.maximumFader)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: playback.setFader(fader + 1, channel: part.index)
            case .decrement: playback.setFader(fader - 1, channel: part.index)
            @unknown default: break
            }
        }
    }
}

/// The list tier's fader: the same control on its side.
struct MixerHorizontalFader: View {
    @ObservedObject var playback: PlaybackEngine
    let part: PlaybackTimeline.Part

    private var fader: Int { playback.voices.fader(part.index) }

    var body: some View {
        GeometryReader { geo in
            let fraction = MixerLayout.capOffset(forFader: fader)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Surface.well)
                    .frame(height: MixerLayout.faderTrackWidth)
                Capsule().fill(Theme.Accent.clay)
                    .frame(width: geo.size.width * fraction,
                           height: MixerLayout.faderTrackWidth)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.Surface.panel)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Theme.Line.line2, lineWidth: 1)
                    }
                    .frame(width: MixerLayout.capSize.height,
                           height: MixerLayout.capSize.width)
                    .offset(x: (geo.size.width - MixerLayout.capSize.height)
                               * fraction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        playback.setFader(
                            MixerLayout.fader(forOffset:
                                value.location.x / max(geo.size.width, 1)),
                            channel: part.index)
                    })
        }
        .frame(minHeight: MixerLayout.controlSide - 12)
        .accessibilityElement()
        .accessibilityIdentifier("strip-fader-\(part.index)")
        .accessibilityLabel("\(part.name), level")
        // "N of 10" and not a bare number: a value with no scale does
        // not say whether 7 is loud. Read by
        // testTheMixerOpensWithAStripPerStaff.
        .accessibilityValue("\(fader) of \(PlaybackGain.maximumFader)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: playback.setFader(fader + 1, channel: part.index)
            case .decrement: playback.setFader(fader - 1, channel: part.index)
            @unknown default: break
            }
        }
    }
}

/// Which General MIDI patch the channel plays, and the way to change it.
///
/// `.fixedSize` and a minimum rather than a 16pt box: this is the chip that
/// read "Accordi…" on a two-staff score. Tapping the LABEL opens the picker
/// too (§4.2) -- the chip is the visible affordance, the label the larger
/// target -- which is why both carry the same action.
struct MixerSoundChip: View {
    @ObservedObject var playback: PlaybackEngine
    let part: PlaybackTimeline.Part
    var action: () -> Void

    var body: some View {
        let patch = playback.instrument(for: part)
        let chosen = playback.hasChosenInstrument(for: part)
        return Button(action: action) {
            HStack(spacing: 1) {
                Text(GeneralMIDI.short(program: patch.program, bank: patch.bank))
                    .typeRole(.meta)
                    .foregroundStyle(chosen ? Theme.Accent.clayStrong : Theme.Ink.ink2)
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Theme.Ink.ink3)
            }
            .padding(.horizontal, 4)
            .frame(minHeight: MixerLayout.soundRowMinimum)
            .background(chosen ? Theme.Accent.clayTint : Theme.Surface.well)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                    .stroke(chosen ? Theme.Accent.clayBorder : Theme.Line.line2,
                            lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("strip-sound-\(part.index)")
        .accessibilityLabel("\(part.name), sound")
        // "automatic" and not "from the staff name": the sound under an
        // untouched channel comes from the notation's own program where there
        // was one and from the staff name only where there was not, and a
        // value naming the wrong one would be a lie in the place a non-visual
        // reader has to trust. The suffix is a CONTRACT --
        // testTheMixerChoosesTheSoundAChannelIsPlayedWith reads it -- and the
        // rebuild dropped it until that test said so.
        .accessibilityValue(GeneralMIDI.name(program: patch.program,
                                             bank: patch.bank)
                            + (chosen ? ", chosen" : ", automatic"))
        .accessibilityHint("Opens the list of sounds")
    }
}

/// The tempo, live while the music plays: a practice tempo is found by ear.
struct MixerTempoSlider: View {
    @ObservedObject var playback: PlaybackEngine

    var body: some View {
        GeometryReader { geo in
            let fraction = PlaybackTempo.fraction(forBPM: playback.tempoBPM)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Surface.band)
                    .frame(height: MixerLayout.tempoTrackHeight)
                Capsule().fill(Theme.Ink.ink2)
                    .frame(width: geo.size.width * fraction,
                           height: MixerLayout.tempoTrackHeight)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.Surface.panel)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Theme.Line.line2, lineWidth: 1)
                    }
                    .frame(width: MixerLayout.capSize.height,
                           height: MixerLayout.capSize.width)
                    .offset(x: (geo.size.width - MixerLayout.capSize.height)
                               * fraction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        playback.setTempo(PlaybackTempo.bpm(
                            forFraction: value.location.x
                                / max(geo.size.width, 1)))
                    })
        }
        .frame(minHeight: 16)
        .accessibilityElement()
        .accessibilityIdentifier("mixer-tempo")
        .accessibilityLabel("Tempo")
        .accessibilityValue("\(Int(playback.tempoBPM.rounded())) beats a minute")
    }
}

/// Where the music is, and where to put it.
struct MixerScrubber: View {
    @ObservedObject var playback: PlaybackEngine

    var body: some View {
        GeometryReader { geo in
            let total = max(playback.timeline.beats, 1)
            let fraction = min(max(playback.beat / total, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Surface.well).frame(height: 4)
                Capsule().fill(Theme.Accent.clay)
                    .frame(width: geo.size.width * fraction, height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.Surface.panel)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Theme.Line.line2, lineWidth: 1)
                    }
                    .frame(width: MixerLayout.capSize.width,
                           height: MixerLayout.capSize.height * 1.6)
                    .offset(x: (geo.size.width - MixerLayout.capSize.width)
                               * fraction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        playback.seek(toBeat: total * min(max(
                            value.location.x / max(geo.size.width, 1), 0), 1))
                    })
        }
        .frame(minHeight: 16)
        .accessibilityElement()
        .accessibilityIdentifier("mixer-scrubber")
        .accessibilityLabel("Position")
        .accessibilityValue(playback.soundingBar.map { "bar \($0)" } ?? "start")
    }
}

// MARK: - The sound picker (§6)

/// The list of sounds one channel can be played with.
///
/// It swaps the panel's BODY and never its header, which is what keeps the ✕
/// reachable -- the shipped picker replaced the rack and the way out went with
/// it, measured as "the mixer's ✕ is not reachable" on a two-channel score in
/// both orientations.
///
/// Two columns where there is room and ONE below 380pt: families, then the
/// instruments of the family, pushed within the panel with a back control.
/// The shipped picker asked the panel to grow to a fixed 300pt instead, which
/// is how a two-strip panel ended up wider than its own placement.
struct MixerSoundPicker: View {
    @ObservedObject var playback: PlaybackEngine
    let part: PlaybackTimeline.Part
    var onDone: () -> Void

    @State private var family: GeneralMIDI.Family?

    private var current: (program: UInt8, bank: GeneralMIDI.Bank) {
        playback.instrument(for: part)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.Line.line).frame(height: 1)
            GeometryReader { geo in
                if geo.size.width >= 380 {
                    HStack(spacing: 0) {
                        families.frame(width: MixerLayout.pickerFamilyWidth)
                        Rectangle().fill(Theme.Line.line).frame(width: 1)
                        instruments(in: family ?? current.bank.defaultFamily)
                    }
                } else if let chosen = family {
                    instruments(in: chosen)
                } else {
                    families
                }
            }
            .frame(minHeight: 132, maxHeight: 190)
            Rectangle().fill(Theme.Line.line).frame(height: 1)
            footer
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mixer-picker")
    }

    private var header: some View {
        HStack(spacing: Theme.Metric.s8) {
            if family != nil {
                Button { family = nil } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Ink.ink2)
                        .frame(minWidth: 28, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mixer-picker-back")
                .accessibilityLabel("Back to the families")
            }
            Text(part.name).typeRole(.label)
                .foregroundStyle(Theme.Ink.ink3)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: Theme.Metric.s8)
            Button(action: onDone) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Ink.ink2)
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mixer-picker-close")
            .accessibilityLabel("Close the sound list")
        }
        .padding(.horizontal, Theme.Metric.s12)
        .frame(minHeight: 30)
    }

    private var families: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(GeneralMIDI.Family.allCases) { item in
                    row(title: item.name, selected: item == family, check: false,
                        id: "picker-family-\(item.rawValue)") { family = item }
                }
            }
        }
        .background(Theme.Surface.well)
    }

    private func instruments(in family: GeneralMIDI.Family) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(GeneralMIDI.instruments(in: family)) { item in
                    row(title: item.name,
                        selected: item.program == current.program
                            && item.bank == current.bank,
                        check: true,
                        id: "picker-instrument-\(item.id)") {
                        playback.setInstrument(program: item.program,
                                               bank: item.bank, for: part)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Three actions, and each is the inverse of something.
    ///
    /// AUTO undoes a choice on this channel; ALL AUTO undoes one made across
    /// the rack; ALL STAVES is the ask the feature came from. A control that
    /// changes every channel at once and leaves the reader undoing it a strip
    /// at a time is the create-only trap the house rule names -- which is why
    /// ALL AUTO exists and why the rebuild dropping it was a regression a test
    /// caught as "no way back".
    private var footer: some View {
        HStack(spacing: Theme.Metric.s8) {
            action("AUTO", id: "picker-guess",
                   label: "Back to the automatic sound") {
                playback.clearInstrument(for: part)
            }
            action("ALL AUTO", id: "picker-all-guess",
                   label: "Every staff back to its automatic sound") {
                playback.clearInstruments()
            }
            Spacer(minLength: Theme.Metric.s4)
            action("ALL STAVES", id: "picker-all-staves",
                   label: "Put every staff on this sound") {
                playback.setInstrumentEverywhere(program: current.program,
                                                 bank: current.bank)
            }
        }
        .padding(.horizontal, Theme.Metric.s8)
        .frame(minHeight: 30)
    }

    private func action(_ title: String, id: String, label: String,
                        run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title).typeRole(.label)
                .foregroundStyle(Theme.Accent.clayStrong)
                .fixedSize()
                .padding(.horizontal, 4)
                .frame(minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
    }

    /// One row. `.fixedSize` and a minimum, like everything else here.
    private func row(title: String, selected: Bool, check: Bool, id: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Metric.s4) {
                Text(title).typeRole(.meta)
                    .foregroundStyle(Theme.Ink.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
                if selected && check {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Accent.clayStrong)
                }
            }
            .padding(.horizontal, Theme.Metric.s8)
            .padding(.vertical, 3)
            .frame(minHeight: MixerLayout.pickerRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.Accent.clayTint : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

private extension GeneralMIDI.Bank {
    /// Which family the picker opens on for a channel's current bank.
    var defaultFamily: GeneralMIDI.Family {
        self == .percussion ? .percussion : .piano
    }
}
