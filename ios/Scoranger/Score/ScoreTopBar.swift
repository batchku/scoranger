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
    @ObservedObject var annotation: AnnotationController
    let number: Int?
    let title: String
    let subtitle: String
    @Binding var mode: ScoreMode
    @Binding var titleMenuOpen: Bool
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
            barButton("xmark", label: "Close score", identifier: "score-close",
                      action: onClose)
            Spacer(minLength: Theme.Metric.s8)
            titleBlock
            Spacer(minLength: Theme.Metric.s8)
            barButton("pencil", label: "Edit", identifier: "score-edit",
                      active: mode == .edit) {
                mode = (mode == .edit) ? .read : .edit
                annotation.isOn = (mode == .edit)
            }
            barButton("bubble.left", label: "Ask", identifier: "score-ask",
                      active: chatOpen, action: onAsk)
            barButton("book.pages", label: "Two pages side by side",
                      identifier: "score-spread", active: state.twoPageSpread) {
                state.twoPageSpread.toggle()
            }
            barButton("ellipsis", label: "More", identifier: "score-more",
                      active: moreOpen) { moreOpen.toggle(); titleMenuOpen = false }
        }
        .padding(.horizontal, Theme.Metric.s12)
        .frame(height: Theme.Metric.scoreTopBar)
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
        }
        .padding(.horizontal, Theme.Metric.s12)
        .frame(height: Theme.Metric.scoreTopBarPerformance)
        .background(Theme.Surface.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Line.line).frame(height: 1)
        }
        .accessibilityIdentifier("performance-bar")
    }

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
                        // the mode, stated: §6 only works if it is visible
                        Text(mode.pencilMeaning).typeRole(.data)
                            .foregroundStyle(Theme.Accent.clayStrong)
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
    let pages: String
    let bar: Int?

    var body: some View {
        HStack(spacing: Theme.Metric.s6) {
            chip(pages, identifier: "counter-pages")
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
