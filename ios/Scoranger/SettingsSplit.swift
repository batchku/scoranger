import SwiftUI

// Settings as a split (design/DESIGN_SYSTEM.md §7.17, T1–T10): an index at
// the left, 300 wide, each item stating its section's answer in meta, the
// current one in clayTint; the chosen section at the right, never more than
// a few rows and a note. On a compact width the index alone, each section
// pushed as its own page (Ph6). Labels per §10: Engine, Server, Scanning,
// Model; the sentences that were headers are notes under the control.

enum SettingsSection: String, CaseIterable, Identifiable {
    case account, reading, titles, engine, server, scanning, model, diagnostics, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .account:     return "Account"
        case .reading:     return "Reading"
        case .titles:      return "Titles"
        case .engine:      return "Engine"
        case .server:      return "Server"
        case .scanning:    return "Scanning"
        case .model:       return "Model"
        case .diagnostics: return "Diagnostics"
        case .about:       return "About"
        }
    }
}

struct SettingsSplit: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var signIn: SignIn
    @State private var section: SettingsSection = .reading
    @State private var pushed: SettingsSection?
    @Environment(\.horizontalSizeClass) private var sizeClass

    static let indexWidth: CGFloat = 300

    /// The sections that apply right now: Titles only while the scan finds
    /// something, Server only while the engine is remote.
    private var sections: [SettingsSection] {
        SettingsSection.allCases.filter { s in
            switch s {
            // Titles stays while it is the section being read: the repair
            // empties the scan, and its result has to be readable after.
            case .titles: return section == .titles || pushed == .titles
                || TitleRepair.offer(count: state.titleRepairsNeeded.count) != nil
            case .server: return !state.useLocalEngine
            default:      return true
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let compact = sizeClass == .compact || geo.size.width < Self.indexWidth * 2.2
            if compact {
                ZStack {
                    index(fullWidth: true)
                    if let pushed {
                        VStack(spacing: 0) {
                            PanelHeader(title: pushed.title, trailing: { EmptyView() })
                                .environment(\.panelBack, { self.pushed = nil })
                                .environment(\.panelDone, nil)
                            ScrollView { SettingsSectionView(section: pushed) }
                        }
                        .background(Theme.Surface.panel)
                        .transition(.move(edge: .trailing))
                    }
                }
                .animation(Theme.Motion.overlay(reduced: false), value: pushed)
            } else {
                HStack(alignment: .top, spacing: Theme.Metric.pagePanelGap) {
                    index(fullWidth: false)
                        .frame(width: Self.indexWidth)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(sectionShown.title).typeRole(.panelTitle)
                                .foregroundStyle(Theme.Ink.ink)
                                .padding(.horizontal, Theme.Metric.panelSide)
                                .padding(.top, Theme.Metric.s16)
                                .padding(.bottom, Theme.Metric.s8)
                                .accessibilityIdentifier("settings-section-title")
                            SettingsSectionView(section: sectionShown)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-split")
    }

    private var sectionShown: SettingsSection {
        sections.contains(section) ? section : (sections.first ?? .reading)
    }

    private func index(fullWidth: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metric.s4) {
                ForEach(sections) { s in
                    Button {
                        if fullWidth { pushed = s } else { section = s }
                    } label: {
                        HStack(spacing: Theme.Metric.s8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.title).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                                Text(answer(for: s)).typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: Theme.Metric.s8)
                            if fullWidth {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Theme.Ink.ink3)
                            }
                        }
                        .padding(.horizontal, Theme.Metric.s16)
                        .frame(minHeight: 48)
                        .background(!fullWidth && sectionShown == s ? Theme.Accent.clayTint : Theme.Surface.band)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings-\(s.rawValue)")
                    .accessibilityLabel(s.title)
                    .accessibilityValue(answer(for: s))
                    .accessibilityAddTraits(!fullWidth && sectionShown == s ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, Theme.Metric.panelSide)
            .padding(.vertical, Theme.Metric.s12)
        }
    }

    /// Each index item states its section's answer (§7.17).
    private func answer(for s: SettingsSection) -> String {
        switch s {
        case .account:
            if case .signedIn(let account) = signIn.state { return account.email ?? "signed in" }
            return "signed out"
        case .reading:     return state.layoutChoice.label.lowercased()
        case .titles:      return "\(state.titleRepairsNeeded.count) to fix"
        case .engine:      return state.useLocalEngine ? "on-device" : "remote"
        case .server:      return state.engineURLString.isEmpty ? "not set" : state.engineURLString
        case .scanning:    return state.omrURLString.isEmpty ? "collects PDFs in Files" : "in the cloud"
        case .model:       return state.chatModel.isEmpty ? (state.modelCatalog?.default ?? "default") : state.chatModel
        case .diagnostics: return "touch log, timing"
        case .about:       return BuildStamp.short
        }
    }
}

/// One section's rows and notes, from `SettingsView`'s blocks.
struct SettingsSectionView: View {
    let section: SettingsSection
    var body: some View {
        SettingsView(section: section)
    }
}

/// Settings as a page on the table: ‹ Library, the title, a Done that a
/// reader (and the tests) know as "Close settings", and the split under it.
struct SettingsPage: View {
    var onBack: () -> Void
    var body: some View {
        Screen(title: "Settings", backLabel: "Library", onBack: onBack,
               trailing: {
                   Button(action: onBack) {
                       Text("Done").typeRole(.control).foregroundStyle(Theme.Ink.ink)
                           .padding(.horizontal, Theme.Metric.s16).frame(height: 36)
                           .background(Theme.Surface.well).clipShape(Capsule()).contentShape(Capsule())
                   }
                   .buttonStyle(.plain)
                   .accessibilityLabel("Close settings")
                   .accessibilityIdentifier("settings-done")
               }, content: { SettingsSplit() }, scrolls: false)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("settings-panel")
    }
}
