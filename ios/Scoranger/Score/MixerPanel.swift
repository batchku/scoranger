import SwiftUI

/// The mixer: one channel strip per staff, and the seek scrubber.
///
/// Built to design/PLAYBACK_0.6.md §1. Laid out like a mixer and rendered like
/// Scoranger -- the DAW conventions each have an equivalent in the instrument
/// panel language this app already uses, so there is no dark chassis, no
/// gradient meter, no bevelled cap, and no per-channel colour. Light only.
///
/// OBSERVES the engine: the LEDs follow the play head twenty times a second and
/// a value passed down from the canvas would redraw the score with them.
struct MixerPanel: View {
    @ObservedObject var playback: PlaybackEngine
    var compact: Bool = false
    var onClose: () -> Void
    var onCycleCorner: () -> Void
    /// Where the panel is parked, for the grip's accessibility value.
    var cornerLabel: String

    /// Where the scrubber's handle is while a finger is on it. Nil when the
    /// reader is not scrubbing, so the handle follows the play head instead.
    @State private var scrubbing: Double?
    /// The same for the tempo slider: the bpm under the finger, so the number
    /// beside it moves with the drag rather than after it.
    @State private var draggingTempo: Double?

    private var parts: [PlaybackTimeline.Part] { playback.timeline.parts }
    private var labels: [String] { PlaybackChannels.labels(for: parts) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.Line.line).frame(height: 1)
            rack
            Rectangle().fill(Theme.Line.line).frame(height: 1)
            tempoBand
            Rectangle().fill(Theme.Line.line).frame(height: 1)
            scrubber
        }
        .frame(width: MixerLayout.panelWidth(channels: parts.count, compact: compact),
               height: MixerLayout.panelHeight)
        .background(Theme.Surface.panel)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metric.rPanel)
                .stroke(Theme.Line.line2, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rPanel))
        .shadow(color: Color(hex: 0x1A1917).opacity(0.16), radius: 10, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mixer")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Metric.s8) {
            // Tap the grip to move the panel. A drag is the fast path, but it
            // is not the ONLY path: VoiceOver and Switch Control cannot drag,
            // and a panel reachable only by dragging is one those readers can
            // never move.
            Button(action: onCycleCorner) {
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle().fill(Theme.Ink.ink3).frame(width: 12, height: 2)
                    }
                }
                .frame(width: 28, height: MixerLayout.headerHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mixer-grip")
            .accessibilityLabel("Move the mixer")
            .accessibilityValue(cornerLabel)
            .accessibilityHint("Moves it to the next corner")

            Text("MIXER").typeRole(.meta)
                .tracking(0.8)
                .foregroundStyle(Theme.Accent.clayStrong)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Ink.ink2)
                    .frame(width: 28, height: MixerLayout.headerHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mixer-close")
            .accessibilityLabel("Close the mixer")
        }
        .padding(.horizontal, MixerLayout.padding)
        .frame(height: MixerLayout.headerHeight)
    }

    // MARK: - The strips

    private var rack: some View {
        // The header and footer stay put while the strips scroll: the scrubber
        // belongs to the whole performance, not to whichever strips are in view.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(parts.enumerated()), id: \.element.index) { position, part in
                    if position > 0 {
                        Rectangle().fill(Theme.Line.line)
                            .frame(width: MixerLayout.dividerWidth)
                    }
                    ChannelStrip(
                        playback: playback,
                        part: part,
                        label: labels.indices.contains(position)
                            ? labels[position] : part.name)
                }
            }
            .padding(.horizontal, MixerLayout.padding)
        }
        .frame(height: MixerLayout.rackHeight)
    }

    // MARK: - Tempo

    /// The tempo, 1 to 300 bpm.
    ///
    /// Deliberately NOT a channel strip, and drawn so nobody could mistake it
    /// for one: horizontal where the faders are vertical, graphite where they
    /// are clay, on the band fill rather than the panel's, with a rule above
    /// and below it. Tempo belongs to the whole performance, like the
    /// scrubber under it -- a strip would say it belonged to a staff.
    ///
    /// It drives the SAME number the transport prints (`PlaybackTempo`), so
    /// moving it here changes the readout there. Two controls, one value.
    private var tempoBand: some View {
        let bpm = draggingTempo ?? playback.tempoBPM
        return HStack(spacing: Theme.Metric.s8) {
            Text("TEMPO").typeRole(.meta)
                .tracking(0.8)
                .foregroundStyle(Theme.Ink.ink2)
                .fixedSize()
            GeometryReader { geo in
                let fraction = PlaybackTempo.fraction(forBPM: bpm)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Surface.well)
                        .overlay { Capsule().stroke(Theme.Line.line2, lineWidth: 1) }
                        .frame(height: MixerLayout.tempoTrackHeight)
                    Capsule().fill(Theme.Ink.ink2)
                        .frame(width: geo.size.width * fraction,
                               height: MixerLayout.tempoTrackHeight)
                    // The same flat cap as the faders and the seek handle: the
                    // colour says which family this control is in, the SHAPE
                    // says it is the same kind of thing to grab.
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .fill(Theme.Surface.panel)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                                .stroke(Theme.Ink.ink2, lineWidth: 1)
                        }
                        .frame(width: MixerLayout.capSize.height,
                               height: MixerLayout.capSize.width * 0.6)
                        .offset(x: geo.size.width * fraction
                                - MixerLayout.capSize.height / 2)
                }
                .frame(height: MixerLayout.tempoHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            draggingTempo = PlaybackTempo.bpm(
                                forFraction: value.location.x / max(geo.size.width, 1))
                            // live, not on release: a practice tempo is found
                            // by ear while the music is playing
                            playback.setTempo(draggingTempo ?? bpm)
                        }
                        .onEnded { _ in draggingTempo = nil })
            }
            .frame(height: MixerLayout.tempoHeight)
            .accessibilityElement()
            .accessibilityIdentifier("mixer-tempo")
            .accessibilityLabel("Tempo")
            .accessibilityValue("\(Int(bpm.rounded())) beats per minute")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: playback.setTempo(playback.tempoBPM + 1)
                case .decrement: playback.setTempo(playback.tempoBPM - 1)
                @unknown default: break
                }
            }
            Text("\(Int(bpm.rounded()))").typeRole(.meta)
                .foregroundStyle(Theme.Ink.ink)
                .frame(width: 26, alignment: .trailing)
                .accessibilityHidden(true)
                .accessibilityIdentifier("mixer-tempo-value")
        }
        .padding(.horizontal, MixerLayout.padding * 2)
        .frame(height: MixerLayout.tempoHeight)
        .background(Theme.Surface.band)
    }

    // MARK: - The scrubber (§1, and seek's access path)

    private var scrubber: some View {
        let total = max(playback.timeline.beats, 0.001)
        let position = scrubbing ?? playback.beat
        return HStack(spacing: Theme.Metric.s8) {
            Text(clock(position)).typeRole(.meta)
                .foregroundStyle(Theme.Ink.ink2)
                .frame(width: 40, alignment: .leading)
                .accessibilityIdentifier("mixer-elapsed")
            GeometryReader { geo in
                let fraction = min(max(position / total, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Surface.well)
                        .overlay { Capsule().stroke(Theme.Line.line2, lineWidth: 1) }
                        .frame(height: 4)
                    Capsule().fill(Theme.Accent.clay)
                        .frame(width: geo.size.width * fraction, height: 4)
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .fill(Theme.Surface.panel)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                                .stroke(Theme.Line.line2, lineWidth: 1)
                        }
                        .frame(width: MixerLayout.capSize.width,
                               height: MixerLayout.capSize.height)
                        .offset(x: geo.size.width * fraction
                                - MixerLayout.capSize.width / 2)
                    // Musicians seek by BAR, so the chip over the handle says
                    // which one rather than a time -- 2:14 tells a player
                    // nothing they can find on the page.
                    if let scrubbing, let bar = playback.timeline.bar(atBeat: scrubbing) {
                        Text("bar \(bar)").typeRole(.meta)
                            .foregroundStyle(Theme.Ink.ink)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.Surface.panel)
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                                    .stroke(Theme.Line.line2, lineWidth: 1)
                            }
                            .offset(x: geo.size.width * fraction - 22, y: -22)
                            .accessibilityIdentifier("mixer-scrub-bar")
                    }
                }
                .frame(height: MixerLayout.footerHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = min(max(value.location.x / geo.size.width, 0), 1)
                            scrubbing = Double(fraction) * total
                        }
                        .onEnded { _ in
                            if let scrubbing { playback.seek(toBeat: scrubbing) }
                            scrubbing = nil
                        })
            }
            .frame(height: MixerLayout.footerHeight)
            .accessibilityIdentifier("mixer-scrubber")
            .accessibilityLabel("Seek")
            .accessibilityValue(playback.soundingBar.map { "bar \($0)" } ?? "start")
            Text(clock(playback.timeline.beats)).typeRole(.meta)
                .foregroundStyle(Theme.Ink.ink2)
                .frame(width: 40, alignment: .trailing)
                .accessibilityIdentifier("mixer-total")
        }
        .padding(.horizontal, MixerLayout.padding)
        .frame(height: MixerLayout.footerHeight)
    }

    /// Beats to a clock reading, at the opening tempo.
    private func clock(_ beat: Double) -> String {
        let bpm = max(playback.timeline.openingTempo, 1)
        let seconds = Int((beat / bpm * 60).rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// One staff's strip: mute, fader, activity, value, label.
private struct ChannelStrip: View {
    @ObservedObject var playback: PlaybackEngine
    let part: PlaybackTimeline.Part
    let label: String

    private var isOn: Bool { playback.voices.isOn(part.index) }
    private var fader: Int { playback.voices.fader(part.index) }
    /// The staff IS playing even when it is muted -- that is how a reader
    /// confirms the mute is working, so the lamp follows the music and not the
    /// mute. It dims with the rest of the strip and it does not go out.
    private var isSounding: Bool { part.isSounding(at: playback.beat) }

    var body: some View {
        VStack(spacing: 0) {
            mute
            HStack(spacing: MixerLayout.ledInset) {
                fadeTrack
                led
            }
            .frame(height: MixerLayout.faderHeight)
            Text("\(fader)").typeRole(.meta)
                .foregroundStyle(Theme.Ink.ink3)
                .frame(height: MixerLayout.valueHeight)
                .accessibilityHidden(true)
            Text(label).typeRole(.meta)
                .foregroundStyle(Theme.Ink.ink)
                .multilineTextAlignment(.center)
                // One line since the panel halved: 16pt does not hold two.
                // The full staff name is still on the strip's accessibility
                // label, which is where a truncated caption survives.
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: MixerLayout.stripWidth - 8,
                       height: MixerLayout.labelHeight, alignment: .top)
                .accessibilityHidden(true)
        }
        .frame(width: MixerLayout.stripWidth)
        .padding(.vertical, MixerLayout.padding)
        // Muted dims the WHOLE strip, LED included, rather than hiding
        // anything: a strip that vanished would take the way back with it.
        .opacity(isOn ? 1 : MixerLayout.mutedOpacity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("strip-\(part.index)")
    }

    private var mute: some View {
        Button {
            playback.voices.toggle(part.index)
        } label: {
            Text("M").typeRole(.label)
                .foregroundStyle(isOn ? Theme.Ink.ink2 : Theme.Surface.panel)
                .frame(width: MixerLayout.muteSize.width,
                       height: MixerLayout.muteSize.height)
                .background(isOn ? Theme.Surface.panel : Theme.Ink.ink)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(Theme.Line.line2, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("strip-mute-\(part.index)")
        .accessibilityLabel("\(part.name), mute")
        .accessibilityValue(isOn ? "off" : "on")
    }

    private var fadeTrack: some View {
        GeometryReader { geo in
            let travel = geo.size.height - MixerLayout.capSize.height
            let filled = travel * MixerLayout.capOffset(forFader: fader)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                    .fill(Theme.Surface.well)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                            .stroke(Theme.Line.line2, lineWidth: 1)
                    }
                    .frame(width: MixerLayout.faderTrackWidth)
                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                    .fill(Theme.Accent.clay)
                    .frame(width: MixerLayout.faderTrackWidth,
                           height: filled + MixerLayout.capSize.height / 2)
                // the detent: where an untouched fader sits
                Rectangle().fill(Theme.Line.line2)
                    .frame(width: 14, height: 1)
                    .offset(y: -(travel * MixerLayout.capOffset(
                        forFader: MixerLayout.detent)
                                 + MixerLayout.capSize.height / 2))
                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                    .fill(Theme.Surface.panel)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                            .stroke(Theme.Line.line2, lineWidth: 1)
                    }
                    .frame(width: MixerLayout.capSize.width,
                           height: MixerLayout.capSize.height)
                    .offset(y: -filled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // The gesture arrives with DOWN positive; the fader
                        // fills from the bottom, so the fraction is flipped
                        // here rather than inside the pure layout.
                        let up = 1 - (value.location.y / max(geo.size.height, 1))
                        playback.setFader(MixerLayout.fader(forOffset: up),
                                          channel: part.index)
                    })
        }
        .frame(width: MixerLayout.capSize.width)
        .accessibilityElement()
        .accessibilityIdentifier("strip-fader-\(part.index)")
        .accessibilityLabel("\(part.name), volume")
        .accessibilityValue("\(fader) of 10")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: playback.setFader(fader + 1, channel: part.index)
            case .decrement: playback.setFader(fader - 1, channel: part.index)
            @unknown default: break
            }
        }
    }

    private var led: some View {
        Circle()
            .fill(isSounding ? Theme.Status.ok : Theme.Surface.well)
            .overlay {
                Circle().stroke(isSounding ? Color.clear : Theme.Line.line2,
                                lineWidth: 1)
            }
            .overlay {
                // A flat halo, not a glow: the design system forbids blur, and
                // a ring at 22% reads as lit without one.
                if isSounding {
                    Circle().stroke(Theme.Status.ok.opacity(0.22), lineWidth: 3)
                        .frame(width: MixerLayout.ledWidth + 3,
                               height: MixerLayout.ledWidth + 3)
                }
            }
            .frame(width: MixerLayout.ledWidth, height: MixerLayout.ledWidth)
            .accessibilityIdentifier("strip-led-\(part.index)")
            .accessibilityLabel("\(part.name), sounding")
            .accessibilityValue(isSounding ? "yes" : "no")
    }
}

