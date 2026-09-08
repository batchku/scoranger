import SwiftUI
import UniformTypeIdentifiers

/// Score-first (§7, §8): the score is the permanent ground, the library and chat
/// slide over it, and every canvas control lives in one pill. There is no
/// navigation bar, no title bar and no split view — losing `NavigationSplitView`
/// is the largest change in the revamp.
struct ContentView: View {
    /// Leaving the score. The score view is presented OVER the tab bar and X is
    /// how you leave it (NAVIGATION_SYSTEM.md §3); the tabs own where "back"
    /// goes, so this only reports that it happened.
    var onClose: () -> Void = {}

    @EnvironmentObject var state: AppState
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The two overlays, which replace the split view's columns.

    /// Off by default and named a preview (§9.2): a transport that does nothing
    /// teaches people the app is broken. Previous and next step the setlist and
    /// work whether or not this is on.
    /// Defaults to TRUE since 0.6.1. It was false, and playback -- the whole
    /// of 0.6 -- was invisible behind a toggle in a submenu.
    @AppStorage("showTransport") private var showTransport = true
    /// Whether the transport has ever been put on screen unasked. Carries a
    /// reader holding a stored `false` from the builds where that was the
    /// default (see TransportReveal).
    @AppStorage("didRevealTransport") private var didRevealTransport = false

    /// Lane 1 is the ink bar's, and it is only occupied when the bar is out.
    private var inkLaneHeight: CGFloat { state.annotation.isOn ? 56 : 0 }
    private var syncLaneInset: CGFloat { inkLaneHeight + 12 }
    /// The mixer sits above whichever lanes are occupied. Recomputed when a
    /// lane appears or disappears -- never per frame, or the panel drifts
    /// under the reader's hand.
    private var mixerLaneInset: CGFloat { syncLaneInset + 48 }
    /// Which list the title band is showing. The versions dropdown and the
    /// title block open the same band on two different columns (0.6.3 #8).
    @State private var titleMenuMode: TitleBandLayout.Mode = .versions
    @State private var exportRequested = 0
    @State private var scoreScreen: ScoreScreen?
    @State private var optionsSection: String?
    @State private var chatOpen = false
    @State private var didSetInitialOverlays = false
    /// The height the score view has, so the title band can be capped against
    /// it rather than taking whatever it is offered (L16).
    @State private var scoreHeight: CGFloat = 0
    /// The top bar's measured width, owned here because TWO views decide from
    /// it: the bar seats what it can, and Options carries the switches the bar
    /// could not (0.6.8). One measurement, one `Fit`, so a switch cannot end up
    /// in both places or in neither.
    @State private var barWidth: CGFloat = 0
    /// The keyboard, watched rather than obeyed: the score screen opts out of
    /// SwiftUI's automatic avoidance so the page keeps its size, and the chat
    /// panel lifts its own input instead (#59).
    @StateObject private var keyboard = KeyboardObserver()

    @State private var showSettings = false
    @State private var showImporter = false
    /// Piece rows are expanded by default; track only the collapsed ones.
    @State private var collapsedPieces: Set<String> = []
    @State private var collapsedSetlists: Set<String> = []
    /// Arrangements showing their version history.
    @State private var expandedArrangements: Set<String> = []
    /// Prompt groups showing their steps, keyed "<slug>/<group id>".
    @State private var expandedVersionGroups: Set<String> = []
    @State private var infoScore: ScoreDoc?
    @State private var importTargetPiece: String?
    /// Every dialog goes through one request, so they cannot disagree.
    @State private var newPieceName = ""
    @State private var newSetlistName = ""
    /// An arrangement that should go into the setlist about to be created.
    @State private var setlistSeedScore: String?
    /// The setlist whose arrangement picker is open.
    @State private var setlistPicker: SetlistDoc?
    /// The arrangement being put into a set list from its own row.
    @State private var setlistChooserScore: ScoreDoc?

    /// The list moved to `ImportKind`, where the tests can reach it. Kept
    /// here under its own name: this is where the rest of the app asks.
    static let scoreTypes: [UTType] = ImportKind.scoreTypes

