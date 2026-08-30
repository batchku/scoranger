import SwiftUI

/// A book, and the arrangements you take out of it.
///
/// You do not read a book here. A book is a reference — a fake book, a method
/// book — and what makes it useful is pulling one tune out of it and filing
/// that under its piece. The pages are copied, so the book is never cut up.
struct BookScreen: View {
    @EnvironmentObject var state: AppState
    let slug: String
    var onBack: () -> Void
    var onOpen: (String) -> Void

    @State private var fromPage = ""
    @State private var toPage = ""
    @State private var name = ""
    @State private var piece = ""
    @State private var busy = false
    @State private var made: String?

    private var book: BookDoc? {
        (state.manifest?.books ?? []).first { $0.slug == slug }
    }

    /// Both pages must be real numbers inside the book, and in order. Stated
    /// here so the button can say whether it will work before it is pressed —
    /// the engine refuses a bad range, but a disabled button is a better
    /// answer than an error.
    private var range: (from: Int, to: Int)? {
        guard let from = Int(fromPage.trimmingCharacters(in: .whitespaces)),
              let to = Int(toPage.trimmingCharacters(in: .whitespaces)),
              let pages = book?.pages,
              from >= 1, to <= pages, from <= to else { return nil }
        return (from, to)
    }

    private var canExtract: Bool {
        range != nil && !name.trimmingCharacters(in: .whitespaces).isEmpty && !busy
    }

    var body: some View {
        Screen(title: book?.name ?? "Book",
               backLabel: "My library",
               subtitle: book?.pages.map { "\($0) pages" },
               onBack: onBack) {
            VStack(alignment: .leading, spacing: 0) {
                BandHeader("Take an arrangement out")
                VStack(alignment: .leading, spacing: Theme.Metric.s12) {
                    if let made {
                        PanelNote(text: made)
                    }
                    HStack(spacing: Theme.Metric.s12) {
                        PanelField(placeholder: "From page", text: $fromPage, isMono: true)
                            .accessibilityIdentifier("book-from-page")
                        PanelField(placeholder: "To page", text: $toPage, isMono: true)
                            .accessibilityIdentifier("book-to-page")
                    }
                    PanelField(placeholder: "Name of the tune", text: $name)
                        .accessibilityIdentifier("book-name")
                    PanelField(placeholder: "File under this piece (optional)", text: $piece)
                        .accessibilityIdentifier("book-piece")
                    PanelNote(text: "The pages are copied. \(book?.name ?? "The book") "
                              + "stays as it is.")
                    PanelButton(title: busy ? "Taking it out…" : "Add arrangement",
                                kind: .primary) {
                        extract()
                    }
                    .disabled(!canExtract)
                    .accessibilityIdentifier("book-extract")
                }
                .padding(Theme.Metric.panelPadding)
            }
            .padding(.bottom, Theme.Metric.s32)
        }
    }

    private func extract() {
        guard let range else { return }
        let tune = name.trimmingCharacters(in: .whitespaces)
        let filed = piece.trimmingCharacters(in: .whitespaces)
        busy = true
        Task {
            let slugMade = await state.extractFromBook(slug, from: range.from,
                                                       to: range.to, name: tune,
                                                       piece: filed.isEmpty ? nil : filed)
            busy = false
            if slugMade != nil {
                made = "Added “\(tune)” from pages \(range.from)–\(range.to)."
                fromPage = ""; toPage = ""; name = ""; piece = ""
            }
        }
    }
}
