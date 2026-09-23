import SwiftUI

/// The tunes the engine found in a book, for the reader to check and correct
/// before anything is written (0.14.0 §2).
///
/// Every row is a tune: its title, editable in place, and the pages it is on.
/// Tapping a row turns the book above to its first page, so a proposal is
/// checked against the page rather than trusted. The corrections the detector
/// needs most are one tap each: fold a false start back into the tune before
/// it, part two tunes it ran together, drop a row that is not a tune.
///
/// Then one of two things, and the page says what each costs:
///   - KEEP AS CONTENTS: the book stays one book, read a tune at a time;
///   - TAKE OUT: an arrangement per tune, each under a piece of its name.
struct BookReview: View {
    @EnvironmentObject var state: AppState
    let slug: String
    let bookName: String
    @State var contents: BookContents
    /// Where the proposal came from, said once above the list.
    let evidence: String?
    var onShow: (Int) -> Void
    var onDone: (String) -> Void

    @State private var busy = false
    @State private var confirmingTakeOut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Metric.s8) {
                if let evidence {
                    PanelNote(text: evidence)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("book-review-found")
                }
                if let problem = contents.problem {
                    Text(problem).typeRole(.meta).foregroundStyle(Theme.Status.warn)
                        .accessibilityIdentifier("book-review-problem")
                }
            }
            .padding(.horizontal, Theme.Metric.panelPadding)
            .padding(.bottom, Theme.Metric.s8)

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(contents.entries.enumerated()), id: \.element.id) { index, entry in
                    row(entry, at: index)
                    Theme.Rule()
                }
            }

            actions
                .padding(Theme.Metric.panelPadding)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("book-review")
    }

    private func row(_ entry: BookEntry, at index: Int) -> some View {
        HStack(alignment: .center, spacing: Theme.Metric.s8) {
            Text("\(index + 1)").typeRole(.data).foregroundStyle(Theme.Ink.ink3)
                .frame(width: 32, alignment: .trailing)
            VStack(alignment: .leading, spacing: Theme.Metric.s4) {
                TextField("Title", text: Binding(
                    get: { entry.title },
                    set: { contents.rename(entry.id, to: $0) }))
                    .typeRole(.row)
                    .foregroundStyle(Theme.Ink.ink)
                    .accessibilityIdentifier("book-review-title-\(index + 1)")
                HStack(spacing: Theme.Metric.s6) {
                    Text("pages").typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                    pageStepper(entry, start: true)
                    // a word, not a dash: a dash between two minus buttons
                    // read as a third one
                    Text("to").typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                    pageStepper(entry, start: false)
                    if let evidence = entry.evidence {
                        Text(Self.evidenceLabel(evidence)).typeRole(.dataS)
                            .foregroundStyle(Theme.Ink.ink3)
                    }
                }
            }
            Spacer(minLength: 0)
            RowActionsBar(actions: rowActions(entry, at: index))
                .frame(maxWidth: 260)
        }
        .padding(.horizontal, Theme.Metric.panelPadding)
        .padding(.vertical, Theme.Metric.s6)
        .contentShape(Rectangle())
        .onTapGesture { onShow(entry.from) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("book-review-row-\(index + 1)")
    }

    private func pageStepper(_ entry: BookEntry, start: Bool) -> some View {
        let value = start ? entry.from : entry.to
        return HStack(spacing: 2) {
            nudge("minus", label: start ? "Start a page earlier" : "End a page earlier") {
                shift(entry, start: start, by: -1)
            }
            Text("\(value)").typeRole(.data).foregroundStyle(Theme.Ink.ink)
                .frame(minWidth: 28)
            nudge("plus", label: start ? "Start a page later" : "End a page later") {
                shift(entry, start: start, by: 1)
            }
        }
    }

    private func nudge(_ glyph: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph).font(.system(size: 11))
                .foregroundStyle(Theme.Ink.ink2)
                .frame(width: 26, height: 26)
                .background(Theme.Surface.panel)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func shift(_ entry: BookEntry, start: Bool, by delta: Int) {
        if start {
            contents.setRange(entry.id, from: entry.from + delta, to: entry.to)
            onShow(min(max(entry.from + delta, 1), contents.pages))
        } else {
            contents.setRange(entry.id, from: entry.from, to: entry.to + delta)
            onShow(min(max(entry.to + delta, 1), contents.pages))
        }
    }

    private func rowActions(_ entry: BookEntry, at index: Int) -> [RowActionItem] {
        [
            RowActionItem(id: "book-review-merge-\(index + 1)", title: "Join previous",
                          enabled: index > 0) { contents.mergeWithPrevious(entry.id) },
            RowActionItem(id: "book-review-split-\(index + 1)", title: "Split",
                          enabled: entry.to > entry.from) {
                contents.split(entry.id, at: entry.from + 1, title: "Untitled")
            },
            RowActionItem(id: "book-review-remove-\(index + 1)", title: "Remove",
                          destructive: true) { contents.remove(entry.id) },
        ]
    }

    // MARK: committing

    private var actions: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.s12) {
            let n = contents.entries.count
            PanelNote(text: "Keep as contents: \(bookName) stays one book, and its "
                      + "\(n) tune\(n == 1 ? "" : "s") are listed to read one at a "
                      + "time. Take out: each becomes an arrangement under a piece "
                      + "of its name; a piece already called that is used.")
            HStack(spacing: Theme.Metric.s8) {
                PanelButton(title: busy ? "Saving…" : "Keep as contents", kind: .primary,
                            identifier: "book-review-keep") { keep() }
                if confirmingTakeOut {
                    PanelButton(title: "Take out \(n) tune\(n == 1 ? "" : "s")",
                                kind: .primary, identifier: "book-review-take-out-confirm") {
                        takeOut()
                    }
                    PanelButton(title: "Not yet", identifier: "book-review-take-out-cancel") {
                        confirmingTakeOut = false
                    }
                } else {
                    PanelButton(title: "Take out as arrangements",
                                identifier: "book-review-take-out") { confirmingTakeOut = true }
                }
                Spacer(minLength: 0)
                PanelButton(title: "Discard", identifier: "book-review-discard") {
                    state.bookProposals[slug] = nil
                    onDone("The list was discarded. Nothing was changed.")
                }
            }
            .disabled(busy || contents.problem != nil)
        }
    }

    private func keep() {
        busy = true
        Task {
            let ok = await state.keepContents(of: slug, contents.entries)
            busy = false
            if ok {
                let n = contents.entries.count
                onDone("Kept \(n) tune\(n == 1 ? "" : "s") as the contents of \(bookName).")
            }
        }
    }

    private func takeOut() {
        busy = true
        Task {
            let report = await state.takeOutTunes(of: slug, contents.entries)
            busy = false
            confirmingTakeOut = false
            if let report { onDone(Self.summary(report)) }
        }
    }

    /// "Took out 124 tunes: 121 new pieces, 3 added to pieces already here."
    static func summary(_ report: BookSplitReport) -> String {
        let n = report.arrangements.count
        var text = "Took out \(n) tune\(n == 1 ? "" : "s"): "
            + "\(report.piecesCreated) new piece\(report.piecesCreated == 1 ? "" : "s")"
        if report.piecesJoined > 0 {
            text += ", \(report.piecesJoined) added to piece\(report.piecesJoined == 1 ? "" : "s") already here"
        }
        return text + "."
    }

    static func evidenceLabel(_ evidence: String) -> String {
        switch evidence {
        case "bookmark": return "bookmark"
        case "heading":  return "page title"
        case "ocr":      return "read from scan"
        default:         return evidence
        }
    }
}
