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
    /// What the top bar seats at its current width (0.6.8).
    ///
    /// Performance mode and Show transport are BAR controls now -- the two
    /// screens they used to be from the music. This screen keeps them at
    /// exactly the widths the bar cannot seat them, which is a phone, and
    /// shows neither anywhere else.
    ///
    /// Read from `ContentView`'s one measurement rather than measured again
    /// here: two notions of what fits would put a switch in both places at some
    /// width and in neither at another.
    var barFit: ScoreBarLayout.Fit = ScoreBarLayout.Fit(showsVersions: true,
                                                        layoutCells: 3)
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
            // Performance mode moved to the TOP BAR (0.6.8): it is the one
            // control that changes what every input on the music means, and it
            // sat two screens away from that music. It stays here at the widths
            // the bar cannot seat it -- a phone -- because an access path is
            // not removed until its replacement exists at that width, and on a
            // phone it does not (ScoreBarLayout).
            //
            // The app's own switch, not the system's. This was the one stock
            // iOS control left anywhere in it (L33).
            if barFit.optionsCarriesPerformanceToggle {
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
            }

            // Only for a scan, and only while it IS one: once OMR has run, the
            // arrangement has a notation version and the row has nothing left
            // to offer. A row that stays and does nothing is worse than a row
            // that goes.
            if state.displayedArtifact == .scan {
                makeEditableRow
                note("This arrangement is a PDF. Reading it produces a notation "
                     + "version you can transpose, select and ask about — the "
                     + "PDF stays as it is, so you can compare them.")
            }
            // "Score display" is gone (0.6.3 #6). It held page/spread/
            // continuous -- which are three buttons at the TOP of the score,
            // where a reader can see what they are looking at -- and the
            // transport switch, which is now beside them. What was left behind
            // it was chord symbols, so chord symbols come up a level rather
            // than sitting two screens deep (#7).
            //
            // The transport switch is a BAR control (0.6.3 #6), and since 0.6.8
            // it is here ONLY where the bar has yielded it -- the same rule
            // Performance mode follows above. It was in both places at every
            // width, which is one switch too many on an iPad and the reason the
            // bar's copy read as a duplicate rather than as the control.
            if barFit.optionsCarriesTransportToggle {
                PanelToggle(title: "Show transport", isOn: $showTransport)
                    .padding(.horizontal, Theme.Metric.s20)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("more-transport")
            }
            ScreenRow(title: "Chord symbols", value: "\(state.chordDefaultSize) pt",
                      identifier: "more-chords") { push("Chord symbols") }
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
            // "Versions" is gone from here (0.6.3 #8). The versions dropdown
            // at the top of the score is the way in, and it now shows versions
            // and NOTHING ELSE -- which is what made a second list necessary.
            // The section body below is kept: "All N versions" in the dropdown
            // still pushes it.
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

    /// OMR, offered the way Performance mode is offered: a switch, because a
    /// row that performs among rows that lead does not read as pressable
    /// (MakeEditable). It reports its own progress in place and does not pop
    /// the screen -- popping is what made pressing it look like nothing had
    /// happened.
    ///
    /// One-way: OMR cannot be un-run. When it succeeds the arrangement is no
    /// longer a scan and this row goes; when it fails the switch comes back
    /// off and the notice says why.
    private var makeEditableRow: some View {
        let omr = MakeEditable.control(busy: state.omrBusy,
                                       stage: state.omrStage,
                                       fraction: state.omrFraction)
        return VStack(alignment: .leading, spacing: 7) {
            PanelToggle(title: "Make editable",
                        isOn: Binding(get: { omr.isOn },
                                      set: { on in
                                          guard on, omr.acceptsTap else { return }
                                          state.makeEditable()
                                      }))
            HStack(spacing: Theme.Metric.s8) {
                if omr.showsSpinner {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.Accent.clay)
                }
                Text(omr.detail)
                    .typeRole(.meta)
                    .foregroundStyle(Theme.Ink.ink3)
                Spacer(minLength: 0)
            }
            if let fraction = omr.fraction {
                ProgressView(value: fraction)
                    .tint(Theme.Accent.clay)
                    .frame(maxWidth: 220)
            }
        }
        .padding(.horizontal, Theme.Metric.s20)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Line.line).frame(height: 1)
        }
        .accessibilityIdentifier("more-make-editable")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Make editable, \(omr.detail)")
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

        // The LADDER, tappable. The stepper above it was reported as a
        // control that controls nothing -- two SF Symbol glyphs and a number,
        // where the number was the obvious thing to press and was not a
        // button at all. Every rung is a button now, so "18" can be reached by
        // tapping 18. The stepper stays: it is the path for anyone stepping
        // one rung at a time, and an access path is not removed in the build
        // that adds its replacement.
        sizeLadder

        note("New chord symbols inherit this. A symbol you have nudged or "
             + "resized keeps its own size until you reset it.")

        // WHICH part it lands on. A part-wide op that names no part is
        // indistinguishable from one that never ran, which is exactly how
        // this control came to be reported as dead.
        if let part = state.chordPartName() {
            ScreenRow(title: "Applies to", value: part, leads: false,
                      identifier: "chords-part") {}
                .disabled(true)
        } else {
            note("No arrangement is open, so there is nothing to resize.")
        }

        // "Reset all adjustments" was here and is gone (0.6.3 #7): a
        // destructive part-wide op on a screen whose other control is a size
        // stepper. Per-element reset is unaffected -- it lives on the element's
        // own adjust bar, where the thing being reset is on screen.
    }

    /// Every size a chord symbol can take, as buttons.
    private var sizeLadder: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Metric.s6) {
            ForEach(ChordAdjustSession.sizeLadder, id: \.self) { size in
                let selected = size == state.chordDefaultSize
                Button {
                    state.setChordDefault(size)
                } label: {
                    Text("\(size)")
                        .typeRole(.data)
                        .foregroundStyle(selected ? Theme.Accent.clayStrong : Theme.Ink.ink2)
                        .frame(minWidth: 40, minHeight: 34)
                        .background(selected ? Theme.Accent.clayTint : Theme.Surface.panel)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                                .stroke(selected ? Theme.Accent.clay : Theme.Line.line2,
                                        lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(size) point")
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
                .accessibilityIdentifier("chords-size-\(size)")
            }
            }
            .padding(.horizontal, Theme.Metric.s20)
        }
        .padding(.bottom, Theme.Metric.s12)
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
            // "Score display" lived here (0.6.3 #6). Page / spread /
            // continuous are three buttons at the top of the score and the
            // transport switch is beside them; a second surface for the same
            // two properties is how the impossible state got in last time.
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
                // The mode used to be named here -- "Pencil: select" -- and
                // that label is what Ali asked off every screen. The guidance
                // under it is the part worth keeping.
                note("Hold a finger down while drawing to add to the "
                     + "selection; tap an element to drop it.")
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
                        ScreenRow(title: version.id,
                                  value: VersionLabel.text(op: version.op,
                                                           prompt: version.turn?.prompt),
                                  leads: false,
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
    /// Which list this is. The band shows ONE, chosen by the control that
    /// opened it -- the versions dropdown was showing a column of other
    /// pieces beside the versions it was asked for (0.6.3 #8).
    var mode: TitleBandLayout.Mode
    var onPickArrangement: (String) -> Void
    var onPickVersion: (String?) -> Void
    var onAllVersions: () -> Void
    /// The height the score has to give: the band takes what it needs of it,
    /// up to `TitleBandLayout.maxFraction`, and scrolls past that.
    var available: CGFloat = 0

    private var piece: PieceDoc? {
        state.manifest?.pieces?.first { $0.arrangements.contains(score.slug) }
    }

    /// EVERY version, newest first. It was the last four, with the rest behind
    /// an "All N versions" row that pushed a screen -- which is the loop a
    /// reader hit when the version they wanted was the fifth one back. The band
    /// scrolls (TitleBandLayout), so a long history costs height it already
    /// knows how to cap.
    private var shownVersions: [VersionDoc] { Array(score.versions.reversed()) }
    /// The grouped history is still one row away: it shows what PROMPT made a
    /// run of versions, which this flat list cannot.
    private var hasAllVersionsRow: Bool { score.versions.count > 4 }

    private var arrangements: [String] { piece?.arrangements ?? [score.slug] }

    /// The same labels the piece screen shows, by the same rule: a title that
    /// is really the workspace's file name loses to the arrangement's own
    /// name, and no two rows may read the same.
    private var arrangementLabels: [String: String] {
        let scores = arrangements.compactMap { slug in
            state.manifest?.scores.first { $0.slug == slug }
        }
        let shown = ScoreTitle.labels(for: scores.map {
            ScoreTitle.Arrangement(title: $0.title, name: $0.name, slug: $0.slug,
                                   parts: ($0.versions.last?.parts ?? []).map(\.name),
                                   isScan: ArtifactTag.holding(of: $0) == .pdf)
        })
        return Dictionary(uniqueKeysWithValues: zip(scores.map(\.slug), shown))
    }

    private var setlistCount: Int { state.manifest?.setlists?.count ?? 0 }

    /// One row count per mode, and read from the mode rather than defaulted.
    ///
    /// It was `mode == .versions ? versions : arrangements`, so a third mode
    /// would silently have been sized by the arrangement count -- a band with
    /// eight set lists and two arrangements opening two rows tall, its
    /// checklist scrolled out of sight.
    private var contentHeight: CGFloat {
        let rows: Int
        switch mode {
        case .versions:     rows = shownVersions.count
        case .arrangements: rows = arrangements.count
        case .setlists:     rows = setlistCount
        }
        return TitleBandLayout.contentHeight(mode: mode, rows: rows,
                                             hasAllVersionsRow: hasAllVersionsRow)
    }

    var body: some View {
        ScrollView {
            column
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

    @ViewBuilder
    private var column: some View {
        switch mode {
        case .arrangements: arrangementColumn
        case .versions:     versionColumn
        case .setlists:     setlistColumn
        }
    }

    private var arrangementColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            BandHeader(piece.map { "Arrangements of \($0.name)" } ?? "Arrangements")
            ForEach(Array(arrangements.enumerated()), id: \.offset) { index, slug in
                if let arrangement = state.manifest?.scores.first(where: { $0.slug == slug }) {
                    switchRow(title: arrangementLabels[slug]
                                     ?? ScoreTitle.arrangementName(
                                            title: arrangement.title,
                                            name: arrangement.name,
                                            slug: arrangement.slug),
                              number: index + 1,
                              selected: slug == score.slug,
                              id: "menu-arrangement-\(slug)") { onPickArrangement(slug) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var versionColumn: some View {
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

    /// Which set lists this arrangement is in, one box each (0.6.11 #1).
    ///
    /// The rows come from `SetlistMembership`, which is where the two
    /// decisions live: the order is by NAME and never by membership, so a box
    /// checked under the finger does not move the row out from under the next
    /// tap; and a tap resolves to `.add` or `.remove` read off the row rather
    /// than a Bool a caller has to interpret.
    ///
    /// The band STAYS OPEN on a tap, like the sound picker and unlike the
    /// arrangement and version rows -- those switch what you are looking at
    /// and have nothing more to say, while this is a checklist and a reader
    /// putting one arrangement in three set lists should not reopen it twice.
    private var setlistColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            BandHeader("Set lists")
            let rows = SetlistMembership.rows(for: score.slug,
                                              in: state.manifest?.setlists ?? [])
            if rows.isEmpty {
                // Not an empty band: a line saying where set lists come from.
                // The library makes them; this only files an arrangement into
                // one that exists, and a blank panel would read as broken.
                PanelNote(text: "No set lists yet. Make one in the library, "
                          + "then this arrangement can go in it.")
                    .padding(.horizontal, Theme.Metric.s16)
                    .padding(.vertical, 8)
            }
            ForEach(rows) { row in
                setlistRow(row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One set list, with its box.
    ///
    /// The count is shown as the row's `detail` rather than in the title, so
    /// the names line up and a reader scanning for "Friday night" is not
    /// reading past a number to find it.
    private func setlistRow(_ row: SetlistMembership.Row) -> some View {
        Button {
            switch SetlistMembership.tap(row) {
            case .add(let setlist):
                Task { await state.addToSetlist(setlist: setlist, score: score.slug) }
            case .remove(let setlist):
                Task { await state.removeFromSetlist(setlist: setlist,
                                                     score: score.slug) }
            }
        } label: {
            HStack(spacing: Theme.Metric.s8) {
                // A box, not a checkmark on the trailing edge: this row is a
                // CHECKLIST entry that toggles, and the version rows' trailing
                // tick means "this is the one you are looking at". Two
                // different meanings should not share one mark.
                Image(systemName: row.isMember ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(row.isMember ? Theme.Accent.clayStrong
                                                  : Theme.Ink.ink3)
                Text(row.name).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                    .lineLimit(1)
                Spacer(minLength: Theme.Metric.s8)
                Text(row.count == 1 ? "1 arrangement" : "\(row.count) arrangements")
                    .typeRole(.data).foregroundStyle(Theme.Ink.ink3).fixedSize()
            }
            .padding(.horizontal, Theme.Metric.s16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.name)
        .accessibilityValue(row.isMember ? "in this set list" : "not in this set list")
        .accessibilityHint(row.isMember ? "Remove from this set list"
                                        : "Add to this set list")
        .accessibilityAddTraits(row.isMember ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("setlist-check-\(row.slug)")
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
