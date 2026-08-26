import SwiftUI

/// The bottom tab bar (NAVIGATION_SYSTEM.md §5, 12.1).
///
/// On iPad this is deliberate rather than accidental (§9.4): iPadOS prefers a
/// top bar or a sidebar, and we are putting it at the bottom because the iPad
/// is on a music stand and the reach that matters is one thumb at the near edge.
///
/// The active item reuses the pill's own language -- `clayTint` behind a
/// `clay` mark -- which is the through-line the redesign keeps from the chrome
/// it replaces (§8).
struct TabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                item(tab)
            }
        }
        .frame(height: Theme.Metric.tabBarHeight)
        .background(Theme.Surface.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Line.line).frame(height: 1)
        }
    }

    private func item(_ tab: AppTab) -> some View {
        Button {
            guard tab.isAvailable else { return }
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.glyph)
                    .font(.system(size: 19, weight: .regular))
                    .frame(height: 22)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 3)
                    .background {
                        if selection == tab && tab.isAvailable {
                            RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                                .fill(Theme.Accent.clayTint)
                        }
                    }
                Text(tab.title.uppercased())
                    .typeRole(.meta)
            }
            .foregroundStyle(colour(for: tab))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // a disabled tab is still announced, so its presence is a promise
        // rather than a dead pixel
        .disabled(!tab.isAvailable)
        .opacity(tab.isAvailable ? 1 : 0.38)
        .accessibilityIdentifier("tab-\(tab.rawValue)")
        .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
    }

    private func colour(for tab: AppTab) -> Color {
        guard tab.isAvailable else { return Theme.Ink.ink3 }
        return selection == tab ? Theme.Accent.clayStrong : Theme.Ink.ink2
    }
}

/// A search field (12.3). Paper fill so it reads as something to type into,
/// against the ground the rest of the screen sits on.
struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    var identifier: String

    var body: some View {
        HStack(spacing: Theme.Metric.s8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Ink.ink3)
            TextField(placeholder, text: $text)
                .typeRole(.body)
                .foregroundStyle(Theme.Ink.ink)
                .tint(Theme.Accent.clay)
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Ink.ink3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Metric.s12)
        .padding(.vertical, 10)
        .background(Theme.Surface.paper)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                .stroke(Theme.Line.line2, lineWidth: 1)
        }
    }
}

/// One library/home row (12.4): thumbnail, title, subtitle, derived chips, and
/// the trailing meta in mono.
struct LRow: View {
    let row: LibraryRow
    var identifier: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Metric.s12) {
                PageThumb()
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title).typeRole(.titleS).foregroundStyle(Theme.Ink.ink)
                    if !row.subtitle.isEmpty {
                        Text(row.subtitle).typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                            .lineLimit(1)
                    }
                    if !row.chips.isEmpty {
                        HStack(spacing: Theme.Metric.s4) {
                            ForEach(Array(row.chips.enumerated()), id: \.offset) { _, chip in
                                DerivedChip(chip: chip)
                            }
                        }
                    }
                }
                Spacer(minLength: Theme.Metric.s8)
                if !row.meta.isEmpty {
                    Text(row.meta).typeRole(.data).foregroundStyle(Theme.Ink.ink3)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Ink.ink3)
            }
            .padding(.horizontal, Theme.Metric.s20)
            .padding(.vertical, 9)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// A page-shaped placeholder. Real page-1 rasters need the thumbnail cache
/// (§7); until then this says "a score" without pretending to be one.
struct PageThumb: View {
    var width: CGFloat = 44
    var height: CGFloat = 57

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { _ in
                Rectangle().fill(Theme.Line.line).frame(height: 1.5)
            }
        }
        .padding(.horizontal, 5)
        .frame(width: width, height: height, alignment: .top)
        .padding(.top, 8)
        .background(Theme.Surface.paper)
        .overlay { Rectangle().stroke(Theme.Line.line2, lineWidth: 1) }
    }
}

/// A derived chip (12.5). Never a stored tag -- everything it can say is
/// computed from the manifest.
struct DerivedChip: View {
    let chip: LibraryRow.Chip

    var body: some View {
        Text(chip.text)
            .typeRole(chip.kind == .count ? .data : .meta)
            .foregroundStyle(foreground)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(background)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                    .stroke(border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
    }

    private var foreground: Color {
        switch chip.kind {
        case .count:   return Theme.Accent.clayStrong
        case .warning: return Color(hex: 0x8A5A12)
        case .plain:   return Theme.Ink.ink2
        }
    }
    private var background: Color {
        switch chip.kind {
        case .count:   return Theme.Accent.clayTint
        case .warning: return Color(hex: 0xFBF2E6)
        case .plain:   return Theme.Surface.band
        }
    }
    private var border: Color {
        switch chip.kind {
        case .count:   return Theme.Accent.clayBorder
        case .warning: return Color(hex: 0xE8CFA6)
        case .plain:   return Theme.Line.line2
        }
    }
}
