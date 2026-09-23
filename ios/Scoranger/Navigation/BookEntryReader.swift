import PDFKit
import SwiftUI

/// One tune of a book's contents, read in place (0.14.0 §2a).
///
/// The book stays one book: this shows ITS pages from the entry's `from` to
/// `to`, not a copy, and the previous and next tune are one tap away -- a set
/// list's reading, for a book's tunes, instead of a scroll through the whole
/// PDF. It is not the score reader: that reader is built around an
/// arrangement's versions, its engraving and its ink, and a book entry has
/// none of them. Take the tune out to mark it up (BACKLOG).
struct BookEntryReader: View {
    @EnvironmentObject var state: AppState
    let slug: String
    let entryID: String
    var onBack: () -> Void
    var onStep: (String) -> Void

    @State private var document: PDFDocument?
    @State private var loading = true

    private var book: BookDoc? {
        (state.manifest?.books ?? []).first { $0.slug == slug }
    }
    private var entries: [BookEntry] { book?.contents ?? [] }
    private var entry: BookEntry? { entries.first { $0.id == entryID } }

    var body: some View {
        Screen(title: entry?.title ?? "Tune", backLabel: book?.name ?? "Book",
               subtitle: subtitle, onBack: onBack,
               trailing: { stepper }) {
            VStack(spacing: Theme.Metric.s16) {
                if let entry, let document {
                    ForEach(entry.from...entry.to, id: \.self) { page in
                        BookEntryPage(document: document, index: page - 1)
                            .accessibilityIdentifier("book-entry-page-\(page)")
                    }
                } else if loading {
                    PanelNote(text: "Opening the book…")
                } else if entry == nil {
                    PanelNote(text: "This tune is no longer in the book's contents.")
                } else {
                    PanelNote(text: "The book's pages could not be opened here.")
                }
            }
            .padding(Theme.Metric.pageSide)
        }
        .task(id: slug) {
            loading = true
            document = await state.bookDocument(slug)
            loading = false
        }
    }

    /// "Tune 3 of 124 · pp. 12–13"
    private var subtitle: String? {
        guard let entry else { return nil }
        return [BookReading.label(of: entry.id, in: entries), BookReading.pages(entry)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var stepper: some View {
        let previous = BookReading.neighbour(of: entryID, in: entries, by: -1)
        let next = BookReading.neighbour(of: entryID, in: entries, by: 1)
        return HStack(spacing: Theme.Metric.s8) {
            PanelButton(title: "Previous", identifier: "book-entry-previous") {
                if let previous { onStep(previous.id) }
            }
            .disabled(previous == nil)
            PanelButton(title: "Next", kind: .primary, identifier: "book-entry-next") {
                if let next { onStep(next.id) }
            }
            .disabled(next == nil)
        }
    }
}

/// One page, the width of the reading column, at its own shape.
private struct BookEntryPage: View {
    let document: PDFDocument
    let index: Int

    var body: some View {
        GeometryReader { geo in
            let size = drawn(width: geo.size.width)
            PageImage(document: document, index: index, drawn: size,
                      raster: CGSize(width: size.width * 2, height: size.height * 2),
                      interpolation: .high) { phase in
                PageThumb(width: size.width, height: size.height)
                    .overlay {
                        if phase == .missing {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(Theme.Status.warn)
                        }
                    }
            }
            .background(Theme.Surface.paper)
        }
        .aspectRatio(ratio, contentMode: .fit)
    }

    private var ratio: CGFloat {
        let bounds = document.page(at: index)?.bounds(for: .mediaBox)
            ?? CGRect(x: 0, y: 0, width: 8.5, height: 11)
        return bounds.height > 0 ? bounds.width / bounds.height : 0.77
    }

    private func drawn(width: CGFloat) -> CGSize {
        CGSize(width: width, height: ratio > 0 ? width / ratio : width * 1.3)
    }
}
