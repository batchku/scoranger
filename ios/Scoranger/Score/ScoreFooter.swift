import PDFKit
import SwiftUI

/// The page thumbnail strip (NAVIGATION_SYSTEM.md 12.12).
///
/// Grouped in spreads when the spread is on, because that is what a turn
/// actually does. Thumbnails render lazily in a window around the current page:
/// on an iPad Pro a twelve-page score is nothing, on an older iPad a sixty-page
/// one is not (§9.7).
struct ThumbnailStrip: View {
    let document: PDFDocument
    let current: [Int]
    let spread: Bool
    var onJump: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                // LAZY, so only the thumbnails on screen are built. The strip
                // was an eager HStack, which is why it needed a window of six
                // pages either side -- and why the pages outside it were blank
                // (L20). Laziness is the budget now, and it does not lie about
                // what a page looks like.
                LazyHStack(spacing: Theme.Metric.s8) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        HStack(spacing: 2) {
                            ForEach(group, id: \.self) { index in thumb(index) }
                        }
                        .padding(3)
                        .overlay {
                            if spread && group.count > 1 {
                                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                    .foregroundStyle(Theme.Line.line2)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Metric.s12)
                .padding(.vertical, Theme.Metric.s8)
            }
            .onChange(of: current) { _, pages in
                if let first = pages.first {
                    withAnimation { proxy.scrollTo(first, anchor: .center) }
                }
            }
        }
        .frame(height: Theme.Metric.thumbStripHeight)
        .background(Theme.Surface.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.Line.line).frame(height: 1) }
        .accessibilityIdentifier("thumbnail-strip")
    }

    private var groups: [[Int]] {
        SpreadLayout.rows(pageCount: document.pageCount, spread: spread)
    }

    private func thumb(_ index: Int) -> some View {
        Button { onJump(index) } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let drawn = ThumbnailCache.shared.image(
                        document: document, index: index,
                        size: CGSize(width: 104, height: 136)) {
                        Image(uiImage: drawn)
                            .resizable().interpolation(.medium)
                    } else {
                        // A page that will not draw says so. It used to look
                        // exactly like a page that had not been drawn YET,
                        // which is two different problems wearing one face.
                        PageThumb(width: 52, height: 68)
                            .overlay {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.Status.warn)
                            }
                            .accessibilityIdentifier("thumb-failed-\(index)")
                    }
                }
                .frame(width: 52, height: 68)
                .background(Theme.Surface.paper)
                Text("\(index + 1)").typeRole(.data)
                    .foregroundStyle(Theme.Ink.ink3)
                    .padding(2)
            }
            .overlay {
                Rectangle()
                    .stroke(current.contains(index) ? Theme.Accent.clay : Theme.Line.line2,
                            lineWidth: current.contains(index) ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(index)
        .accessibilityIdentifier("thumb-\(index)")
        .accessibilityLabel("Page \(index + 1)")
    }

}

/// The transport (12.13).
///
/// Previous and next step the current setlist. Play, the metronome and the
/// voices are the 0.5.1 playback feature; they were drawn and inert for three
/// builds, and the inert copy is gone with them.
///
/// Modal-free (NAV_MODAL_FREE_0.4.2): the voice list is an INLINE REVEAL under
/// the row, not a sheet or a popover. It pushes the canvas up by its own height
/// while it is open, the same way the title band does.
struct Transport: View {
    let setlistLabel: String?
    var canStep: Bool
    var onPrevious: () -> Void
    var onNext: () -> Void