    /// Build identity, read from the bundle so what is displayed is exactly the
    /// CFBundleVersion App Store Connect records.
    static let buildStamp: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let sha = (Bundle.main.url(forResource: "build-sha", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) })?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "v\(version) · b\(build)" + (sha.map { " · \($0)" } ?? "")
    }()

    private var isCompact: Bool { hSize == .compact }

    /// A PHONE ON ITS SIDE, which is the only place both size classes are
    /// compact. It is the case with 130pt of chrome budget rather than 266,
    /// and the one §3 E-B merges the deck for.
    ///
    /// IT IS NEVER TRUE TODAY. The app is portrait-only on iPhone, and the
    /// one line that says so is
    /// `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone` in
    /// project.yml -- which carries the note about what else wakes up when it
    /// changes. Kept rather than deleted because the layout it chooses is
    /// designed, built and tested: it is waiting for the orientation, not for
    /// the code.
    private var isPhoneLandscape: Bool { isCompact && vSize == .compact }

    /// Go to the unit holding that page.
    ///
    /// A tap on the rail or the scrubber is a page turned BY THE READER just
    /// as much as a swipe is, so it yields following the same way. It does not
    /// go through `step(by:)`, which is where the swipe path hooks this -- so
    /// it needs its own call, or paging from either control would leave the
    /// score snapping back.
    ///
    /// One function, because the rail and the scrubber are two shapes of the
    /// same act and a second copy would drift from this one.
    /// The scrubber, when it is riding in the transport's row rather than
    /// having one of its own. Nil everywhere else, which is what makes the
    /// deck a merge rather than a duplicate.
    private var mergedScrubber: AnyView? {
        guard isPhoneLandscape, state.scoreMode != .performance,
              !state.layout.isContinuous,
              let document = state.pdfDocument else { return nil }
        return AnyView(PageScrubber(pageCount: document.pageCount,
                                    current: state.visiblePageIndices.first ?? 0,
                                    onJump: jumpToPage)
            .background(Color.clear))
    }

    private func jumpToPage(_ index: Int) {
        state.readerTurnedPage()
        state.pageIndex = PagedCanvas.index(forPage: index,
                                            spread: state.twoPageSpread)
    }

    /// What the top bar can seat at its measured width. Read by the bar and by
    /// Options, which carries what the bar could not.
    private var barFit: ScoreBarLayout.Fit {
        ScoreBarLayout.fit(barWidth: barWidth, omrBusy: state.omrBusy)
    }

    var body: some View {
        // A GeometryReader, and not a measurement taken anywhere inside: it is
        // handed its size by its PARENT and nothing below it can change that.
        // Every other place this could go is downstream of the bar -- a
        // `.background` is sized to its content, and a VStack widens to its
        // widest child -- so an overflowing bar reports its overflow, believes
        // it has the room, and seats one more control. Measured on an iPhone
        // 17 Pro: a 402pt screen reporting 411 and seating the numeral and the
        // subtitle it could not draw, with the title left as "S…".
        //
        // The width is also IMPOSED, not only measured. Without the frame the
        // stack is still free to grow past the screen; with it, the bar has to
        // fit inside what it was told.
        GeometryReader { geo in
            ZStack {
                scoreBody
                if let screen = scoreScreen { scoreScreenView(screen) }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { barWidth = geo.size.width }
            .onChange(of: geo.size.width) { _, new in barWidth = new }
        }
    }

    /// Reveal the transport the first time an arrangement can play.
    private func revealTransportIfNeeded() {
        let d = TransportReveal.decide(canPlay: state.playbackAvailability.canPlay,
                                       showTransport: showTransport,
                                       alreadyRevealed: didRevealTransport)
        if d.showTransport != showTransport { showTransport = d.showTransport }
        if d.revealed != didRevealTransport { didRevealTransport = d.revealed }
    }

    @ViewBuilder
    private func scoreScreenView(_ screen: ScoreScreen) -> some View {
        switch screen {
        case .options, .optionsSection:
            ScoreOptionsScreen(mode: $state.scoreMode,
                               showTransport: $showTransport,
                               barFit: barFit,
                               section: optionsSection,
                               onBack: {
                                   if optionsSection != nil { optionsSection = nil }
                                   else { scoreScreen = nil }
                               },
                               push: { optionsSection = $0 },
                               onSettings: { scoreScreen = .settings },
                               onDetails: { scoreScreen = .details },
                               onSetlists: { scoreScreen = .setlists })
                .background(Theme.Surface.ground)
                .accessibilityIdentifier("score-options")
        case .setlists:
            // The pieces list's own screen (Route.setlistsFor -> this same
            // view), pushed from here because the score's stack is keyed by
            // ScoreScreen and not by Route. Nothing about it is re-implemented:
            // the checklist, the inline "New set list" that files this
            // arrangement into what it makes, and the wording are all the ones
            // a reader met coming the other way.
            if let score = state.selectedScore {
                // No identifier on the container, deliberately. An
                // accessibilityIdentifier applied to a whole Screen lands on
                // its first element and REPLACES the one already there --
                // PieceScreen's back button reports `screen-piece-<slug>` and
                // not `screen-back` for exactly that reason. Naming this one
                // would have made the two entrances differ in the tree, which
                // is the one thing §16 is trying to avoid.
                SetlistsForScreen(slug: score.slug,
                                  onBack: { scoreScreen = .options })
                    .background(Theme.Surface.ground)
            }
        case .details:
            if let score = state.selectedScore {
                Screen(title: "Details", backLabel: "Options",
                       subtitle: ScoreTitle.arrangementName(title: score.title,
                                                            name: score.name,
                                                            slug: score.slug),
                       onBack: { scoreScreen = .options }) {
                    ScoreInfoView(score: score)
                }
                .background(Theme.Surface.ground)
            }
        case .settings:
            Screen(title: "Settings", backLabel: "Options",
                   onBack: { scoreScreen = .options }) {
                SettingsView()
            }
            .background(Theme.Surface.ground)
        case .chatModel:
            ChatModelScreen(onBack: { scoreScreen = nil })
                .background(Theme.Surface.ground)
        }
    }

    private var scoreBody: some View {
        VStack(spacing: 0) {
            ScoreTopBar(annotation: state.annotation,
                        number: state.selectedScore
                            .flatMap { state.placement(of: $0.slug)?.number },
                        title: scoreTitle,
                        subtitle: scoreSubtitle,
                        mode: $state.scoreMode,
                        titleMenuOpen: $state.titleMenuOpen,
                        titleMenuMode: $titleMenuMode,
                        showTransport: $showTransport,
                        barWidth: $barWidth,
                        moreOpen: Binding(get: { scoreScreen != nil },
                                          set: { on in
                                              scoreScreen = on ? .options : nil
                                              if !on { optionsSection = nil }
                                          }),
                        chatOpen: chatOpen,
                        onClose: onClose,
                        onAsk: {
                            withAnimation(Theme.Motion.overlay(reduced: reduceMotion)) {
                                chatOpen.toggle()
                            }
                        })
            if state.titleMenuOpen, let score = state.selectedScore {
                TitleSwitcherBand(score: score,
                                  mode: titleMenuMode,
                                  onPickArrangement: { slug in
                                      state.titleMenuOpen = false
                                      state.select(slug: slug)
                                  },
                                  onPickVersion: { version in
                                      state.titleMenuOpen = false
                                      state.pinnedVersion = version
                                      Task { await state.renderIfNeeded() }
                                  },
                                  onAllVersions: {
                                      state.titleMenuOpen = false
                                      optionsSection = "Versions"
                                      scoreScreen = .options
                                  },
                                  available: scoreHeight)
            }
            ZStack(alignment: .top) {
                Theme.Surface.ground
                canvasLayer
                overlayLayer
                // The two menus the top bar opens. Plain children of the
                // canvas stack rather than an overlay on the whole view: as an
                // overlay they did not materialise at all, and a menu that
                // cannot be opened is worse than one that is in the wrong place.

            }
            // What this arrangement IS, opposite the counters (0.6.3 #5).
            .overlay(alignment: .topLeading) {
                if state.selectedScore != nil, state.pdfDocument != nil {
                    ArtifactMarker(kind: state.displayedArtifact)
                        .padding(.top, Theme.Metric.s8)
                        .padding(.leading, Theme.Metric.s12)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: Theme.Metric.s6) {
                    if state.selectedScore != nil {
                        LiveCounters(playback: state.playback,
                                     pages: state.layout.showsPageCounter ? pageCounter : nil,
                                     bar: barCounter,
                                     probe: ProcessInfo.processInfo.arguments
                                        .contains("-geometryProbe")
                                        ? [state.geometry?.probeDescription,
                                           state.seedOutcome.map { "seed[\($0)]" }]
                                            .compactMap { $0 }.joined(separator: " ")
                                        : nil)
                            .allowsHitTesting(false)
                    }
                    // The transcription chip where the BAR could not seat it: a
                    // phone at reading width has about four points of slack,
                    // and OMR running with no sign of it in the score view is
                    // what 0.6.8 set out to fix. Same view, same signal -- only
                    // where it sits changes, and it sits here only while the
                    // bar is not showing it.
                    if state.omrBusy, !barFit.showsOMRProgress,
                       state.scoreMode != .performance {
                        OMRProgressChip(control: MakeEditable.control(
                                            busy: state.omrBusy,
                                            stage: state.omrStage,
                                            fraction: state.omrFraction),
                                        action: { scoreScreen = .options })
                    }
                }
                .padding(.top, Theme.Metric.s8)
                // clear of the chat panel: these belong to the music, and they
                // were being drawn over the chat's own header
                .padding(.trailing,
                         ScorePosition.counterTrailingInset(
                            chatOpen: chatOpen, isCompact: isCompact,
                            chatWidth: Theme.Metric.chatWidth,
                            base: Theme.Metric.s12))
            }
            // TWO gates, not one. They were a single condition, and that put
            // the transport behind `!isContinuous` -- so the scrolling view,
            // which is the ONE mode playing along to the score is for, was the
            // only mode with no transport at all.
            //
            // Performance mode still gives the score the whole screen: both go,
            // and the page-turn zones become the point (§4.5).
            //
            // The STRIP is a list of PAGES. Continuous mode has one, so the
            // strip showed a single thumbnail of the whole score -- true, and
            // useless. The designer's position markers are the right answer and
            // are not built yet; showing nothing is better than showing that.
            // A PHONE gets a 28pt scrubber where an iPad gets the 96pt rail.
            // The rail is better where there is room -- a legible thumbnail
            // says what a page IS, which no tick can -- but 96pt is more than
            // a third of a phone's whole chrome budget, spent on thumbnails
            // that at 52x68 show only that a page has staves (§9.6). Neither
            // screen loses a way to reach a page.
            if state.scoreMode != .performance, !state.layout.isContinuous,
               isCompact, !isPhoneLandscape, let document = state.pdfDocument {
                PageScrubber(pageCount: document.pageCount,
                             current: state.visiblePageIndices.first ?? 0,
                             onJump: jumpToPage)
            }
            if state.scoreMode != .performance, !state.layout.isContinuous,
               !isCompact, let document = state.pdfDocument {
                ThumbnailStrip(document: document,
                               current: state.visiblePageIndices,
                               spread: state.twoPageSpread,
                               // straight to the unit holding that page: no
                               // offset arithmetic left to get wrong
                               onJump: jumpToPage)
            }
            // The TRANSPORT is about the music, not about pages, so it belongs
            // in every mode that has chrome at all. It is revealed the first
            // time something can actually play (TransportReveal) -- a reader
            // should never have to know the toggle exists to find playback.
            if state.scoreMode != .performance, showTransport {
                Transport(setlistLabel: setlistLabel,
                          canStep: setlistPosition != nil,
                          onPrevious: { stepSetlist(-1) },
                          onNext: { stepSetlist(1) },
                          playback: state.playback,
                          unavailable: state.playbackAvailability,
                          preparing: state.playbackPreparing,
                          onPlay: { state.togglePlayback() },
                          onResolve: {
                              // The remote-engine case is fixed in Settings,
                              // which this view owns; the scan case is the
                              // engine's business.
                              if state.playbackAvailability == .needsLocalEngine {
                                  scoreScreen = .settings
                              } else {
                                  state.resolvePlaybackAvailability()
                              }
                          },
                          mixerOpen: state.mixerOpen,
                          onMixer: { state.mixerOpen.toggle() },
                          // A phone on its side carries the scrubber IN the
                          // transport: two rows are 76 of a 130pt chrome
                          // budget, one deck is 48 (§3 E-B).
                          leading: mergedScrubber,
                          height: isPhoneLandscape
                              ? Theme.Metric.scoreDeckCompact
                              : Theme.Metric.transportHeight)
                    // Built when the transport appears, never when the score
                    // opens: writing the MIDI takes music21 a moment and
                    // opening an arrangement must not wait on it.
                    .task(id: state.displayedVersionID) {
                        await state.preparePlayback()
                    }
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { scoreHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, new in scoreHeight = new }
            }
        }
        // The ink bar, over the WHOLE score screen -- strip and transport
        // included, so it can be moved anywhere on it (#46).
        .overlay(alignment: .bottom) {
            AnnotationBarLayer(controller: state.annotation)
        }
        // Lane 2 (§4): the sync chip, centred, 12pt above the ink bar's lane.
        // It is transient, so it gets a lane rather than a slot in a row that
        // would reflow around it as it comes and goes.
        .overlay(alignment: .bottom) {
            if state.scoreMode != .performance {
                SyncChipLayer(state: state, playback: state.playback)
                    .padding(.bottom, syncLaneInset)
            }
        }
        // Lane 3 (§4): the mixer, movable, parked bottom-right above the
        // highest occupied lane. LAST in the stack, which is the z-order the
        // spec settles: fixed chrome < ink bar < sync chip < mixer.
        .overlay {
            if state.scoreMode != .performance, state.mixerOpen {
                // The rebuilt window (design/MIXER_WINDOW.md). `MixerLayer` --
                // the panel positioned by arithmetic that was not what got
                // drawn -- is what Ali's iPad clipped.
                MixerWindowLayer(state: state, playback: state.playback,
                                 lanesInset: mixerLaneInset)
            }
        }
        .background(Theme.Surface.ground)
        // #59: the music is not resized by a text field taking focus. The
        // avoidance inset is a safe-area inset on the WHOLE screen -- the
        // canvas lost the keyboard's height and the page re-fitted to what was
        // left, collapsing a full page to a thumbnail. The pushed screens over
        // this one are ZStack siblings and keep their avoidance, so their
        // fields still lift; the chat panel, which lives inside here, lifts
        // itself in `overlayLayer`.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: state.annotation.isOn) { _, on in
            // the ink bar can be dismissed from its own control, and the mode
            // must follow it or the top bar would lie about the Pencil
            if on { state.scoreMode = .edit } else if state.scoreMode == .edit { state.scoreMode = .read }
        }
        .task {
            Theme.verifyFontsRegistered()
            revealTransportIfNeeded()
        }
        // and again when what is on screen changes: the first arrangement
        // opened may be a scan, and the transport should arrive on the first
        // one that can actually play rather than only at launch.
        .onChange(of: state.playbackAvailability) { _, _ in revealTransportIfNeeded() }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: Self.scoreTypes,
                      allowsMultipleSelection: true) { result in
            let piece = importTargetPiece
            importTargetPiece = nil
            if case .success(let urls) = result {
                for url in urls { state.receiveFile(at: url, intoPiece: piece) }
            }
        }
        // Panel dialogs, not system ones: a sheet is 620 wide over a 34% dim and
        // an alert has a band footer whose verb names the action (§7.15, §7.16).

    }

    // MARK: - The setlist, which is what the transport steps

    private var setlistPosition: (setlist: SetlistDoc, index: Int)? {
        guard let slug = state.currentSetlist, let current = state.selectedSlug,
              let setlist = state.manifest?.setlists?.first(where: { $0.slug == slug }),
              let index = setlist.arrangements.firstIndex(of: current) else { return nil }
        return (setlist, index)
    }

    private var setlistLabel: String? {
        guard let position = setlistPosition else { return nil }
        return "setlist · \(position.index + 1) of \(position.setlist.arrangements.count)"
    }

    private func stepSetlist(_ delta: Int) {
        guard let position = setlistPosition else { return }
        let next = position.index + delta
        guard position.setlist.arrangements.indices.contains(next) else { return }
        state.select(slug: position.setlist.arrangements[next])
    }

    // MARK: - The two menus the top bar opens

            // MARK: - Identity, counters

    private var scoreTitle: String {
        guard let score = state.selectedScore else { return "No arrangement" }
        // Never the slug. Scores imported before the engine learned to refuse
        // a file name as a title still carry one, and rewriting someone's
        // names underneath them is not the fix -- so the view says what it
        // does know instead (L18).
        let piece = state.manifest?.pieces?.first { $0.arrangements.contains(score.slug) }
        return ScoreTitle.display(title: score.title, name: score.name,
                                  slug: score.slug, pieceName: piece?.name,
                                  parts: (state.displayedVersion?.parts ?? []).map(\.name))
    }

    private var scoreSubtitle: String {
        guard let score = state.selectedScore else { return "" }
        let piece = state.manifest?.pieces?.first { $0.arrangements.contains(score.slug) }
        return [piece?.name, state.displayedVersionLabel]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var pageCounter: String {
        ScorePosition.pageLabel(visible: state.visiblePageIndices,
                                total: state.pdfDocument?.pageCount ?? 0)
    }

    /// The bar on screen, from the geometry the selection layer already builds.
    ///
    /// The visible RECT, not the visible page: reporting every measure on the
    /// page meant the readout said "bar 1" while the reader was zoomed into
    /// bar 30. Falls back to the whole page where no rect has been reported
    /// yet -- the first frame, and the remote-engine path, which builds no
    /// geometry at all and correctly shows nothing.
    private var barCounter: Int? {
        guard let geometry = state.geometry else { return nil }
        let pages: [(visible: CGRect, bars: [BarPosition.Bar])] =
            state.visiblePageIndices.compactMap { index in
                guard let page = geometry.page(index) else { return nil }
                let bars = BarPosition.bars(onPage: page)
                let rect = state.visibleBarRects[index]
                    ?? CGRect(origin: .zero, size: page.size)
                return (rect, bars)
            }
        return BarPosition.first(inPages: pages)
    }

    // The score view's dialogs are gone (NAV_MODAL_FREE_0.4.2 §2). Details
    // and Settings are pushed screens now, reached through the "…" screen; the
    // set-list pickers and the alerts belonged to the legacy overlay, which
    // went with it. Nothing floats over the score any more except the docked
    // chrome -- chat, ink bar, strip, transport -- which blocks nothing and
    // needs no dismissing.

    // MARK: - Canvas

    /// The score, inset so it stays centred in whatever gap the overlays leave.
    /// The inset animates; the page itself does not resize unless both overlays
    /// are open (§5).
    @ViewBuilder
    private var canvasLayer: some View {
        HStack(spacing: 0) {
            // reserve exactly the panels' widths, so what remains IS the canvas
            Group {
                if let score = state.selectedScore {
                    // No width cap. The spec pins the page at 520 (436 with both
                    // panels open), but those came from a 1180pt mockup; capping
                    // an iPad's 1032pt canvas to 544 left dead bands either side
                    // and made the scroll view itself too narrow, so zoom hit
                    // hard limits well inside the screen. The score gets the
                    // whole gap and ScorePagesView sizes the page from it.
                    scorePane(score)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity)
            Color.clear.frame(width: isCompact ? 0 : (chatOpen ? Theme.Metric.chatWidth : 0))
        }
        .animation(Theme.Motion.overlay(reduced: reduceMotion), value: chatOpen)
        // a finished lasso opens chat: the selection has to be visibly received,
        // not silently held
        .onChange(of: state.chatOpenRequest) { _, _ in
            withAnimation(Theme.Motion.overlay(reduced: reduceMotion)) { chatOpen = true }
        }
    }

    @ViewBuilder
    private func scorePane(_ score: ScoreDoc) -> some View {
        if let doc = state.pdfDocument, let vid = state.displayedVersionID {
            // ONE CANVAS, EVERY SIZE CLASS (IPHONE_0.6.14 §0, §10.4 step 1).
            //
            // Compact width used to get `ScoreZoomView`: 36 lines of PDFView
            // with `autoScales`. Everything the score view IS lived on the
            // other branch -- Pencil markup, the lasso, selection, the
            // playhead, the thumbnail rail -- and the phone had none of it,
            // with a zoom ceiling of 5 rather than the 12 a notehead needs.
            //
            // It is not that the phone had a worse canvas; it had a different
            // one, so every feature built on the real canvas simply did not
            // exist there and no test could tell. Nothing else in 0.6.14 is
            // testable until this branch goes.
            //
            // The engine is handed in rather than reached through AppState:
            // AppState publishes nothing when the play head moves, so a canvas
            // that read it that way would never follow. Same reason the ink
            // bar observes its controller directly.
            ScorePagesView(document: doc, annotationKey: "\(score.inkNamespace)/\(vid)",
                           canvasIdentity: "\(score.slug)/\(vid)",
                           mode: state.scoreMode, playback: state.playback)
        } else if score.versions.isEmpty {
            // An arrangement with no versions has no version to display, so
            // renderIfNeeded returns at its guard and nothing is ever in
            // flight. Saying so beats a spinner that can never finish.
            StateView(systemImage: "questionmark.square.dashed",
                      title: "Nothing to show",
                      message: "This arrangement has no versions — nothing was ever "
                             + "written to it. That usually means an import stopped "
                             + "part way. You can delete it and import the score again.",
                      actionTitle: "Delete this arrangement",
                      // and step back out: what is on screen no longer exists,
                      // and the undo bar lives in the library behind this
                      action: {
                          state.deleteScore(slug: score.slug)
                          onClose()
                      })
        } else if state.loadingPDF {
            StateView(systemImage: "music.note.list", title: "Engraving…",
                      message: "Verovio is setting the page.")
        } else if let err = state.lastError {
            // The build is ON the failure, not only in Settings. A screenshot of
            // this screen is how a reader reports it, and without the build
            // stamp nobody can tell which version they are looking at -- an
            // afternoon went into establishing that from timestamps alone.
            StateView(systemImage: "exclamationmark.triangle",
                      title: "Render failed", message: "The engine could not draw this version.",
                      mono: "\(err)\n\(Self.buildStamp)")
        } else {
            StateView(systemImage: "music.note", title: "Opening…")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !state.libraryLoaded {
            // Still looking. Nothing here is known yet -- not whether there are
            // scores, and not whether the engine is reachable -- so neither
            // message below can be told the truth, and both were shown for a
            // moment at every launch.
            StateView(systemImage: "music.note.list",
                      title: "Opening your library…",
                      message: "")
                .accessibilityIdentifier("library-loading")
        } else if !state.engineOK && !state.useLocalEngine {
            StateView(systemImage: "bolt.horizontal.circle",
                      title: "Engine unreachable",
                      message: "Check the URL in Settings and that the engine is running on your Mac.",
                      mono: state.engineURLString,
                      actionTitle: "Settings") { showSettings = true }
        } else {
            StateView(systemImage: "music.quarternote.3",
                      title: "No arrangement open",
                      message: "Open the library to pick an arrangement, or import a score.",
                      actionTitle: "Open library") {
            }
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var overlayLayer: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if chatOpen {
                    OverlayPanel(edge: .trailing,
                                 width: isCompact ? .infinity : Theme.Metric.chatWidth) {
                        chatPanel
                    }
                    .transition(panelTransition(.trailing))
                }
            }
            // the screen ignores the keyboard so the page keeps its size; the
            // panel with the field in it takes the inset back (#59)
            .padding(.bottom,
                     KeyboardInset.panelBottom(keyboard: keyboard.height,
                                               safeAreaBottom: geo.safeAreaInsets.bottom))
            .animation(Theme.Motion.overlay(reduced: reduceMotion), value: chatOpen)
            .animation(Theme.Motion.overlay(reduced: reduceMotion), value: keyboard.height)
        }
    }

    /// Reduce Motion swaps the slide for a cross-fade (§5, §9).
    private func panelTransition(_ edge: OverlayEdge) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .move(edge: edge == .leading ? .leading : .trailing)
    }

    @ViewBuilder
    private var chatPanel: some View {
        VStack(spacing: 0) {
            OverlayHeader(subject: {
                HStack(spacing: Theme.Metric.s6) {
                    if let slug = state.selectedScore?.slug,
                       let placement = state.placement(of: slug) {
                        NumeralBadge(number: placement.number, role: .numeralM)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(state.selectedScore?.name ?? "Chat")
                            .typeRole(.title)
                            .foregroundStyle(Theme.Ink.ink)
                            .lineLimit(1)
                        if let slug = state.selectedScore?.slug,
                           let placement = state.placement(of: slug) {
                            Text(placement.piece.name)
                                .typeRole(.meta)
                                .foregroundStyle(Theme.Ink.ink3)
                                .lineLimit(1)
                        }
                    }
                }
            }, trailing: {
                if let catalog = state.modelCatalog {
                    // The chat header's model Menu becomes a pushed screen
                    // (NAV_MODAL_FREE_0.4.2 §7.3): the last popover in the app.
                    Button { scoreScreen = .chatModel } label: {
                        Text(state.chatModel.isEmpty ? (catalog.default) : state.chatModel)
                            .typeRole(.data)
                            .foregroundStyle(Theme.Ink.ink2)
                            // one line at its natural width: with the title
                            // taking priority the chip started wrapping instead
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.vertical, Theme.Metric.s4)
                            .padding(.horizontal, Theme.Metric.s6)
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                                    .stroke(Theme.Line.line2, lineWidth: 1)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chat-model")
                    .accessibilityLabel("Chat model")
                }
            }, onDismiss: {
                withAnimation(Theme.Motion.overlay(reduced: reduceMotion)) { chatOpen = false }
            }, dismissLabel: "Close chat")
            ChatView()
        }
    }

    // The legacy library overlay lived here: piece and set-list sections,
    // drag-to-file rows and three context menus. It is gone (0.4.1 §1).
    // Browsing is the Library tab, filing is Edit mode's Move-to-piece,
    // and reordering is the arrangement sheet -- so nothing was left that
    // only the overlay could do. The score screen now has exactly one
    // chrome: top bar, thumbnail strip, transport.

    // MARK: - Pill

    /// Wrapped in a child view so the annotation controller can be observed:
    /// the pill shows markup state and the live ink colour.

    @ViewBuilder
    private var versionMenuItems: some View {
        if let score = state.selectedScore {
            ForEach(state.versionGroups(for: score)) { group in
                Button {
                    state.pinnedVersion = (group.face.id == score.latest) ? nil : group.face.id
                    Task { await state.renderIfNeeded() }
                } label: {
                    if group.face.id == state.displayedVersionID {
                        Label("\(group.face.name) · \(shortTitle(group.title))",
                              systemImage: "checkmark")
                    } else {
                        Text("\(group.face.name) · \(shortTitle(group.title))")
                    }
                }
            }
        }
    }

    // `optionsMenuItems` lived here: the "…" popover's rows, including the
    // last stock iOS Toggle in the app. The popover became a pushed screen in
    // the modal-free revision and nothing has rendered these since -- so this
    // is dead code that a control audit keeps finding (L33).

    private func shortTitle(_ title: String) -> String {
        title.count > 40 ? title.prefix(40).trimmingCharacters(in: .whitespaces) + "…" : title
    }

    // MARK: - Navigation

    private func openScore(_ slug: String, version: String? = nil) {
        state.select(slug: slug, version: version)
        // one pane at a time on iPhone: opening a score reveals it
        if isCompact {
        }
    }
}
/// A row inside a piece is a drop target: what lands on it takes its place in
/// the running order and everything below shifts down, which is the #N
/// renumbering the user sees. A row in Unfiled has no order to join, so it
/// accepts nothing.
private extension View {
}

/// Observes the shared annotation controller so the pill reflects markup state
/// and carries the live ink colour.
// The pill is gone from the score view: the top bar carries its duties
// (NAVIGATION_SYSTEM.md §8), and with the legacy overlay removed there is
// nothing left for its library button to open.


/// The page and bar counters, wired to the transport's own clock.
///
/// It OBSERVES the engine, and that is the whole reason it exists rather than
/// `PositionCounters` being called with a boolean: the bar chip appears with
/// the play head and goes when it stops, and `AppState` publishes nothing when
/// the engine's state changes. Read through `AppState` the chip would appear
/// only when something else happened to redraw the score screen -- the same
/// fault the transport row and the ink bar each had to be fixed for.
///
/// `BarPosition.counter` is the rule, and it is tested there: bar while
/// playing, nothing while reading. The page counter is not playback's business
/// and passes straight through.
private struct LiveCounters: View {
    @ObservedObject var playback: PlaybackEngine
    let pages: String?
    let bar: Int?
    /// Test-only, under `-geometryProbe`: the per-page system count.
    let probe: String?

    var body: some View {
        PositionCounters(pages: pages,
                         bar: BarPosition.counter(bar: bar,
                                                  isPlaying: playback.isPlaying),
                         probe: probe)
    }
}
