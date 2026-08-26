import SwiftUI

/// Home (NAVIGATION_SYSTEM.md §4.1).
///
/// The reference puts coloured tool panels here -- a tuner, a metronome, a
/// store. We have none of those, and inventing them as chrome would be a lie,
/// so the four panels are all things this app already does. They are told apart
/// by FILL WEIGHT rather than by four colours, which keeps the three-colour
/// budget the design system is built on (§1).
///
/// Where the reference has an account avatar we put the engine chip: we have no
/// accounts, and we do have two engines -- and which one is running is the
/// thing you actually need to know at a glance.
struct HomeView: View {
    @EnvironmentObject var state: AppState
    @Binding var search: String
    var onOpen: (String) -> Void
    var onOpenSetlist: (SetlistDoc) -> Void
    var onImport: () -> Void
    var onNewArrangement: () -> Void
    var onNewSetlist: () -> Void
    var onAsk: () -> Void
    var onSettings: () -> Void
    var onAllPieces: () -> Void
    var onAllSetlists: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topRow
                    .padding(.horizontal, Theme.Metric.s20)
                    .padding(.top, Theme.Metric.s12)
                SearchField(placeholder: "Search pieces, arrangements, setlists…",
                            text: $search, identifier: "home-search")
                    .padding(.horizontal, Theme.Metric.s20)
                    .padding(.vertical, Theme.Metric.s12)
                quickActions
                    .padding(.horizontal, Theme.Metric.s20)
                if search.isEmpty {
                    section(title: "RECENT PIECES", link: "All pieces",
                            onLink: onAllPieces, rows: recentPieces, prefix: "home-piece")
                    section(title: "RECENT SETLISTS", link: "All setlists",
                            onLink: onAllSetlists, rows: recentSetlists, prefix: "home-setlist")
                } else {
                    section(title: "RESULTS", link: nil, onLink: {},
                            rows: searchResults, prefix: "home-result")
                }
                buildStamp
            }
            .padding(.bottom, Theme.Metric.s32)
        }
        .background(Theme.Surface.ground)
    }

    /// Which build this is (0.4.1 item 1).
    ///
    /// It disappeared in the redesign, and a tester who cannot say which build
    /// they are on cannot report anything useful about it -- every device
    /// report in this project has turned on knowing that.
    private var buildStamp: some View {
        Text(BuildStamp.short)
            .typeRole(.data)
            .foregroundStyle(Theme.Ink.ink3)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Theme.Metric.s24)
            .accessibilityIdentifier("build-stamp")
    }

    private var topRow: some View {
        HStack(spacing: Theme.Metric.s8) {
            PanelIconButton(systemName: "questionmark", label: "Help") {}
            inbox
            PanelIconButton(systemName: "gearshape", label: "Settings", action: onSettings)
                .accessibilityIdentifier("home-settings")
            Spacer()
            engineChip
        }
    }

    private var inbox: some View {
        PanelIconButton(systemName: "tray", label: "Inbox") {}
            .overlay(alignment: .topTrailing) {
                if !state.pendingImports.isEmpty {
                    Text("\(state.pendingImports.count)")
                        .typeRole(.meta)
                        .foregroundStyle(Theme.Surface.paper)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Circle().fill(Theme.Accent.clay))
                        .offset(x: 4, y: -4)
                }
            }
    }

    private var engineChip: some View {
        HStack(spacing: Theme.Metric.s6) {
            LED(isOn: state.engineOK)
            Text(state.useLocalEngine ? "on-device" : "remote")
                .typeRole(.data).foregroundStyle(Theme.Ink.ink2)
        }
        .padding(.horizontal, Theme.Metric.s8)
        .padding(.vertical, 5)
        .background(Theme.Surface.panel)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                .stroke(Theme.Line.line2, lineWidth: 1)
        }
        .accessibilityIdentifier("home-engine-chip")
        .accessibilityLabel("Engine: \(state.useLocalEngine ? "on-device" : "remote"), "
                            + (state.engineOK ? "reachable" : "unreachable"))
    }

    private var quickActions: some View {
        HStack(spacing: Theme.Metric.s12) {
            QuickAction(glyph: "arrow.down.to.line", title: "Import or scan",
                        detail: "PDF, MusicXML, MIDI. A PDF goes through OMR first.",
                        fill: Theme.Accent.clayTint, border: Theme.Accent.clayBorder,
                        identifier: "home-import", action: onImport)
            QuickAction(glyph: "square", title: "New arrangement",
                        detail: "A blank staff, then ask for what you want.",
                        fill: Theme.Surface.band, border: Theme.Line.line2,
                        identifier: "home-new-arrangement", action: onNewArrangement)
            QuickAction(glyph: "line.3.horizontal", title: "New setlist",
                        detail: "A gig's running order of arrangements.",
                        fill: Theme.Surface.well, border: Theme.Line.line2,
                        identifier: "home-new-setlist", action: onNewSetlist)
            QuickAction(glyph: "bubble.left", title: "Ask Scoranger",
                        detail: "Pick up the last arrangement you had open.",
                        fill: Theme.Surface.panel, border: Theme.Line.line2,
                        identifier: "home-ask", action: onAsk)
        }
    }

    @ViewBuilder
    private func section(title: String, link: String?, onLink: @escaping () -> Void,
                         rows: [LibraryRow], prefix: String) -> some View {
        BandHeader(title: title) {
            if let link {
                Button(action: onLink) {
                    HStack(spacing: 2) {
                        Text(link).typeRole(.meta)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(Theme.Ink.ink2)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-link-\(prefix)")
            }
        }
        if rows.isEmpty {
            Text(search.isEmpty ? "Nothing here yet." : "No matches.")
                .typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                .padding(.horizontal, Theme.Metric.s20)
                .padding(.vertical, Theme.Metric.s12)
        } else {
            ForEach(rows) { row in
                LRow(row: row, identifier: "\(prefix)-\(row.id)") { open(row, prefix: prefix) }
                Divider().overlay(Theme.Line.line)
            }
        }
    }

    private func open(_ row: LibraryRow, prefix: String) {
        if prefix.contains("setlist"),
           let setlist = (state.manifest?.setlists ?? []).first(where: { $0.slug == row.id }) {
            onOpenSetlist(setlist)
        } else {
            onOpen(row.id)
        }
    }

    /// Recent pieces come from the newest version time of their arrangements --
    /// the data is already there, no new field (§7).
    private var recentPieces: [LibraryRow] {
        guard let manifest = state.manifest else { return [] }
        return Array(LibraryModel.sorted(LibraryModel.pieceRows(manifest: manifest),
                                         by: .recent).prefix(5))
    }

    /// Setlists carry no timestamps at all, so "recent" is what the app itself
    /// remembers opening (§7): a client-side list.
    private var recentSetlists: [LibraryRow] {
        guard let manifest = state.manifest else { return [] }
        let rows = LibraryModel.setlistRows(manifest: manifest)
        let opened = RecentSetlists.slugs()
        let ordered = opened.compactMap { slug in rows.first { $0.id == slug } }
        return Array((ordered + rows.filter { !opened.contains($0.id) }).prefix(4))
    }

    private var searchResults: [LibraryRow] {
        guard let manifest = state.manifest else { return [] }
        let all = LibraryModel.pieceRows(manifest: manifest)
            + LibraryModel.unfiledRows(manifest: manifest)
            + LibraryModel.setlistRows(manifest: manifest)
        return LibraryModel.searched(all, query: search)
    }
}

/// A quick-action panel (12.2).
struct QuickAction: View {
    let glyph: String
    let title: String
    let detail: String
    let fill: Color
    let border: Color
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Metric.s8) {
                Image(systemName: glyph)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Theme.Accent.clayStrong)
                Text(title).typeRole(.titleS).foregroundStyle(Theme.Ink.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Text(detail).typeRole(.meta).foregroundStyle(Theme.Ink.ink2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Metric.s12)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rPanel))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metric.rPanel)
                    .stroke(border, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// Which setlists were opened -- the one piece of "recent" the engine cannot
/// tell us, so the app remembers it itself (§7).
enum RecentSetlists {
    private static let key = "recentSetlists"

    static func slugs() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func opened(_ slug: String) {
        var list = slugs().filter { $0 != slug }
        list.insert(slug, at: 0)
        UserDefaults.standard.set(Array(list.prefix(12)), forKey: key)
    }
}
