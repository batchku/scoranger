import SwiftUI

// MARK: - Band header (§7.3)

/// The silkscreen label: a full-width `band` strip with hard rules top and
/// bottom and a tracked-out caps label. Used for sidebar sections, sheet
/// sections and card headers, with an optional trailing action.
struct BandHeader<Trailing: View>: View {
    let title: String
    /// An index letter is a heading, not a label: at the generic 10pt `.label`
    /// role the "S" over the S's was a speck (L13). The spec asks for 13pt
    /// Space Grotesk 700 there, which is `.titleS`.
    var role: Theme.Role = .label
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.inPanel) private var inPanel

    var body: some View {
        HStack(spacing: Theme.Metric.s8) {
            // Sentence case (§2 rule 2): the tracked caps silkscreen is retired.
            // A section label is ink3; an index LETTER (passed in as .titleS)
            // keeps clayStrong, which §1 reserves for the alphabet.
            Text(title)
                .typeRole(role)
                .foregroundStyle(role == .label ? Theme.Ink.ink3 : Theme.Accent.clayStrong)
            Spacer(minLength: 0)
            trailing()
        }
        // Inside the panel a header is a block's label (§7.2): sentence case
        // on the panel's own ground, the dashed rule above separating blocks
        // [C13]. On a page it is the band it was.
        .padding(.horizontal, inPanel ? Theme.Metric.panelSide : Theme.Metric.panelPadding)
        .padding(.top, inPanel ? Theme.Metric.s12 : 5)
        .padding(.bottom, inPanel ? Theme.Metric.s6 : 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(inPanel ? Color.clear : Theme.Surface.band)
        // ONE rule, above [C13]: the block after a row takes the row's rule,
        // so a header never draws a second line under itself.
        .overlay(alignment: .top) { Theme.Rule() }
    }
}

extension BandHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

// MARK: - Numeral (§7.5)

/// `#N`, the app's identity element. Space Grotesk 700, clay, tabular, with a
/// reserved width so #1 through #99 stay left-aligned down a column.
struct NumeralBadge: View {
    let number: Int
    var role: Theme.Role = .numeralL

    /// The stamp (§7.4): the numeral inside a clay ring. 56/3/22 on a head,
    /// 40/2.5/15 in a row, 30/2/12 in a version list -- ring diameter, ring
    /// weight, type size, keyed by the role the caller already passes.
    private var ring: (diameter: CGFloat, weight: CGFloat) {
        switch role {
        case .numeralXL: return (56, 3)
        case .numeralM:  return (30, 2)
        default:         return (40, Theme.Metric.stampRing)
        }
    }

    var body: some View {
        Text("#\(number)")
            .typeRole(role)
            .monospacedDigit()
            .foregroundStyle(Theme.Accent.clay)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            // 1pt left of the ring's centre, for the hash (§3 Centring).
            .offset(x: -1)
            .frame(width: ring.diameter, height: ring.diameter)
            .overlay {
                Circle().strokeBorder(Theme.Accent.clay, lineWidth: ring.weight)
            }
            .accessibilityLabel("Arrangement number \(number)")
    }
}

// MARK: - LED (§7.14)

/// A drawn circle with a halo, never a symbol, and never the only carrier of
/// its meaning: it sits beside a mono word.
/// A status dot. Just the dot.
///
/// It used to print a word of its own -- "on-device" when lit, "unreachable"
/// when not -- and that was wrong twice over. On the library's engine chip the
/// caller printed the mode too, so it read "on-device on-device"; and in
/// Settings, where it is used bare, it said "on-device" while the app was
/// talking to a remote engine, because the word was describing REACHABILITY
/// and being read as the mode.
///
/// One of the two had to own the word, and it is the caller: only the caller
/// knows whether the engine it is lighting is the on-device one or a remote
/// one. The dot says reachable or not, in colour and to VoiceOver.
struct LED: View {
    let isOn: Bool

