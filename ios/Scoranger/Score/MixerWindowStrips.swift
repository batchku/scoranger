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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // THE DIM IS APPLIED PER ROW, NOT TO THE STRIP (§13.4).
        //
        // A muted strip goes to 0.42 so the eye passes over it, and the arc
        // keeps its clay: the level is what the reader comes back to when they
        // unmute, and a mix they cannot read is a mix they have to rediscover.
        //
        // Per row because opacity does not work the other way round. The first
        // attempt dimmed the whole strip and put the knob back with an opacity
        // above 1, which SwiftUI clamps before it multiplies -- so the knob
        // would have dimmed with everything else and the code would have
        // claimed otherwise.
        let dim = isOn ? 1 : MixerLayout.mutedOpacity
        VStack(spacing: 0) {
            MixerMuteButton(playback: playback, part: part).opacity(dim)
            // The KNOB, and the value inside its face (§13). The separate
            // value row is gone -- that is the row the knob spends on itself.
            // The LED sits in the CENTRE of the knob and the knob is centred
            // in its column (Ali, 2026-09-10). One control reads as one thing:
            // the ring is the level, the light in the middle is whether the
            // part is sounding right now.
            MixerKnob(playback: playback, part: part,
                      centre: { MixerLED(on: isSounding, part: part).opacity(dim) })
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(minHeight: MixerLayout.knobRow(text: typeSize))
            MixerSoundChip(playback: playback, part: part, action: onPickSound)
                .opacity(dim)
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
                .opacity(dim)
        }
        .frame(width: width)
        .padding(.vertical, MixerLayout.rackPaddingMinimum / 2)
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
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mixer-label-\(part.index)")
                MixerSoundChip(playback: playback, part: part,
                               compressible: true, action: onPickSound)
            }
            // NO layoutPriority here. It was 1, meaning "give this its ideal
            // width first" -- which on a 402pt phone at accessibility text is
            // how the row demanded 681pt. The name is the thing that should
            // give ground, not the thing that takes it.
            .frame(minWidth: 0, maxWidth: 150, alignment: .leading)
            Spacer(minLength: Theme.Metric.s4)
            // 100pt is the spec's ideal, 64 the floor. A minimum that cannot
            // be met is a minimum that pushes the row off the screen, and on a
            // 402pt phone at accessibility text there is not 100pt to give.
            // A CEILING, not just a floor. `MixerHorizontalFader` is a
            // GeometryReader: it has no intrinsic width and takes everything
            // offered. Measured on iPhone 17 at accessibility text it claimed
            // 395.7pt of a row that had 378 to spend, and the row -- and with
            // it the whole panel -- grew to 665pt on a 402pt screen. A
            // greedy child in a row with no upper bound is how a panel
            // overflows a frame that is trying to cap it.
            MixerHorizontalFader(playback: playback, part: part)
                .frame(minWidth: 56, idealWidth: 100, maxWidth: 140)
            Text("\(fader)").typeRole(.data)
                .foregroundStyle(Theme.Ink.ink3)
                .fixedSize(horizontal: false, vertical: true)
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
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
                .frame(minWidth: 26, minHeight: MixerLayout.muteRowMinimum)
                .background(isOn ? Theme.Surface.well : Theme.Ink.ink2)
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

/// The KNOB (§13), which replaces the vertical fader.
///
/// A 270-degree arc with the gap at the bottom, the level printed in the face,
/// and a RELATIVE vertical drag: 14pt of travel is one unit, so a full sweep
/// is 140pt and a wobble is nothing.
///
/// Relative is the whole difference from the fader. A fader track has a
/// position that means 7; a knob face does not, so reading the finger's
/// absolute position would jump the level to wherever it landed. On a 30pt
/// track that was easy to do by accident -- a touch near the middle set the
/// channel to about 5 rather than nudging it down -- and it is the likeliest
/// explanation for a reader who pulled three channels down and still heard
/// four.
///
/// Flat, like everything else here: no bevel, no gradient, no shadow (§0).
struct MixerKnob<Centre: View>: View {
    @ObservedObject var playback: PlaybackEngine
    let part: PlaybackTimeline.Part
    /// What sits in the middle of the face: the strip puts its LED there.
    @ViewBuilder var centre: () -> Centre

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The level the finger went down on. The drag is measured from here, not
    /// from where the finger is.
    @State private var startFader: Int?

    private var fader: Int { playback.voices.fader(part.index) }

