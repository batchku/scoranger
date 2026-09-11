import SwiftUI

// The right page (design/DESIGN_SYSTEM.md §7.2).
//
// One panel, 380 wide, beside the page it belongs to. It shows what the
// tapped thing opened -- a tool-row button, a row's action, the score bar --
// headed by its name, and closes with Done or with the row's ✕ [C2]. It is
// `panel`, never white [C1]. What used to push a screen, expand a band under
// a row, or float as a window opens here instead, at the row's height, so the
// finger moves along the row and never off it (§3 Travel).
//
// On a phone the same content is pushed as a page with ‹ in its header (Ph3).

/// What the panel is showing, as a stack: Sort opens one state; a row's
/// Arrangement opens one and its Versions pushes another, with ‹ back to the
/// first; Done empties the stack. `rest` is what the panel shows when nothing
/// is open on a screen that has a panel at rest ("This piece", "This set
/// list"); Done gives it back (S2).
final class PanelModel: ObservableObject {
    @Published private(set) var stack: [Route] = []
    @Published var rest: Route?

    var top: Route? { stack.last ?? rest }
    var isOpen: Bool { top != nil }
    var canGoBack: Bool { stack.count > 1 }

    /// Open from a tool row or a row: replaces whatever was open.
    func open(_ route: Route) {
        withAnimation(Theme.Motion.overlay(reduced: false)) { stack = [route] }
    }
    /// Open beside the current state, with ‹ back to it.
    func push(_ route: Route) {
        withAnimation(Theme.Motion.overlay(reduced: false)) { stack.append(route) }
    }
    /// The same button pressed again closes what it opened.
    func toggle(_ route: Route) {
        if stack.last == route { done() } else { open(route) }
    }
    func back() {
        guard !stack.isEmpty else { return }
        withAnimation(Theme.Motion.overlay(reduced: false)) { stack.removeLast() }
    }
    func done() {
        withAnimation(Theme.Motion.overlay(reduced: false)) { stack = [] }
    }
    /// Whether this route is what the panel is showing right now -- the
    /// button that opened it is lit while it is (§7.5).
    func isShowing(_ route: Route) -> Bool { stack.last == route }
    /// A screen's panel at rest, set on appear and cleared on disappear.
    func setRest(_ route: Route?) {
        if rest != route { rest = route }
    }
    func clearRest(_ route: Route) {
        if rest == route { rest = nil }
    }
}

// MARK: - Environment

private struct InPanelKey: EnvironmentKey { static let defaultValue = false }
private struct PanelTitleKey: EnvironmentKey { static let defaultValue: String? = nil }
private struct PanelBackKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }
private struct PanelDoneKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }

extension EnvironmentValues {
    /// True inside the panel: `Screen` draws the panel's header rather than a
    /// nav bar, and rows draw as panel items.
    var inPanel: Bool {
        get { self[InPanelKey.self] } set { self[InPanelKey.self] = newValue }
    }
    /// The noun the panel is headed by when the screen inside has no title
    /// of its own ("Arrangement", "Set list").
    var panelTitle: String? {
        get { self[PanelTitleKey.self] } set { self[PanelTitleKey.self] = newValue }
    }
    /// ‹, when the panel opened from another panel state; nil at the root.
    var panelBack: (() -> Void)? {
        get { self[PanelBackKey.self] } set { self[PanelBackKey.self] = newValue }
    }
    /// Done.
    var panelDone: (() -> Void)? {
        get { self[PanelDoneKey.self] } set { self[PanelDoneKey.self] = newValue }
    }
}

// MARK: - The panel's own chrome