    var body: some View {
        Circle()
            .fill(colour)
            .frame(width: 9, height: 9)
            .overlay {
                Circle().stroke(colour.opacity(0.22), lineWidth: 3)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isOn ? "Engine connected" : "Engine unreachable")
    }

    private var colour: Color { isOn ? Theme.Status.ok : Theme.Status.danger }
}

/// Content revealed in place: the sort and filter options, and anything else
/// that expands where it was asked for rather than floating over the screen.
///
/// It is a CONTAINER because the alternative is what happened -- the library's
/// sort options were a bare row of chips on the screen's own ground, so a
/// revealed list did not read as revealed, and every screen that reveals
/// something would have invented its own version of this.
///
/// Well fill, ruled top and bottom: the same language as a band, one step
/// quieter, so it reads as belonging to the control that opened it.
struct RevealBand<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Metric.s12)
            .padding(.vertical, Theme.Metric.s8)
            .background(Theme.Surface.well)
            .overlay(alignment: .top) { hairline }
            .overlay(alignment: .bottom) { hairline }
    }

    private var hairline: some View {
        Theme.Rule()
    }
}

/// A small bordered chip for a piece of STATE, next to the text it qualifies.
///
/// It exists because a state set as bare text runs into whatever is beside it:
/// "Pencil: select" sat against the version with nothing between them and read
/// as "… · v003 Pencil: select", one sentence made of two facts.
struct MiniChip: View {
    let text: String
    var tint: Color = Theme.Accent.clayStrong

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Metric.s6)
            .padding(.vertical, 2)
            .background(Theme.Surface.panel)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Buttons (§7.11)

/// 13pt/600 label, 2pt radius, hard border. `primary` and `destructive` carry a
/// fill and a white label; the default sits on `panel`.
struct PanelButton: View {
    enum Kind { case normal, primary, destructive }

    let title: String
    var kind: Kind = .normal
    /// Set ON the button rather than on the wrapper. An identifier applied to
    /// a composite view from outside did not reach the button inside it: the
    /// empty library's action was on screen and unfindable.
    var identifier: String?
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .typeRole(.control)
                .foregroundStyle(labelColour)
                .padding(.vertical, Theme.Metric.s8)
                .padding(.horizontal, Theme.Metric.s12)
                .frame(minHeight: 34)
                .background(fill)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(Color.clear, lineWidth: 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityIdentifier(identifier ?? "")
    }

    private var fill: Color {
        switch kind {
        case .normal:      return Theme.Surface.panel
        case .primary:     return Theme.Accent.clayPress
        case .destructive: return Theme.Status.danger
        }
    }

    private var labelColour: Color {
        kind == .normal ? Theme.Ink.ink : .white
    }
}

/// 34pt square icon button with the same border language. Always given a 44pt
/// hit area even though it draws smaller (§3).
struct PanelIconButton: View {
    let systemName: String
    let label: String
    var tint: Color = Theme.Ink.ink2
    var bordered = true
    var size: CGFloat = 34
    /// The glyph inside the square. Separate from `size`, or a bigger button
    /// is only a bigger tap target drawn around the same small icon.
    var glyphSize: CGFloat = 13
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: glyphSize, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Theme.Surface.panel.opacity(bordered ? 1 : 0))
                .overlay {
                    if bordered {
                        RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                            .stroke(Color.clear, lineWidth: 0)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
                .frame(width: Theme.Metric.hitTarget, height: Theme.Metric.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Row (§7.4)

/// Selection is a `clayTint` fill *plus* an inset clay outline: on a warm
/// ground the fill alone is too quiet (§1 rule 2).
struct RowSelectionBackground: View {
    let isSelected: Bool

    var body: some View {
        if isSelected {
            Theme.Accent.clayTint
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(Theme.Accent.clay, lineWidth: 1)
                        .padding(1)
                }
        } else {
            Color.clear
        }
    }
}

// MARK: - Overlay panel (§7.2)

enum OverlayEdge { case leading, trailing }

/// A full-height opaque panel that slides over the score, with a hard edge on
/// the score side. The score is the ground; these are the things above it.
struct OverlayPanel<Content: View>: View {
    let edge: OverlayEdge
    let width: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        // A MAXIMUM, not a width (§6.1). At compact there is no room beside
        // the score for a 460pt panel, so a fixed width draws a panel wider
        // than the phone and its rows hang 13.7pt off each edge -- measured on
        // an iPhone 17 Pro, where the Options rows came out 429pt in a 402pt
        // window. The rule the surface obeys is: at compact width nothing has
        // a fixed width; it either fills the width or it becomes a screen.
        content()
            .frame(maxWidth: width)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.Surface.panel)
            .overlay(alignment: edge == .leading ? .trailing : .leading) {
                Theme.Rule(vertical: true)
            }
            .modifier(PanelShadow())
    }
}

