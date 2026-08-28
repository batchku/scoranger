import SwiftUI

/// The score view's own pushed screens (NAV_MODAL_FREE_0.4.2 §7).
///
/// The score view is a full-screen place with ✕, not a modal, so it stays --
/// but its two floating panels do not. The `…` popover becomes this screen, and
/// back returns to the score with its page and zoom intact, because the score
/// was never torn down: it is simply covered.
enum ScoreScreen: Hashable {
    case options
    case optionsSection(String)
    case details
    case settings
    case chatModel
}

struct ScoreOptionsScreen: View {
    @EnvironmentObject var state: AppState
    @Binding var mode: ScoreMode
    @Binding var showTransport: Bool
    var section: String?
    var onBack: () -> Void
    var push: (String) -> Void
    var onSettings: () -> Void
    var onDetails: () -> Void

    /// The format currently being written, so its row can say so: engraving a
    /// PDF of a long score takes a moment and a dead row reads as a dead app.
    @State private var exporting: ScoreExport.Format?
    /// The finished file, handed to Apple's share sheet.
    ///
    /// This is the ONE modal in the app, and it is deliberate: the system share
    /// sheet is how iOS puts a file into Files, Mail or another program, and
    /// re-implementing it would be both worse and impossible.
    @State private var sharing: URL?
    /// The two-step inline confirm for the part-wide reset (no dialog).
    @State private var resettingChords = false

    var body: some View {
        Group {
            if let section {
                Screen(title: section, backLabel: "Options", onBack: onBack) {
                    sectionBody(section)
                }
            } else {
                Screen(title: "Options", backLabel: "Score", onBack: onBack) {
                    root
                }
            }
        }
        // Apple's own sheet, and the only one in the app: it is how iOS puts a
        // file into Files, Mail or another program.
        .sheet(item: $sharing) { url in
            SystemShareSheet(url: url)
        }
    }

