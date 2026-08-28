import SwiftUI

// The bottom tab bar is gone (§4C). It held Home, My Library and a disabled
// Shared placeholder -- one live tab and a stub, which is not a tab bar. The
// app opens on My Library, and the Pieces/Setlists segmented control is the
// only place-switcher. If sharing lands it returns as a third SEGMENT.

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

/// One library row (12.4): thumbnail, title, subtitle, derived chips, and
/// the trailing meta in mono.
struct LRow: View {
    let row: LibraryRow
    var identifier: String
    var action: () -> Void
    /// The one control a row carries (§4): row tap opens the music, ☰ manages.
    var onMenu: (() -> Void)?
    var menuIsOpen: Bool = false

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
                    // Never wrapped, never compressed, and never squeezed by
                    // the title beside it: "v001 · 19:55" is one short mono
                    // string and it is what the reader checks at a glance.
                    Text(row.meta).typeRole(.data).foregroundStyle(Theme.Ink.ink3)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                }
                // No chevron when there is a ☰. Three trailing affordances --
                // meta, chevron, ☰ -- were two too many, and the chevron said
                // exactly what the ☰ says: there is more here. The row itself
                // is still a button; that is what its tap is for.
                if onMenu == nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Ink.ink3)
                }
            }
            .padding(.leading, Theme.Metric.s20)
            // a row with a ☰ keeps its content clear of it; the overlay sits
            // outside the layout, so nothing else would
            .padding(.trailing, onMenu == nil ? Theme.Metric.s20
                                              : Theme.Metric.rowMenuInset)
            .padding(.vertical, 9)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .overlay(alignment: .trailing) {
            if let onMenu {
                RowMenuButton(identifier: "row-menu-\(row.id)",
                              label: "Manage \(row.title)",
                              isOpen: menuIsOpen, action: onMenu)
                    .padding(.trailing, Theme.Metric.s8)
            }
        }
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