private struct PanelShadow: ViewModifier {
    func body(content: Content) -> some View {
        Theme.Elevation.panel(content)
    }
}

/// Header line inside an overlay: subject on the left, state on the right, and a
/// bordered dismiss button at the far end.
struct OverlayHeader<Subject: View, Trailing: View>: View {
    @ViewBuilder var subject: () -> Subject
    @ViewBuilder var trailing: () -> Trailing
    let onDismiss: () -> Void
    let dismissLabel: String

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Metric.s8) {
            // The subject wins the space. Without this the model chip took
            // what it wanted and the chat's own title truncated to
            // "Sous le ciel quart…" with room to spare beside it (L30).
            subject()
                .layoutPriority(1)
            Spacer(minLength: Theme.Metric.s8)
            trailing()
                .layoutPriority(0)
            PanelIconButton(systemName: "xmark", label: dismissLabel,
                            size: 30, action: onDismiss)
        }
        .padding(.horizontal, Theme.Metric.panelPadding)
        .padding(.vertical, Theme.Metric.s8)
        .background(Theme.Surface.panel)
        .overlay(alignment: .bottom) {
            Theme.Rule()
        }
    }
}

// MARK: - State view (§7.17)

/// Centred glyph, title, a body no wider than it needs, and at most one button.
/// Failure states name the cause in mono and the fix in prose.
struct StateView: View {
    let systemImage: String
    let title: String
    /// Named `message`, not `body`: a stored property called body collides with
    /// the View requirement.
    var message: String?
    var mono: String?
    var actionTitle: String?
    /// An empty state's action is the ONE thing to do about it, so it is the
    /// specced primary rather than another bordered button (L12 nit).
    var actionKind: PanelButton.Kind = .normal
    /// Applied to the TITLE, never to the whole state.
    ///
    /// An identifier on a composite view collapses it into one accessibility
    /// element and swallows what is inside: with `library-empty` on the state
    /// itself, the state was findable and its Import button was not there at
    /// all. This is the same trap the navigation work hit five times; putting
    /// the identifier on a leaf is the answer.
    var identifier: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Metric.s12) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.Ink.ink3)
            Text(title)
                .typeRole(.title)
                .foregroundStyle(Theme.Ink.ink)
                .accessibilityIdentifier(identifier ?? "")
            if let mono {
                Text(mono)
                    .typeRole(.data)
                    .foregroundStyle(Theme.Ink.ink2)
                    .padding(.vertical, Theme.Metric.s4)
                    .padding(.horizontal, Theme.Metric.s8)
                    .background(Theme.Surface.well)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
            }
            if let message {
                Text(message)
                    .typeRole(.body)
                    .foregroundStyle(Theme.Ink.ink2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            if let actionTitle, let action {
                PanelButton(title: actionTitle, kind: actionKind,
                            identifier: "state-action", action: action)
                    .padding(.top, Theme.Metric.s4)
            }
        }
        .padding(Theme.Metric.s24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
