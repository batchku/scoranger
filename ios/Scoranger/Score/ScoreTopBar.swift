import SwiftUI

/// The score view's top bar (NAVIGATION_SYSTEM.md §4.5, 12.9–12.11).
///
/// This is what the pill becomes. Its pieces go to their own places: library →
/// X and the tabs, `#N` → the title block, the version chip → the title
/// dropdown, gear → `…`, pencil → Edit, chat → Ask (§8).
///
/// The bar also STATES THE MODE, which is not decoration: the whole of §6 rests
/// on the Pencil meaning exactly one thing at a time, and a mode you cannot see
/// is a mode you cannot trust.
struct ScoreTopBar: View {
    @EnvironmentObject var state: AppState
    @Environment(\.horizontalSizeClass) private var hSize
    @ObservedObject var annotation: AnnotationController
    let number: Int?
    let title: String
    let subtitle: String
    @Binding var mode: ScoreMode
    @Binding var titleMenuOpen: Bool
    /// Measured, so the bar can say what it can seat (#60).
    @State private var barWidth: CGFloat = 0
    @Binding var moreOpen: Bool
    var chatOpen: Bool
    var onClose: () -> Void
    var onAsk: () -> Void

    var body: some View {
        if mode == .performance {
            performanceBar
        } else {
            fullBar
        }
    }

    // MARK: - Reading and editing