    private var root: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Performance mode first and lit, because it is the one entry that
            // changes what every input means (§6 of the navigation system).
            // The app's own switch, not the system's. This was the one stock
            // iOS control left anywhere in it (L33) -- and it sat in the most
            // prominent row of the options screen.
            PanelToggle(title: "Performance mode",
                        isOn: Binding(get: { mode == .performance },
                                      set: { on in
                                          mode = on ? .performance : .read
                                          if on { state.annotation.isOn = false }
                                          onBack()
                                      }))
                .accessibilityIdentifier("more-performance")
                .padding(.horizontal, Theme.Metric.s20)
                .padding(.vertical, 11)
                .background(Theme.Accent.clayTint)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.Line.line).frame(height: 1)
                }

            ScreenRow(title: "Score display", value: state.twoPageSpread ? "two pages" : "one page",
                      identifier: "more-display") { push("Score display") }
            // Every row states its current answer where it has one. A screen of
            // bare labels is a menu; the answers are what make it a summary of
            // where the score stands (L34).
            ScreenRow(title: "Annotations",
                      value: state.annotation.isOn ? "on" : "off",
                      identifier: "more-annotations") {
                push("Annotations")
            }
            ScreenRow(title: "Selection & chat",
                      value: state.activeSelection.map {
                          "\($0.addresses.count) selected"
                      } ?? "nothing selected",
                      identifier: "more-selection") {
                push("Selection & chat")
            }
            ScreenRow(title: "Transpose", value: "by interval",
                      identifier: "more-transpose") { push("Transpose") }
            ScreenRow(title: "Versions",
                      value: state.selectedScore.map {
                          "\(state.displayedVersionID ?? "—") of \($0.versions.count)"
                      } ?? state.displayedVersionID,
                      identifier: "more-versions") { push("Versions") }
            ScreenRow(title: "Piece & arrangement details",
                      value: state.selectedScore.flatMap { score in
                          state.placement(of: score.slug)?.piece.name
                      },
                      identifier: "more-details") {
                onDetails()
            }
            ScreenRow(title: "Share & export", value: "MusicXML · MIDI · PDF",
                      identifier: "more-export") {
                push("Share & export")
            }
            ScreenRow(title: "Settings",
                      value: state.useLocalEngine ? "on-device" : "remote",
                      identifier: "more-settings") { onSettings() }
        }
        .padding(.bottom, Theme.Metric.s32)
    }

    /// The part-wide half of size and position: the default every chord symbol
    /// in the part inherits, and the way back out of every override.
    ///
    /// Per-element values are absolute points in the notation, so they survive
    /// this default changing -- which is the point of storing them that way.
    @ViewBuilder
    private var chordSymbolRows: some View {
        HStack(spacing: Theme.Metric.s8) {
            Text("Default size").typeRole(.row).foregroundStyle(Theme.Ink.ink)
            Spacer(minLength: Theme.Metric.s8)
            Button {
                state.stepChordDefault(.smaller)
            } label: {
                Image(systemName: "textformat.size.smaller")
                    .frame(width: 34, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!state.canStepChordDefault(.smaller))
            .opacity(state.canStepChordDefault(.smaller) ? 1 : 0.42)
            .accessibilityLabel("Smaller default chord size")
            .accessibilityIdentifier("chords-smaller")

            Text("\(state.chordDefaultSize) pt")
                .typeRole(.data).foregroundStyle(Theme.Ink.ink)
                .frame(minWidth: 44)
                .accessibilityIdentifier("chords-size")

            Button {
                state.stepChordDefault(.bigger)
            } label: {
                Image(systemName: "textformat.size.larger")
                    .frame(width: 34, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!state.canStepChordDefault(.bigger))
            .opacity(state.canStepChordDefault(.bigger) ? 1 : 0.42)
            .accessibilityLabel("Bigger default chord size")
            .accessibilityIdentifier("chords-bigger")
        }
        .padding(.horizontal, Theme.Metric.s20)
        .padding(.vertical, Theme.Metric.s12)

        note("New chord symbols inherit this. A symbol you have nudged or "
             + "resized keeps its own size until you reset it.")

        BandHeader("Careful")
        if resettingChords {
            ConfirmDeleteStrip(what: "every chord symbol's size and position in this part",
                               verb: "Reset all",
                               identifier: "chords-confirm-reset",
                               onDelete: {
                                   resettingChords = false
                                   state.resetAllChordAdjustments()
                               },
                               onKeep: { resettingChords = false })
        } else {
            ScreenRow(title: "Reset all adjustments", leads: false,
                      isDestructive: true,
                      identifier: "chords-reset-all") { resettingChords = true }
        }
    }

    /// One row per format, each saying what it is FOR rather than what it is:
    /// "Open in another notation program" beats "MusicXML" for anyone who does
    /// not already know what MusicXML is.
    @ViewBuilder
    private var exportRows: some View {
        ForEach(ScoreExport.Format.allCases, id: \.rawValue) { format in
            ScreenRow(title: format.label,
                      value: exporting == format ? "preparing…" : format.detail,
                      leads: false,
                      identifier: "export-\(format.rawValue)") {
                guard exporting == nil, let score = state.selectedScore else { return }
                exporting = format
                Task {
                    let pinned = state.pinnedVersion
                    sharing = await state.exportFile(slug: score.slug,
                                                     version: pinned,
                                                     format: format)
                    exporting = nil
                }
            }
            .disabled(exporting != nil)
        }
        note("The file is named for the arrangement, and carries the version "
             + "number only when you are looking at an older one.")
    }

    @ViewBuilder
    private func sectionBody(_ section: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch section {
            case "Score display":
                ScreenRow(title: "Chord symbols", value: "size and position",
                          identifier: "display-chords") { push("Chord symbols") }
                PanelToggle(title: "Two pages side by side", isOn: $state.twoPageSpread)
                    .padding(Theme.Metric.s20)
                    .accessibilityIdentifier("display-spread")
                PanelToggle(title: "Show transport (preview)", isOn: $showTransport)
                    .padding(.horizontal, Theme.Metric.s20)
                    .accessibilityIdentifier("display-transport")
                note("Playback is not wired up. Previous and next step the current "
                     + "set list, and those work.")
            case "Annotations":
                ScreenRow(title: "Clear markup on this version", leads: false,
                          isDestructive: true, identifier: "annotations-clear") {
                    if let score = state.selectedScore, let vid = state.displayedVersionID {
                        DrawingStore.shared.clear(prefix: "\(score.slug)/\(vid)")
                        Task { await state.renderIfNeeded(force: true) }
                    }
                    onBack()
                }
                note("Ink belongs to the version it was drawn on.")
            case "Selection & chat":
                ScreenRow(title: "Clear selection", leads: false,
                          identifier: "selection-clear") { state.clearSelection(); onBack() }
                note(mode.pencilMeaning + ". Hold a finger down while drawing to add "
                     + "to the selection; tap an element to drop it.")
            case "Transpose":
                ScreenRow(title: "Up a semitone", leads: false,
                          identifier: "transpose-up") { state.transpose(semitones: 1); onBack() }
                ScreenRow(title: "Down a semitone", leads: false,
                          identifier: "transpose-down") { state.transpose(semitones: -1); onBack() }
                note("Transposes the whole arrangement. To move only some notes, "
                     + "select them and ask in chat.")
            case "Versions":
                if let score = state.selectedScore {
                    ForEach(score.versions.reversed(), id: \.id) { version in
                        ScreenRow(title: version.id, value: version.op, leads: false,
                                  identifier: "version-\(version.id)") {
                            state.pinnedVersion = version.id == score.latest ? nil : version.id
                            Task { await state.renderIfNeeded() }
                            onBack()
                        }
                    }
                }
            case "Chord symbols":
                chordSymbolRows
            case "Share & export":
                exportRows
            default:
                EmptyView()
            }
        }
        .padding(.bottom, Theme.Metric.s32)
    }

    private func note(_ text: String) -> some View {
        Text(text).typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Metric.s20)
            .padding(.vertical, Theme.Metric.s8)
    }
}