    /// Observed, not read through AppState: the row has to redraw when the
    /// play head moves, and AppState publishes nothing when the engine's own
    /// state changes. The same fix the ink bar needed.
    @ObservedObject var playback: PlaybackEngine
    /// Why playback cannot happen, when it cannot. Anything but `.available`
    /// replaces the controls with the reason -- a button that plainly is not
    /// live beats one that looks live and does nothing (§9.2).
    ///
    /// The reason now carries its REMEDY. It used to be a bare string, and a
    /// reader whose library is all imported PDFs read "Run OMR to play this
    /// arrangement" on every score with nothing to tap.
    var unavailable: PlaybackAvailability = .available
    var preparing: Bool
    var onPlay: () -> Void
    /// Perform whatever `unavailable` is offering.
    var onResolve: () -> Void = {}
    /// Whether the mixer is on screen. The voice list BELOW stays exactly
    /// where it was: the mixer is a richer way to reach the same mutes, and
    /// the rule is that an access path survives the build that replaces it.
    var mixerOpen: Bool = false
    var onMixer: () -> Void = {}

    /// The voice list, revealed in place. Local because nothing outside this
    /// row needs to know whether it is open.
    @State private var voicesOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            row
            if voicesOpen { voiceList }
        }
        .background(Theme.Surface.band)
        // The spacebar, as in every DAW (0.6.3 #9). It lives HERE and not on
        // the score screen, so it exists exactly while the transport does --
        // a shortcut for a control that is not on screen does something
        // invisible.
        .background(alignment: .leading) { spaceKey }
        .overlay(alignment: .top) { Rectangle().fill(Theme.Line.line).frame(height: 1) }
        // Named on the container AND told to contain its children, or the
        // identifier is inherited by every button inside it and the buttons
        // stop existing to a test -- the defect that made the title band
        // unusable.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transport")
    }

    /// The spacebar shortcut, and nothing to look at.
    ///
    /// A button of its own rather than the shortcut hung on Play: the shortcut
    /// has to refuse while a text field has focus, and Play's TAP must not --
    /// tapping Play with the chat input focused is a perfectly ordinary thing
    /// to do. One control, two triggers, two different rules is how the tap
    /// would have been broken to fix the key.
    ///
    /// `.opacity(0)` and not `.hidden()`: a hidden view leaves the responder
    /// chain and takes its key command with it.
    private var spaceKey: some View {
        Button("Play or stop") {
            guard TransportKeys.spaceToggles(
                    isEditingText: KeyboardFocus.isEditingText,
                    isTransportShowing: true,
                    canPlay: unavailable.canPlay && playback.unavailable == nil
                            && !preparing) else { return }
            onPlay()
        }
        .keyboardShortcut(.space, modifiers: [])
        .frame(width: 1, height: 1)
        .opacity(0)
        .accessibilityHidden(true)
        .accessibilityIdentifier("transport-space-key")
    }

    private var row: some View {
        HStack(spacing: Theme.Metric.s8) {
            stepButton("backward.end", label: "Previous in setlist",
                       id: "transport-prev", enabled: canStep, action: onPrevious)
            stepButton("forward.end", label: "Next in setlist",
                       id: "transport-next", enabled: canStep, action: onNext)
            if let setlistLabel {
                chip(setlistLabel, id: "transport-setlist")
            }

            Divider().frame(height: 20)

            // AppState's reason first -- a scan, or the remote engine -- and
            // then the audio engine's own, which is READ OFF THE OBSERVED
            // OBJECT so the row redraws when it lands. Reading it through
            // AppState would leave the reason on screen only by luck of some
            // other publish.
            if !unavailable.canPlay || playback.unavailable != nil {
                unavailableRow
                Spacer(minLength: 0)
            } else {
                playControls
                Spacer(minLength: 0)
                position
            }
        }
        .padding(.horizontal, Theme.Metric.s12)
        .frame(height: Theme.Metric.transportHeight)
    }

    /// The reason, and the button that answers it.
    ///
    /// The audio engine's own failure has no remedy here, so it stays a
    /// sentence; a scan and the remote engine both have one, so they get a
    /// button. The draft warning rides with the offer rather than only with
    /// the spinner: telling someone their notation is a draft after they have
    /// waited for it is telling them too late.
    @ViewBuilder
    private var unavailableRow: some View {
        let engineFailure = playback.unavailable
        HStack(spacing: Theme.Metric.s8) {
            Text(engineFailure ?? unavailable.message)
                .typeRole(.meta)
                .foregroundStyle(Theme.Ink.ink3)
                .accessibilityIdentifier("transport-unavailable")
            if engineFailure == nil, let title = unavailable.actionTitle {
                Button(action: onResolve) {
                    Text(title).typeRole(.meta)
                        .foregroundStyle(Theme.Accent.clayStrong)
                        .padding(.horizontal, Theme.Metric.s8)
                        .frame(height: 24)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                                .stroke(Theme.Line.line2, lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("transport-resolve")
            }
            if engineFailure == nil, unavailable.warnsItIsADraft {
                Text("draft").typeRole(.data)
                    .foregroundStyle(Theme.Ink.ink3)
                    .accessibilityIdentifier("transport-draft-warning")
            }
        }
        .accessibilityIdentifier(unavailable.identifier)
    }

    @ViewBuilder
    private var playControls: some View {
        Button(action: onPlay) {
            Image(systemName: playback.isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Accent.clayStrong)
                .frame(width: 32, height: 32)
                .background(playback.isPlaying ? Theme.Accent.clayTint : Theme.Surface.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(playback.isPlaying ? Theme.Accent.clay : Theme.Line.line2,
                                lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(preparing)
        .opacity(preparing ? 0.42 : 1)
        .accessibilityIdentifier("transport-play")
        .accessibilityLabel(playback.isPlaying ? "Stop" : "Play")

        Button {
            playback.rewind()
        } label: {
            Image(systemName: "backward.end.alt.fill").font(.system(size: 12))
                .foregroundStyle(Theme.Ink.ink2)
                .frame(width: 32, height: 32)
                .background(Theme.Surface.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(Theme.Line.line2, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transport-rewind")
        .accessibilityLabel("Back to the start")

        toggleButton("metronome", glyph: "metronome",
                     on: playback.metronome, id: "transport-metronome") {
            playback.metronome.toggle()
        }

        toggleButton("mixer", glyph: "slider.vertical.3",
                     on: mixerOpen, id: "transport-mixer", action: onMixer)

        // The one control that opens something. Its label is the ANSWER, not
        // the question: "3 of 4 voices" says what the state is without opening
        // it, which is what every other row in this app does (L34).
        Button {
            withAnimation(Theme.Motion.overlay(reduced: reduceMotion)) {
                voicesOpen.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Text(playback.voices.summary(in: playback.timeline.parts,
                                             metronome: playback.metronome))
                    .typeRole(.data)
                Image(systemName: voicesOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Theme.Ink.ink2)
            .padding(.horizontal, Theme.Metric.s8)
            .frame(height: 32)
            .background(voicesOpen ? Theme.Accent.clayTint : Theme.Surface.panel)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                    .stroke(voicesOpen ? Theme.Accent.clay : Theme.Line.line2, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("transport-voices")
        .accessibilityLabel("Voices, \(playback.voices.summary(in: playback.timeline.parts, metronome: playback.metronome))")
    }

    /// Where the sound has got to, and how fast. The tempo says whose it is:
    /// 120 nobody chose is not 120 an arranger chose, and a player setting up
    /// to practise deserves to know which they are hearing.
    private var position: some View {
        HStack(spacing: Theme.Metric.s8) {
            if preparing {
                Text("preparing…").typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                    .accessibilityIdentifier("transport-preparing")
            } else {
                Text(playback.soundingBar.map { "bar \($0)" } ?? "—")
                    .typeRole(.data).foregroundStyle(Theme.Ink.ink)
                    .frame(minWidth: 54, alignment: .trailing)
                    .accessibilityIdentifier("transport-bar")
                Text(tempoLabel).typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                    .accessibilityIdentifier("transport-tempo")
            }
        }
    }

    /// The SAME number the mixer's tempo slider sits on. It was the timeline's
    /// opening tempo, which the slider could not change -- a readout and a
    /// control claiming one value while reading two.
    private var tempoLabel: String {
        PlaybackTempo.label(bpm: playback.tempoBPM,
                            fromScore: playback.timeline.tempoFromScore,
                            overridden: playback.tempoOverride != nil)
    }

    /// One row per part, each a switch. Muting every one of them is how the
    /// reader gets the metronome alone, so the list says so rather than
    /// looking like a mistake.
    private var voiceList: some View {
        // The staff labels, with a display-only ordinal where one repeats: a
        // scanned quartet is four staves called "Voice" and the page says so,
        // but four identical rows cannot be told apart.
        let labels = PlaybackChannels.labels(for: playback.timeline.parts)
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Theme.Line.line).frame(height: 1)
            ForEach(Array(playback.timeline.parts.enumerated()), id: \.element.index) { position, part in
                let caption = labels.indices.contains(position) ? labels[position] : part.name
                Button {
                    playback.voices.toggle(part.index)
                } label: {
                    HStack(spacing: Theme.Metric.s8) {
                        Image(systemName: playback.voices.isOn(part.index)
                                ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(playback.voices.isOn(part.index)
                                             ? Theme.Accent.clayStrong : Theme.Ink.ink3)
                            .frame(width: 20)
                        Text(caption).typeRole(.row)
                            .foregroundStyle(playback.voices.isOn(part.index)
                                             ? Theme.Ink.ink : Theme.Ink.ink3)
                        if let instrument = part.instrument, instrument != caption {
                            Text(instrument).typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Theme.Metric.s12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("voice-\(part.index)")
                .accessibilityLabel(caption)
                .accessibilityValue(playback.voices.isOn(part.index) ? "on" : "off")
            }
            HStack(spacing: Theme.Metric.s12) {
                Button("All on") {
                    playback.voices.setAll(on: true, parts: playback.timeline.parts)
                }
                .typeRole(.meta).foregroundStyle(Theme.Accent.clayStrong)
                .buttonStyle(.plain)
                .accessibilityIdentifier("voices-all-on")

                Button("All off") {
                    playback.voices.setAll(on: false, parts: playback.timeline.parts)
                }
                .typeRole(.meta).foregroundStyle(Theme.Accent.clayStrong)
                .buttonStyle(.plain)
                .accessibilityIdentifier("voices-all-off")

                Text(playback.voices.advice(in: playback.timeline.parts,
                                            metronome: playback.metronome))
                    .typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Metric.s12)
            .padding(.vertical, Theme.Metric.s8)
        }
    }

    private func chip(_ text: String, id: String) -> some View {
        Text(text).typeRole(.data)
            .foregroundStyle(Theme.Ink.ink2)
            .padding(.horizontal, Theme.Metric.s8)
            .padding(.vertical, 4)
            .background(Theme.Surface.panel)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                    .stroke(Theme.Line.line2, lineWidth: 1)
            }
            .accessibilityIdentifier(id)
    }

    private func toggleButton(_ label: String, glyph: String, on: Bool, id: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph).font(.system(size: 13))
                .foregroundStyle(on ? Theme.Accent.clayStrong : Theme.Ink.ink2)
                .frame(width: 32, height: 32)
                .background(on ? Theme.Accent.clayTint : Theme.Surface.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(on ? Theme.Accent.clay : Theme.Line.line2, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
        .accessibilityValue(on ? "on" : "off")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : [.isButton])
    }

    private func stepButton(_ glyph: String, label: String, id: String,
                            enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph).font(.system(size: 13))
                .foregroundStyle(enabled ? Theme.Ink.ink : Theme.Ink.ink3)
                .frame(width: 32, height: 32)
                .background(Theme.Surface.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(Theme.Line.line2, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
    }
}