/// The mixer's layer on the score screen: parking, dragging, and the lanes it
/// must stay clear of (§4).
///
/// A layer of its own so it OBSERVES both the app state and the engine. The
/// panel redraws on every play-head tick for its LEDs; the score must not.
struct MixerLayer: View {
    @ObservedObject var state: AppState
    @ObservedObject var playback: PlaybackEngine
    var lanesInset: CGFloat

    @State private var drag: CGSize = .zero
    @State private var parked: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let size = CGSize(
                width: MixerLayout.panelWidth(channels: playback.timeline.parts.count),
                height: MixerLayout.panelHeight)
            let home = MixerLayout.origin(for: state.mixerCorner, panel: size,
                                          in: geo.size, lanesInset: lanesInset)
            let origin = MixerLayout.clamp(
                CGPoint(x: home.x + drag.width, y: home.y + drag.height),
                panel: size, in: geo.size)
            MixerPanel(
                playback: playback,
                compact: geo.size.width < 700,
                onClose: { state.mixerOpen = false },
                onCycleCorner: {
                    // Tapping the grip moves it AND forgets the drag, so the
                    // corner it names is the corner it is in.
                    drag = .zero
                    state.mixerCorner = state.mixerCorner.next
                },
                cornerLabel: state.mixerCorner.label)
                .position(x: origin.x + size.width / 2,
                          y: origin.y + size.height / 2)
                .gesture(
                    DragGesture()
                        .onChanged { drag = $0.translation }
                        .onEnded { value in drag = value.translation })
        }
    }
}