/// The title switcher (§7.1): an inline band below the top bar.
///
/// It pushes the score down rather than floating over it, and the paged canvas
/// simply fits into less height -- which is the one real advantage of paging
/// here, since there is no scroll offset to preserve.
struct TitleSwitcherBand: View {
    @EnvironmentObject var state: AppState
    let score: ScoreDoc
    var onPickArrangement: (String) -> Void
    var onPickVersion: (String?) -> Void
    var onAllVersions: () -> Void
    /// The height the score has to give: the band takes what it needs of it,
    /// up to `TitleBandLayout.maxFraction`, and scrolls past that.
    var available: CGFloat = 0

    private var piece: PieceDoc? {
        state.manifest?.pieces?.first { $0.arrangements.contains(score.slug) }
    }

    private var shownVersions: [VersionDoc] { Array(score.versions.suffix(4).reversed()) }
    private var hasAllVersionsRow: Bool { score.versions.count > 4 }

    private var contentHeight: CGFloat {
        TitleBandLayout.contentHeight(arrangements: (piece?.arrangements ?? [score.slug]).count,
                                      versions: shownVersions.count,
                                      hasAllVersionsRow: hasAllVersionsRow)
    }

    var body: some View {
        ScrollView {
            columns
        }
        .frame(height: TitleBandLayout.height(content: contentHeight,
                                              available: available))
        .scrollDisabled(!TitleBandLayout.scrolls(content: contentHeight,
                                                 available: available))
        .background(Theme.Surface.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Line.line).frame(height: 1) }
        // NO identifier on this container. An identifier on a stack is taken by
        // its children: the two columns became two buttons both called
        // "title-switcher" and every row inside them -- the arrangements, the
        // versions -- stopped existing. The band was open and unusable, and the
        // only way to switch version while reading went with it.
        .accessibilityElement(children: .contain)
    }

    private var columns: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                BandHeader(piece.map { "Arrangements of \($0.name)" } ?? "Arrangements")
                ForEach(Array((piece?.arrangements ?? [score.slug]).enumerated()),
                        id: \.offset) { index, slug in
                    if let arrangement = state.manifest?.scores.first(where: { $0.slug == slug }) {
                        switchRow(title: arrangement.title ?? arrangement.name,
                                  number: index + 1,
                                  selected: slug == score.slug,
                                  id: "menu-arrangement-\(slug)") { onPickArrangement(slug) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                BandHeader("Versions")
                ForEach(shownVersions, id: \.id) { version in
                    // What MADE the version, not just its id: "v003 / v002 /
                    // v001" told a reader nothing, so switching version while
                    // reading was a guess.
                    switchRow(title: TitleBandLayout.versionLabel(
                                        prompt: version.turn?.prompt, op: version.op),
                              number: nil,
                              detail: version.id,
                              selected: version.id == state.displayedVersionID,
                              id: "menu-version-\(version.id)") {
                        onPickVersion(version.id == score.latest ? nil : version.id)
                    }
                }
                if hasAllVersionsRow {
                    ScreenRow(title: "All \(score.versions.count) versions",
                              identifier: "menu-all-versions", action: onAllVersions)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The rule between the columns is an OVERLAY, not a member of the
        // stack. As a member it was `Rectangle().frame(width: 1)` -- a shape
        // with a width and no height, which takes every point it is offered
        // and took the band with it: five rows filled half the screen and the
        // music was squeezed into what was left.
        .overlay { Rectangle().fill(Theme.Line.line).frame(width: 1) }
    }

    private func switchRow(title: String, number: Int?, detail: String? = nil,
                           selected: Bool, id: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Metric.s8) {
                if let number { NumeralBadge(number: number, role: .numeralM) }
                if let detail {
                    Text(detail).typeRole(.data).foregroundStyle(Theme.Ink.ink3)
                        .fixedSize()
                }
                Text(title).typeRole(.row).foregroundStyle(Theme.Ink.ink).lineLimit(1)
                Spacer(minLength: Theme.Metric.s8)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Accent.clayStrong)
                }
            }
            .padding(.horizontal, Theme.Metric.s16)
            .padding(.vertical, 8)
            .background(selected ? Theme.Accent.clayTint : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.map { "\($0), \(title)" } ?? title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier(id)
    }
}

/// Which model answers (§7.3). The chat header's `Menu` becomes this.
struct ChatModelScreen: View {
    @EnvironmentObject var state: AppState
    var onBack: () -> Void

    var body: some View {
        Screen(title: "Chat model", backLabel: "Chat", onBack: onBack) {
            VStack(alignment: .leading, spacing: 0) {
                BandHeader("Models")
                if let catalog = state.modelCatalog {
                    ForEach(catalog.models.keys.sorted(), id: \.self) { alias in
                        ScreenRow(title: alias, value: catalog.models[alias],
                                  leads: false,
                                  identifier: "chat-model-\(alias)") {
                            state.chatModel = alias
                            onBack()
                        }
                    }
                } else {
                    Text("The model list loads once the engine is reachable.")
                        .typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                        .padding(Theme.Metric.s20)
                }
            }
            .padding(.bottom, Theme.Metric.s32)
        }
    }
}
