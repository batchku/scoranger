import SwiftUI

/// The title dropdown (NAVIGATION_SYSTEM.md N6, 12.10).
///
/// Two levels, because our hierarchy is two levels: the arrangements of this
/// piece, then the versions of this arrangement (§2). The design session's
/// recommendation was to keep versions here rather than only in `…`, and that
/// is what ships; if it reads as too dense on a real stand, §9.6 says versions
/// move out and the dropdown keeps arrangements alone.
struct TitleMenu: View {
    @EnvironmentObject var state: AppState
    let score: ScoreDoc
    var onPick: (String) -> Void
    var onPickVersion: (String?) -> Void
    var onAllVersions: () -> Void

    private var piece: PieceDoc? {
        state.manifest?.pieces?.first { $0.arrangements.contains(score.slug) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let piece {
                BandHeader("Arrangements of \(piece.name)")
                ForEach(Array(piece.arrangements.enumerated()), id: \.offset) { index, slug in
                    if let arrangement = state.manifest?.scores.first(where: { $0.slug == slug }) {
                        row(number: index + 1,
                            title: arrangement.title ?? arrangement.name,
                            detail: "\(arrangement.versions.count) versions",
                            selected: slug == score.slug,
                            identifier: "menu-arrangement-\(slug)") { onPick(slug) }
                    }
                }
            }
            BandHeader("Versions")
            ForEach(recentVersions, id: \.id) { version in
                row(number: nil, title: version.id, detail: version.op,
                    selected: version.id == state.displayedVersionID,
                    identifier: "menu-version-\(version.id)") {
                    onPickVersion(version.id == score.latest ? nil : version.id)
                }
            }
            if score.versions.count > recentVersions.count {
                Button(action: onAllVersions) {
                    HStack {
                        Text("All \(score.versions.count) versions").typeRole(.row)
                            .foregroundStyle(Theme.Ink.ink2)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.Ink.ink3)
                    }
                    .padding(.horizontal, Theme.Metric.panelPadding)
                    .padding(.vertical, Theme.Metric.sheetRowVertical)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("menu-all-versions")
            }
        }
        .frame(width: 360)
        .background(Theme.Surface.panel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rPanel))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metric.rPanel)
                .stroke(Theme.Line.line2, lineWidth: 1)
        }
        .modifier(ChipShadow())
        .accessibilityIdentifier("title-menu")
    }

    private var recentVersions: [VersionDoc] { Array(score.versions.suffix(5).reversed()) }

    private func row(number: Int?, title: String, detail: String, selected: Bool,
                     identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Metric.s8) {
                if let number { NumeralBadge(number: number, role: .numeralM) }
                Text(title).typeRole(.row).foregroundStyle(Theme.Ink.ink).lineLimit(1)
                Spacer(minLength: Theme.Metric.s8)
                Text(detail).typeRole(.data).foregroundStyle(Theme.Ink.ink3).lineLimit(1)
                Image(systemName: selected ? "checkmark" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(selected ? Theme.Accent.clayStrong : Theme.Ink.ink3)
            }
            .padding(.horizontal, Theme.Metric.panelPadding)
            .padding(.vertical, Theme.Metric.sheetRowVertical)
            .background(selected ? Theme.Accent.clayTint : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// The "…" menu (N7/N8, 12.14).
///
/// Two layers, never a modal: layer one lists the categories, layer two
/// replaces the contents behind a back row. Everything the gear menu and the
/// Settings sheet used to hold arrives here (§8).
struct MoreMenu: View {
    @EnvironmentObject var state: AppState
    @Binding var mode: ScoreMode
    @Binding var showTransport: Bool
    var onClose: () -> Void
    var onSettings: () -> Void
    var onDetails: () -> Void
    var onExport: () -> Void

    @State private var layer: Layer = .root

    enum Layer: Equatable {
        case root, display, annotations, selection, transpose, versions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch layer {
            case .root:        rootLayer
            case .display:     displayLayer
            case .annotations: annotationsLayer
            case .selection:   selectionLayer
            case .transpose:   transposeLayer
            case .versions:    versionsLayer
            }
        }
        .frame(width: 320)
        .background(Theme.Surface.panel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rPanel))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metric.rPanel)
                .stroke(Theme.Line.line2, lineWidth: 1)
        }
        .modifier(ChipShadow())
        .accessibilityIdentifier("more-menu")
    }

    // MARK: - Layer one

    private var rootLayer: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Performance mode sits in the highlighted top row because it is
            // the one entry that changes what every input means (§6).
            HStack(spacing: Theme.Metric.s8) {
                Image(systemName: "music.note.list").font(.system(size: 15))
                    .foregroundStyle(Theme.Accent.clayStrong)
                Text("Performance mode").typeRole(.row).foregroundStyle(Theme.Ink.ink)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { mode == .performance },
                    set: { on in
                        mode = on ? .performance : .read
                        if on { state.annotation.isOn = false }
                        onClose()
                    }))
                    .labelsHidden()
                    .tint(Theme.Accent.clay)
                    .accessibilityIdentifier("more-performance")
            }
            .padding(.horizontal, Theme.Metric.panelPadding)
            .padding(.vertical, Theme.Metric.sheetRowVertical)
            .background(Theme.Accent.clayTint)

            entry("Score display", glyph: "rectangle.split.2x1", id: "more-display") {
                layer = .display
            }
            entry("Annotations", glyph: "pencil.tip", id: "more-annotations") {
                layer = .annotations
            }
            entry("Selection & chat", glyph: "lasso", id: "more-selection") {
                layer = .selection
            }
            entry("Transpose", glyph: "arrow.up.arrow.down", id: "more-transpose") {
                layer = .transpose
            }
            entry("Versions", glyph: "clock.arrow.circlepath", id: "more-versions") {
                layer = .versions
            }
            entry("Piece & arrangement details", glyph: "info.circle", id: "more-details") {
                onClose(); onDetails()
            }
            entry("Share & export", glyph: "square.and.arrow.up", id: "more-export") {
                onClose(); onExport()
            }
            entry("Settings", glyph: "gearshape", id: "more-settings") {
                onClose(); onSettings()
            }
        }
    }

    // MARK: - Layer two

    private var displayLayer: some View {
        VStack(alignment: .leading, spacing: 0) {
            back("Score display")
            toggleRow("Two pages side by side", isOn: $state.twoPageSpread,
                      id: "display-spread")
            // §9.2: a transport that does nothing teaches people the app is
            // broken, so it is off by default and named a preview. prev/next
            // step the setlist and work whether or not this is on.
            toggleRow("Show transport (preview)", isOn: $showTransport,
                      id: "display-transport")
            note("Playback is not wired up. Previous and next step the current "
                 + "setlist, and those work.")
        }
    }

    private var annotationsLayer: some View {
        VStack(alignment: .leading, spacing: 0) {
            back("Annotations")
            actionRow("Clear markup on this version", id: "annotations-clear") {
                if let score = state.selectedScore, let vid = state.displayedVersionID {
                    DrawingStore.shared.clear(prefix: "\(score.slug)/\(vid)")
                    Task { await state.renderIfNeeded(force: true) }
                }
                onClose()
            }
            note("Ink belongs to the version it was drawn on.")
        }
    }

    private var selectionLayer: some View {
        VStack(alignment: .leading, spacing: 0) {
            back("Selection & chat")
            actionRow("Clear selection", id: "selection-clear") {
                state.clearSelection(); onClose()
            }
            note(mode.pencilMeaning + ". Hold a finger down while drawing to add "
                 + "to the selection; tap an element to drop it.")
        }
    }

    private var transposeLayer: some View {
        VStack(alignment: .leading, spacing: 0) {
            back("Transpose")
            actionRow("Up a semitone", id: "transpose-up") {
                state.transpose(semitones: 1); onClose()
            }
            actionRow("Down a semitone", id: "transpose-down") {
                state.transpose(semitones: -1); onClose()
            }
            note("Transposes the whole arrangement. To move only some notes, "
                 + "select them and ask in chat.")
        }
    }

    private var versionsLayer: some View {
        VStack(alignment: .leading, spacing: 0) {
            back("Versions")
            if let score = state.selectedScore {
                ForEach(score.versions.reversed(), id: \.id) { version in
                    actionRow("\(version.id) · \(version.op)",
                              id: "version-\(version.id)") {
                        state.pinnedVersion = version.id == score.latest ? nil : version.id
                        Task { await state.renderIfNeeded() }
                        onClose()
                    }
                }
            }
        }
    }

    // MARK: - Rows

    private func entry(_ title: String, glyph: String, id: String,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Metric.s8) {
                Image(systemName: glyph).font(.system(size: 14))
                    .foregroundStyle(Theme.Ink.ink2).frame(width: 18)
                Text(title).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Ink.ink3)
            }
            .padding(.horizontal, Theme.Metric.panelPadding)
            .padding(.vertical, Theme.Metric.sheetRowVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func back(_ title: String) -> some View {
        Button { layer = .root } label: {
            HStack(spacing: Theme.Metric.s8) {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                Text(title).typeRole(.label)
                Spacer()
            }
            .foregroundStyle(Theme.Accent.clayStrong)
            .padding(.horizontal, Theme.Metric.panelPadding)
            .padding(.vertical, Theme.Metric.s6)
            .background(Theme.Surface.band)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("more-back")
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>, id: String) -> some View {
        HStack(spacing: Theme.Metric.s8) {
            Text(title).typeRole(.row).foregroundStyle(Theme.Ink.ink)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(Theme.Accent.clay)
                .accessibilityIdentifier(id)
        }
        .padding(.horizontal, Theme.Metric.panelPadding)
        .padding(.vertical, Theme.Metric.sheetRowVertical)
    }

    private func actionRow(_ title: String, id: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                Spacer()
            }
            .padding(.horizontal, Theme.Metric.panelPadding)
            .padding(.vertical, Theme.Metric.sheetRowVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func note(_ text: String) -> some View {
        Text(text).typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Metric.panelPadding)
            .padding(.bottom, Theme.Metric.s8)
    }
}