/// The header of a panel state: ‹ when there is somewhere back to go, the
/// title (20pt), an optional mono count or subtitle, a trailing control, and
/// Done at the trailing edge (§7.2).
struct PanelHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var count: Int?
    /// What VoiceOver calls Done; "Close chat" where a test or a reader
    /// already knows it by that name.
    var doneLabel: String = "Done"
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.panelBack) private var back
    @Environment(\.panelDone) private var done

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Metric.s8) {
            if let back {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Ink.ink2)
                        .frame(width: 32, height: 32)
                        .background(Theme.Surface.well)
                        .clipShape(Circle())
                        .frame(width: Theme.Metric.hitTarget, height: Theme.Metric.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("panel-back")
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Metric.s6) {
                    Text(title).typeRole(.panelTitle).foregroundStyle(Theme.Ink.ink)
                        .lineLimit(1)
                        .accessibilityIdentifier("panel-title")
                    if let count {
                        Text("\(count)").typeRole(.data).foregroundStyle(Theme.Ink.ink3)
                            .accessibilityIdentifier("panel-count")
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: Theme.Metric.s8)
            trailing()
            if let done {
                Button(action: done) {
                    Text("Done").typeRole(.control)
                        .foregroundStyle(Theme.Ink.ink)
                        .padding(.horizontal, Theme.Metric.s16)
                        .frame(height: 36)
                        .background(Theme.Surface.well)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(doneLabel)
                .accessibilityIdentifier("panel-done")
            }
        }
        .padding(.horizontal, Theme.Metric.panelSide)
        .padding(.top, Theme.Metric.s16)
        .padding(.bottom, Theme.Metric.s12)
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, count: Int? = nil, doneLabel: String = "Done") {
        self.init(title: title, subtitle: subtitle, count: count, doneLabel: doneLabel) { EmptyView() }
    }
}

/// The page shape the panel and the list page share: `panel` fill, `rPage`
/// top corners, running off the bottom of the table (§7.1).
struct PageShape: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.Surface.panel)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: Theme.Metric.rPage, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: Theme.Metric.rPage))
    }
}

extension View {
    func pageShape() -> some View { modifier(PageShape()) }
}

/// The list page beside its panel (§7.1, §7.2). Regular width: an HStack,
/// the page taking what the panel leaves, 10 between them, 16 from the
/// table's edges. Compact width: the panel covers the page as a pushed page
/// with ‹ in its header (Ph3).
struct PanelHost<Page: View, PanelContent: View>: View {
    @ObservedObject var panel: PanelModel
    /// True while something covers the table (the score): the panel is not
    /// drawn at all, so nothing of it reaches the accessibility tree from
    /// under the cover -- a hidden page's Done was being found and tapped.
    var suspended = false
    @ViewBuilder var page: () -> Page
    @ViewBuilder var content: (Route) -> PanelContent
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        GeometryReader { geo in
            let compact = isCompact || geo.size.width < Theme.Metric.panelWidth * 2
            ZStack(alignment: .trailing) {
                HStack(spacing: Theme.Metric.pagePanelGap) {
                    page()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !compact, !suspended, let top = panel.top {
                        panelPage(top, width: Theme.Metric.panelWidth)
                            .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                    }
                }
                if compact, !suspended, let top = panel.top {
                    panelPage(top, width: nil)
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                }
            }
            .animation(Theme.Motion.overlay(reduced: reduceMotion), value: panel.top)
        }
    }

    private func panelPage(_ route: Route, width: CGFloat?) -> some View {
        content(route)
            .environment(\.inPanel, true)
            .environment(\.panelTitle, route.panelTitle)
            .environment(\.panelBack, panel.canGoBack ? { panel.back() } : nil)
            .environment(\.panelDone, { panel.done() })
            .frame(width: width)
            .frame(maxHeight: .infinity, alignment: .top)
            .pageShape()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("panel")
            .id(route)
    }
}

// MARK: - Panel content pieces (§7.2)

/// A block's label inside the panel: sentence case, `label` in ink3, with the
/// dashed rule above it that separates blocks [C13].
struct PanelLabel: View {
    let text: String
    var ruled = true
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if ruled { Theme.Rule().padding(.bottom, Theme.Metric.s12) }
            Text(text).typeRole(.label).foregroundStyle(Theme.Ink.ink3)
                .padding(.horizontal, Theme.Metric.panelSide)
                .padding(.bottom, Theme.Metric.s6)
        }
        .padding(.top, Theme.Metric.s4)
    }
}

/// A row of 44pt buttons across the panel (§7.2 `btns`).
struct PanelButtons<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(spacing: Theme.Metric.s8) { content() }
            .padding(.horizontal, Theme.Metric.panelSide)
            .padding(.vertical, Theme.Metric.s8)
    }
}

/// A key/value row: 48pt, the key in `row`, the value in mono at the right,
/// a dashed rule under (§7.2).
struct PanelKeyValue: View {
    let key: String
    let value: String
    var identifier: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Metric.s8) {
                Text(key).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                Spacer(minLength: Theme.Metric.s8)
                Text(value).typeRole(.data).foregroundStyle(Theme.Ink.ink2)
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.Metric.panelSide)
            .frame(minHeight: 48)
            Theme.Rule()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier ?? "")
    }
}