/// The sync chip: the only solid-clay object on the canvas, so it reads as an
/// interruption without needing a colour of its own (§3).
struct SyncChipLayer: View {
    @ObservedObject var state: AppState
    @ObservedObject var playback: PlaybackEngine

    private var playheadPage: Int? {
        guard let bar = playback.soundingBar, let geometry = state.geometry else { return nil }
        return Playhead.page(ofMeasure: bar,
                             pages: geometry.pages.map {
                                 ($0.index, BarPosition.bars(onPage: $0))
                             })
    }

    private var shows: Bool {
        PageFollow.showsSync(isPlaying: playback.isPlaying,
                             isFollowing: state.pageFollow.isFollowing,
                             playheadPage: playheadPage,
                             visiblePages: state.visiblePageIndices,
                             isPerformanceMode: state.scoreMode == .performance)
    }

    var body: some View {
        Group {
            if shows {
                Button {
                    guard let page = playheadPage else { return }
                    state.pageFollow.syncTapped()
                    state.pageIndex = PagedCanvas.index(forPage: page,
                                                        spread: state.twoPageSpread)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text(PageFollow.syncLabel(bar: playback.soundingBar))
                            .typeRole(.label)
                    }
                    .foregroundStyle(Theme.Surface.panel)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Theme.Accent.clayPress)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sync-to-playback")
                .accessibilityLabel(PageFollow.syncLabel(bar: playback.soundingBar))
                .accessibilityAddTraits(.isButton)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: shows)
    }
}