    private var fullBar: some View {
        HStack(spacing: Theme.Metric.s8) {
            // FIXED, and first. Nothing added to this bar may push the way out
            // of the score off it -- on a phone that left no way back at all
            // (#60). The priority and the fixed size are belt and braces over
            // ScoreBarLayout's own arithmetic.
            barButton("xmark", label: "Close score", identifier: "score-close",
                      action: onClose)
                .fixedSize()
                .layoutPriority(2)
            Spacer(minLength: Theme.Metric.s8)
            titleBlock
            if fit.showsVersions { versionsTrigger }
            Spacer(minLength: Theme.Metric.s8)
            barButton("pencil", label: "Edit", identifier: "score-edit",
                      active: mode == .edit) {
                mode = (mode == .edit) ? .read : .edit
                annotation.isOn = (mode == .edit)
            }
            barButton("bubble.left", label: "Ask", identifier: "score-ask",
                      active: chatOpen, action: onAsk)
            layoutControl
            barButton("ellipsis", label: "More", identifier: "score-more",
                      active: moreOpen) { moreOpen.toggle(); titleMenuOpen = false }
        }
        .padding(.horizontal, Theme.Metric.s12)
        .frame(height: Theme.Metric.scoreTopBar)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { barWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, new in barWidth = new }
            }
        }
        .background(Theme.Surface.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Line.line).frame(height: 1)
        }
    }

    /// Performance mode collapses the bar to a strip (§4.5, N10): the score
    /// gets the screen, and the only things left are the way out and a
    /// statement of what mode you are in.
    private var performanceBar: some View {
        HStack(spacing: Theme.Metric.s8) {
            barButton("xmark", label: "Leave performance mode",
                      identifier: "score-close") { mode = .read }
            Text("PERFORMANCE").typeRole(.label)
                .foregroundStyle(Theme.Accent.clayStrong)
            Text(ScoreMode.performance.pencilMeaning).typeRole(.meta)
                .foregroundStyle(Theme.Ink.ink3)
            Spacer()
            // Performance mode strips the bar to the way out and the mode, but
            // switching version is what a player does mid-rehearsal and there
            // was NO route to it here at all.
            versionsTrigger
        }
        .padding(.horizontal, Theme.Metric.s12)
        .frame(height: Theme.Metric.scoreTopBarPerformance)
        .background(Theme.Surface.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Line.line).frame(height: 1)
        }
        // .contain, or the identifier on this stack takes its children with it:
        // the bar became one element and the version control inside it did not
        // exist to a tap. The title band carries the same note for the same
        // reason.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("performance-bar")
    }

    /// Page / spread / continuous, as one segmented control.
    ///
    /// It REPLACES the two-page-spread button: they are three answers to one
    /// question, and as separate toggles they could both be on -- a state with
    /// no meaning (see `ScoreLayout`). Absent in performance mode, which is
    /// the bar that has nothing but the way out.
    ///
    /// The spec asked for ONE `.adjustable` element here. It is three buttons
    /// instead, deliberately: `.accessibilityElement(children: .ignore)` on a
    /// container collapses its children, and a collapsed cell cannot be tapped
    /// -- by a UI test or by anyone using Switch Control or Full Keyboard
    /// Access. This codebase has been caught by exactly that three times (the
    /// title block, the title band, and the performance bar earlier today).
    /// Three labelled buttons read fine in VoiceOver and can actually be
    /// pressed.
    private var layoutControl: some View {
        HStack(spacing: 0) {
            ForEach(Array(ScoreLayout.available(
                            isCompact: isCompact || fit.layoutCells <= 2).enumerated()),
                    id: \.element) { index, option in
                if index > 0 {
                    Rectangle().fill(Theme.Line.line).frame(width: 1, height: 34)
                }
                layoutCell(option)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                .stroke(Theme.Line.line2, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("score-layout")
    }

    /// Continuous re-engraves the score with no system breaks, which only
    /// Verovio can do. A scan has no engraving, so the cell is shown disabled
    /// rather than removed -- a control that appears and disappears with the
    /// arrangement is harder to trust than one that is plainly unavailable.
    private func isAvailable(_ option: ScoreLayout) -> Bool {
        option != .continuous || state.displayedArtifact == .notation
    }

    private func layoutCell(_ option: ScoreLayout) -> some View {
        let active = state.layout == option
        let available = isAvailable(option)
        return Button {
            guard state.layout != option else { return }
            state.layout = option
            // continuous has no pages to be on, and coming back from it the
            // reader should be at the top of the score rather than at an index
            // the strip never had
            state.pageIndex = 0
            Task { await state.renderIfNeeded() }
        } label: {
            Image(systemName: option.glyph)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(!available ? Theme.Ink.ink3
                                 : (active ? Theme.Accent.clayStrong : Theme.Ink.ink2))
                .frame(width: 40, height: 34)
                .background(active ? Theme.Accent.clayTint : Theme.Surface.panel)
                .overlay {
                    if active {
                        RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                            .stroke(Theme.Accent.clay, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .accessibilityLabel(option.label)
        .accessibilityHint(available ? "" : ScoreArtifact.whyNotEditable())
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("layout-\(option.rawValue)")
    }

    /// "N versions" -- the control that opens the version dropdown.
    ///
    /// A SIBLING of the title button, never a child of it: `titleBlock`
    /// collapses its children into one accessibility element, so a button
    /// drawn inside it is findable and untappable (the same trap the title
    /// block's own comment records). It opens the same band the title does,
    /// because the band IS the dropdown -- one surface, two ways in.
    @ViewBuilder
    private var versionsTrigger: some View {
        if let label = ScoreTitle.versionsLabel(count: versionCount) {
            Button {
                titleMenuOpen.toggle()
                moreOpen = false
            } label: {
                HStack(spacing: 4) {
                    Text(label).typeRole(.data)
                        .foregroundStyle(titleMenuOpen ? Theme.Accent.clayStrong
                                                       : Theme.Ink.ink3)
                        .lineLimit(1).fixedSize()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(titleMenuOpen ? Theme.Accent.clayStrong
                                                       : Theme.Ink.ink3)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(titleMenuOpen ? Theme.Surface.well : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityHint("Switch to another version")
            .accessibilityAddTraits(titleMenuOpen ? [.isButton, .isSelected] : [.isButton])
            .accessibilityIdentifier("score-versions")
        }
    }

    private var versionCount: Int { state.selectedScore?.versions.count ?? 0 }

    /// A phone is offered page and continuous only: a spread across 390pt is
    /// two thumbnails, and this bar has no room for a third cell there.
    private var isCompact: Bool { hSize == .compact }

    /// What this bar can seat. See `ScoreBarLayout` for the order things yield
    /// in -- ✕ never does (#60).
    private var fit: ScoreBarLayout.Fit { ScoreBarLayout.fit(barWidth: barWidth) }

    private var titleBlock: some View {
        Button {
            titleMenuOpen.toggle()
            moreOpen = false
        } label: {
            HStack(spacing: Theme.Metric.s8) {
                if let number { NumeralBadge(number: number, role: .numeralM) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).typeRole(.titleS).foregroundStyle(Theme.Ink.ink)
                        .lineLimit(1)
                    HStack(spacing: Theme.Metric.s6) {
                        Text(subtitle).typeRole(.data).foregroundStyle(Theme.Ink.ink3)
                            .lineLimit(1)
                        // The mode, stated: §6 only works if it is visible --
                        // but as bare text it ran straight into the version
                        // beside it and read as "… · v003 Pencil: select".
                        // The chip's own border tells them apart. A "·" as
                        // well left a dangling separator between the version
                        // and a box -- punctuation joining a sentence to a
                        // thing that is not one (#41).
                        if fit.showsModeChip {
                            MiniChip(text: mode.pencilMeaning)
                                .accessibilityIdentifier("pencil-mode")
                        }
                    }
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Ink.ink3)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(titleMenuOpen ? Theme.Surface.well : Color.clear)
            .overlay {
                if titleMenuOpen {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(Theme.Line.line2, lineWidth: 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // one element, not a stack. A Button whose label is a stack is reported
        // as a CONTAINER: it is findable, and a tap on it reaches the container
        // rather than the button -- so the title band never opened. VoiceOver
        // reads the parts separately for the same reason.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityHint("Switch arrangement or version")
        .accessibilityAddTraits(titleMenuOpen ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("score-title")
    }

    private func barButton(_ glyph: String, label: String, identifier: String,
                           active: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(active ? Theme.Accent.clayStrong : Theme.Ink.ink2)
                .frame(width: 34, height: 34)
                .background(active ? Theme.Accent.clayTint : Theme.Surface.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(active ? Theme.Accent.clay : Theme.Line.line2, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

/// Page and bar counters (12.11).
///
/// §7 expected `bar N` to wait on a parallel session for the geometry layer. It
/// does not: `ScoreGeometry` is already here -- selection is built on it -- and
/// every element it holds carries the measure it belongs to. The bar showing is
/// the lowest-numbered one actually on screen.
struct PositionCounters: View {
    /// Nil in continuous mode, which has no pages to count.
    let pages: String?
    let bar: Int?

    var body: some View {
        HStack(spacing: Theme.Metric.s6) {
            if let pages { chip(pages, identifier: "counter-pages") }
            // one place decides how a bar reads, and it is unit-tested
            if let label = BarPosition.label(for: bar) {
                chip(label, identifier: "counter-bar")
            }
        }
    }

    private func chip(_ text: String, identifier: String) -> some View {
        Text(text)
            .typeRole(.data)
            .foregroundStyle(Theme.Ink.ink2)
            .padding(.horizontal, Theme.Metric.s8)
            .padding(.vertical, 4)
            .background(Theme.Surface.panel)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                    .stroke(Theme.Line.line2, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
            .accessibilityIdentifier(identifier)
    }
}