    var body: some View {
        let face = MixerLayout.knobFace(text: typeSize)
        // No numeral. The level is the ring, and the ring is what a player
        // reads on a real desk; the number was a second statement of the same
        // fact taking a row of its own (Ali, 2026-09-10). It is still SPOKEN:
        // the accessibility value below carries it.
        ZStack {
            Circle()
                .fill(Theme.Surface.panel)
            arc(from: 0, to: 1, colour: Theme.Surface.well, face: face)
            arc(from: 0, to: progress, colour: Theme.Accent.clay, face: face)
            // No pointer tick [C3]: the clay arc alone carries the level, and
            // the LED in the centre is the mute.
            centre()
        }
        .frame(width: face, height: face)
        // THE ROW IS THE HIT TARGET, never the face: at Large the face is 36pt
        // and a 36pt circle is not something to aim at (§13.2).
        .frame(maxWidth: .infinity, minHeight: MixerLayout.knobRow(text: typeSize))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { move in
                    let start = startFader ?? fader
                    if startFader == nil { startFader = start }
                    playback.setFader(
                        MixerLayout.knobFader(from: start,
                                              translation: move.translation.height),
                        channel: part.index)
                }
                .onEnded { _ in startFader = nil })
        .accessibilityElement()
        // KEPT: it is the same control and the tests address it (§13.6).
        .accessibilityIdentifier("strip-fader-\(part.index)")
        .accessibilityLabel("\(part.name), level")
        .accessibilityValue("level \(fader) of \(PlaybackGain.maximumFader)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: playback.setFader(fader + 1, channel: part.index)
            case .decrement: playback.setFader(fader - 1, channel: part.index)
            @unknown default: break
            }
        }
    }

    private var progress: Double {
        let span = Double(PlaybackGain.maximumFader - PlaybackGain.minimumFader)
        guard span > 0 else { return 0 }
        return Double(fader - PlaybackGain.minimumFader) / span
    }

    /// The level, in the mono face the rest of the app prints numbers in.
    private var value: some View {
        Text("\(fader)").typeRole(.data)
            .foregroundStyle(Theme.Ink.ink)
            .fixedSize()
            .accessibilityHidden(true)
    }

    /// A slice of the sweep, as a stroked arc. `trim` is in turns from the
    /// shape's own zero, so the sweep is expressed as fractions of a circle
    /// and then rotated to put the gap at the bottom.
    private func arc(from: Double, to: Double, colour: Color,
                     face: CGFloat) -> some View {
        let sweep = MixerLayout.knobSweep / 360
        return Circle()
            .trim(from: from * sweep, to: to * sweep)
            .stroke(colour, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(MixerLayout.knobStartAngle - 90))
            .frame(width: face - 3, height: face - 3)
            .accessibilityHidden(true)
    }

    /// A line from 0.60r to 0.90r, turned to the level's angle.
    private func pointer(face: CGFloat) -> some View {
        let radius = face / 2
        return Rectangle()
            .fill(Theme.Ink.ink)
            .frame(width: 2, height: radius * 0.30)
            .offset(y: -radius * 0.75)
            .rotationEffect(.degrees(MixerLayout.knobAngle(forFader: fader)))
            .accessibilityHidden(true)
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
    /// Whether the chip may give up width.
    ///
    /// In a STRIP it may not: the strip's width is the chip's width and the
    /// name is the only caption there is. In a ROW it shares one line with a
    /// mute, a name, a fader and a value, and a chip that refuses to compress
    /// makes the ROW refuse -- measured on iPhone 17 at accessibility text,
    /// where the list row's intrinsic width came out at 681pt on a 402pt
    /// screen and hung 139.5pt off BOTH edges. `.frame(maxWidth:)` cannot fix
    /// that: a parent cannot compress a child that will not.
    var compressible: Bool = false
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
                    .modifier(ChipWidth(compressible: compressible))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Theme.Ink.ink3)
            }
            .padding(.horizontal, 4)
            .frame(minHeight: MixerLayout.soundRowMinimum)
            .background(chosen ? Theme.Accent.clayTint : Theme.Surface.well)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                    .stroke(chosen ? Theme.Accent.clayBorder : Color.clear, lineWidth: 1.5)
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
            Theme.Rule()
            GeometryReader { geo in
                if geo.size.width >= 380 {
                    HStack(spacing: 0) {
                        families.frame(width: MixerLayout.pickerFamilyWidth)
                        Theme.Rule(vertical: true)
                        instruments(in: family ?? current.bank.defaultFamily)
                    }
                } else if let chosen = family {
                    instruments(in: chosen)
                } else {
                    families
                }
            }
            .frame(minHeight: 132, maxHeight: 190)
            Theme.Rule()
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
                .fixedSize(horizontal: false, vertical: true)
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
                .fixedSize(horizontal: false, vertical: true)
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


/// The sound chip's width rule, as a modifier so the two callers differ by one
/// argument rather than by a duplicated `Text`.
private struct ChipWidth: ViewModifier {
    let compressible: Bool
    func body(content: Content) -> some View {
        if compressible {
            // Shrink a little, then truncate. The full name is on the chip's
            // accessibility value, which is where a truncated caption survives.
            AnyView(content.minimumScaleFactor(0.7).truncationMode(.tail))
        } else {
            AnyView(content.fixedSize())
        }
    }
}
