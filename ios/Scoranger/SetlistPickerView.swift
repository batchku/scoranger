import SwiftUI

/// What is in a running order, and what could be.
///
/// A setlist holds arrangements, not pieces: what gets played is a particular
/// version of a tune, and "the quartet one, then the accordion one" is a set
/// in a way that "Sous le ciel de Paris" is not. So this lists every
/// arrangement, marks the ones already in the setlist, and toggles on tap.
struct SetlistPickerView: View {
    let setlist: SetlistDoc
    @EnvironmentObject var state: AppState

    /// The setlist as it stands now — the sheet edits it, so it cannot read
    /// from the snapshot it opened with.
    private var live: SetlistDoc {
        state.manifest?.setlists?.first { $0.slug == setlist.slug } ?? setlist
    }

    private var everyArrangement: [ScoreDoc] {
        (state.manifest?.scores ?? []).sorted {
            $0.name.lowercased() < $1.name.lowercased()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BandHeader("In this set list")
            let members = live.arrangements
            if members.isEmpty {
                PanelNote(text: "Nothing yet — tap an arrangement below to add it.")
                    .padding(Theme.Metric.panelPadding)
            }
            ForEach(Array(members.enumerated()), id: \.element) { index, slug in
                if let score = everyArrangement.first(where: { $0.slug == slug }) {
                    row(score, position: index + 1, isMember: true)
                }
            }

            BandHeader("Add an arrangement")
            let candidates = everyArrangement.filter { !members.contains($0.slug) }
            if candidates.isEmpty {
                PanelNote(text: "Every arrangement is already in this set list.")
                    .padding(Theme.Metric.panelPadding)
            }
            ForEach(candidates) { score in
                row(score, position: nil, isMember: false)
            }
        }
    }

    private func row(_ score: ScoreDoc, position: Int?, isMember: Bool) -> some View {
        Button {
            Task {
                if isMember {
                    await state.removeFromSetlist(setlist: setlist.slug, score: score.slug)
                } else {
                    await state.addToSetlist(setlist: setlist.slug, score: score.slug)
                }
            }
        } label: {
            HStack(spacing: Theme.Metric.s8) {
                // the running order's own number, not the piece's #N
                if let position {
                    Text("\(position).").typeRole(.data)
                        .foregroundStyle(Theme.Accent.clayStrong)
                        .frame(minWidth: 22, alignment: .trailing)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(score.name).typeRole(.row).foregroundStyle(Theme.Ink.ink)
                        .lineLimit(1)
                    HStack(spacing: Theme.Metric.s4) {
                        if let placement = state.placement(of: score.slug) {
                            Text(placement.piece.name).typeRole(.meta)
                                .foregroundStyle(Theme.Ink.ink3).lineLimit(1)
                        }
                        // Building a running order is exactly when knowing a
                        // tune is still a PDF matters (0.6.3 #3, #4).
                        ForEach(Array(ArtifactTag.chips(
                                        files: score.versions.map(\.file))
                                        .enumerated()), id: \.offset) { _, chip in
                            DerivedChip(chip: chip)
                        }
                    }
                }
                Spacer(minLength: Theme.Metric.s8)
                Image(systemName: isMember ? "minus.circle" : "plus.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isMember ? Theme.Status.danger : Theme.Accent.clayStrong)
            }
            .padding(.horizontal, Theme.Metric.panelPadding)
            .padding(.vertical, Theme.Metric.sheetRowVertical)
            .frame(minHeight: Theme.Metric.sheetRowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("picker-\(isMember ? "remove" : "add")-\(score.slug)")
        .accessibilityLabel("\(isMember ? "Remove" : "Add") \(score.name)")
    }
}

/// The other direction: one arrangement, every set list, in or out.
struct SetlistChooserView: View {
    let score: ScoreDoc
    /// Asks the caller to run the "new set list" flow, seeded with this score.
    let onNewSetlist: () -> Void
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BandHeader("Set lists")
            let setlists = state.manifest?.setlists ?? []
            if setlists.isEmpty {
                PanelNote(text: "No set lists yet.")
                    .padding(Theme.Metric.panelPadding)
            }
            ForEach(setlists) { setlist in
                let isIn = setlist.arrangements.contains(score.slug)
                Button {
                    Task {
                        if isIn {
                            await state.removeFromSetlist(setlist: setlist.slug,
                                                          score: score.slug)
                        } else {
                            await state.addToSetlist(setlist: setlist.slug,
                                                     score: score.slug)
                        }
                    }
                } label: {
                    HStack(spacing: Theme.Metric.s8) {
                        Text(setlist.name).typeRole(.row)
                            .foregroundStyle(Theme.Ink.ink)
                        Spacer(minLength: Theme.Metric.s8)
                        Text("\(setlist.arrangements.count)").typeRole(.data)
                            .foregroundStyle(Theme.Ink.ink3)
                        Image(systemName: isIn ? "checkmark.circle.fill" : "plus.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.Accent.clayStrong)
                    }
                    .padding(.horizontal, Theme.Metric.panelPadding)
                    .padding(.vertical, Theme.Metric.sheetRowVertical)
                    .frame(minHeight: Theme.Metric.sheetRowMinHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chooser-\(setlist.slug)")
                .accessibilityLabel("\(isIn ? "Remove from" : "Add to") \(setlist.name)")
            }

            VStack(alignment: .leading, spacing: Theme.Metric.s8) {
                PanelButton(title: "New set list…", kind: .primary, action: onNewSetlist)
                    .accessibilityIdentifier("chooser-new-setlist")
            }
            .padding(Theme.Metric.panelPadding)
        }
    }
}
