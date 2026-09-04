import PDFKit
import SwiftUI

/// A book, and the arrangements you take out of it.
///
/// You do not read a book here, but you do LOOK through it. A book is a
/// reference — a fake book, a method book — and what makes it useful is
/// pulling one tune out of it and filing that under its piece. The pages are
/// copied, so the book is never cut up.
///
/// The screen used to ask for a page range and show nothing at all, which in a
/// four-hundred-page fake book means guessing: type 137, extract, open it,
/// find it is "Moonglow", delete it, guess again. So the pages are here. You
/// flip to the tune, press "Starts here", flip to its last page, press "Ends
/// here", and the fields fill themselves in.
///
/// The fields stay, and stay editable, because a reader who knows the page
/// number should still be able to type it — and typing it now turns the book
/// to that page. `BookPages` is the arithmetic that keeps the two in step.
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

    /// The book, opened. nil until it has loaded, and still nil when it cannot
    /// be reached — which the screen says, rather than showing an empty frame.
    @State private var document: PDFDocument?
    @State private var loading = true
    /// The page on screen, 1-based as printed.
    @State private var showing = 1

    private var book: BookDoc? {
        (state.manifest?.books ?? []).first { $0.slug == slug }
    }

    private var pages: Int? {
        document.map { $0.pageCount } ?? book?.pages
    }

    private var range: (from: Int, to: Int)? {
        BookPages.range(from: fromPage, to: toPage, pages: pages)
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
                BandHeader("Look through it")
                browser
                BandHeader("Take an arrangement out")
                form
            }
            .padding(.bottom, Theme.Metric.s32)
        }
        .task(id: slug) { await open() }
    }

    // MARK: looking through it

    @ViewBuilder
    private var browser: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.s12) {
            if let document, let pages, pages > 0 {
                BookPageView(document: document, index: showing - 1)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("book-page")
                    .accessibilityLabel(BookPages.label(page: showing, pages: pages))
                pager(pages)
                BookThumbnails(document: document, showing: showing,
                               chosen: { BookPages.isChosen($0, from: fromPage,
                                                            to: toPage, pages: pages) },
                               onJump: { showing = $0 })
                markers(pages)
            } else if loading {
                PanelNote(text: "Opening the book…")
                    .accessibilityIdentifier("book-loading")
            } else {
                // A book that will not open is not a reason to take the
                // feature away: the fields below still work, and someone who
                // knows the page numbers can still use them.
                PanelNote(text: "This book's pages could not be opened here, so "
                          + "the page numbers below have to be typed.")
                    .accessibilityIdentifier("book-unopenable")
            }
        }
        .padding(Theme.Metric.panelPadding)
    }

    private func pager(_ pages: Int) -> some View {
        HStack(spacing: Theme.Metric.s8) {
            step("chevron.left", label: "Previous page", id: "book-prev",
                 enabled: showing > 1) { showing = BookPages.clamp(showing - 1, pages: pages) }
            step("chevron.right", label: "Next page", id: "book-next",
                 enabled: showing < pages) { showing = BookPages.clamp(showing + 1, pages: pages) }
            Text(BookPages.label(page: showing, pages: pages))
                .typeRole(.data)
                .foregroundStyle(Theme.Ink.ink2)
                .accessibilityIdentifier("book-page-label")
            Spacer(minLength: 0)
        }
    }

    /// The two presses that fill the fields in, and what they have chosen so
    /// far said as a sentence — two numbers in two boxes do not read as a span.
    private func markers(_ pages: Int) -> some View {
        HStack(spacing: Theme.Metric.s8) {
            PanelButton(title: "Starts here", kind: .normal) {
                (fromPage, toPage) = BookPages.starting(at: showing, from: fromPage,
                                                        to: toPage)
            }
            .accessibilityIdentifier("book-starts-here")
            PanelButton(title: "Ends here", kind: .normal) {
                (fromPage, toPage) = BookPages.ending(at: showing, from: fromPage,
                                                      to: toPage)
            }
            .accessibilityIdentifier("book-ends-here")
            if let range {
                Text("Taking \(BookPages.summary(from: range.from, to: range.to))")
                    .typeRole(.meta)
                    .foregroundStyle(Theme.Ink.ink3)
                    .accessibilityIdentifier("book-range-summary")
            }
            Spacer(minLength: 0)
        }
    }

    private func step(_ glyph: String, label: String, id: String,
                      enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph).font(.system(size: 13))
                .foregroundStyle(enabled ? Theme.Ink.ink : Theme.Ink.ink3)
                .frame(width: 32, height: 32)
                .background(Theme.Surface.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(Theme.Line.line2, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
    }

    // MARK: taking one out

    private var form: some View {
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
        // A typed page turns the book to it. The field is still the field --
        // this is the other half of "Starts here", not a replacement for it.
        .onChange(of: fromPage) { _, typed in follow(typed) }
        .onChange(of: toPage) { _, typed in follow(typed) }
    }

    private func follow(_ typed: String) {
        guard let pages, let page = BookPages.page(inField: typed, pages: pages) else { return }
        showing = page
    }

    private func open() async {
        loading = true
        document = await state.bookDocument(slug)
        loading = false
        if let pages, pages > 0 { showing = BookPages.clamp(showing, pages: pages) }
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

/// One page of the book, big enough to read a tune's title off.
///
/// Rastered through `ThumbnailCache` like every other page picture in the app,
/// and — since a fake book is four hundred pages of scan — rastered OFF the
/// main thread. See `PageImage`.
private struct BookPageView: View {
    let document: PDFDocument
    let index: Int

    /// Tall enough to read a title and a first line at arm's length, short
    /// enough that the fields below it are still on screen without scrolling.
    private static let height: CGFloat = 420

    var body: some View {
        let size = drawnSize()
        PageImage(document: document, index: index, drawn: size,
                  // Twice the points drawn, because `PDFPage.thumbnail`
                  // answers at scale 1 and this is a retina display.
                  raster: CGSize(width: size.width * 2, height: size.height * 2),
                  interpolation: .high) { phase in
            PageThumb(width: size.width, height: size.height)
                .overlay {
                    if phase == .missing {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.Status.warn)
                    }
                }
                .accessibilityIdentifier(phase == .missing ? "book-page-failed"
                                                           : "book-page-drawing")
        }
        .background(Theme.Surface.paper)
        .overlay { Rectangle().stroke(Theme.Line.line2, lineWidth: 1) }
        .frame(maxWidth: .infinity)
    }

    /// The page's own shape, at the height there is room for. A fake book is
    /// not always portrait and a picture stretched to a fixed box is unreadable
    /// where it is not.
    private func drawnSize() -> CGSize {
        let bounds = document.page(at: index)?.bounds(for: .mediaBox)
            ?? CGRect(x: 0, y: 0, width: 8.5, height: 11)
        let ratio = bounds.height > 0 ? bounds.width / bounds.height : 0.77
        return CGSize(width: Self.height * ratio, height: Self.height)
    }
}

/// A page as a picture, drawn off the main thread and abandoned when the
/// reader moves on.
///
/// Used by the book browser and by the score's own thumbnail strip
/// (`ScoreFooter`), which had the same fault and is fixed by the same view
/// rather than by a second copy of this reasoning.
///
/// This is the fix for "too slow to scroll a big book". The picture used to be
/// made INSIDE the view body: `ThumbnailCache.shared.image(...)` rasterises a
/// PDF page on whatever thread asks, and the thread asking was the main one.
/// A lazy strip builds a cell for every page a flick passes over, so a flick
/// across a 512-page book stopped the main thread once per page — and there
/// was nothing to call off, because the drawing WAS the view.
///
/// So: ask the cache what it already holds, which is a dictionary lookup and
/// free; and only when it holds nothing, queue the raster and wait. `.task` is
/// cancelled when the cell leaves the strip, which cancels the operation, and
/// one that has not started never rasterises at all.
///
/// The placeholder is told WHY it is being shown. A page not drawn yet and a
/// page that cannot be drawn are two different problems, and with cancellation
/// the first one is the ordinary outcome of a flick — so the warning triangle
/// belongs to `.missing` alone.
struct PageImage<Placeholder: View>: View {
    let document: PDFDocument
    let index: Int
    /// Where it is drawn, in points.
    let drawn: CGSize
    /// What it is rastered at, in pixels.
    let raster: CGSize
    let interpolation: Image.Interpolation
    @ViewBuilder let placeholder: (PageThumbnails.Phase) -> Placeholder

    @State private var image: UIImage?
    @State private var phase: PageThumbnails.Phase = .pending

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().interpolation(interpolation)
            } else {
                placeholder(phase)
            }
        }
        .frame(width: drawn.width, height: drawn.height)
        // The key names the document, the page AND the size, so a cell that
        // changes any of them asks again and one that changes none does not.
        .task(id: ThumbnailCache.key(document: document, index: index, size: raster)) {
            if let held = ThumbnailCache.shared.cached(document: document,
                                                       index: index, size: raster) {
                image = held
                phase = .drawn
                return
            }
            image = nil
            phase = .pending
            let made = await ThumbnailCache.shared.request(document: document,
                                                           index: index, size: raster)
            phase = PageThumbnails.phase(drew: made != nil, abandoned: Task.isCancelled)
            image = phase == .drawn ? made : nil
        }
    }
}

/// The strip under the page: every page in the book, lazily.
///
/// Lazy, so a four-hundred-page book builds the dozen thumbnails on screen and
/// not four hundred — the same rule the score's own strip learned. The pages
/// inside the chosen range are marked, so a span reads as a span.
private struct BookThumbnails: View {
    let document: PDFDocument
    let showing: Int
    let chosen: (Int) -> Bool
    var onJump: (Int) -> Void

    /// The cell, in points, and the raster it needs on a retina display.
    private static let cell = CGSize(width: 52, height: 68)
    private static let raster = CGSize(width: 104, height: 136)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Metric.s8) {
                    ForEach(0..<document.pageCount, id: \.self) { index in
                        thumb(index)
                    }
                }
                .padding(.vertical, Theme.Metric.s8)
            }
            .onChange(of: showing) { _, page in
                withAnimation { proxy.scrollTo(page - 1, anchor: .center) }
            }
        }
        .frame(height: Theme.Metric.thumbStripHeight)
        .background(Theme.Surface.panel)
        .overlay { Rectangle().stroke(Theme.Line.line, lineWidth: 1) }
        .accessibilityIdentifier("book-thumbnails")
    }

    private func thumb(_ index: Int) -> some View {
        let page = index + 1
        let isShowing = page == showing
        let inRange = chosen(page)
        return Button { onJump(page) } label: {
            ZStack(alignment: .bottomTrailing) {
                PageImage(document: document, index: index, drawn: Self.cell,
                          raster: Self.raster, interpolation: .medium) { phase in
                    PageThumb(width: Self.cell.width, height: Self.cell.height)
                        .overlay {
                            if phase == .missing {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.Status.warn)
                            }
                        }
                }
                .background(Theme.Surface.paper)
                Text("\(page)").typeRole(.data)
                    .foregroundStyle(Theme.Ink.ink3)
                    .padding(2)
            }
            .background(inRange ? Theme.Accent.clayTint : Color.clear)
            .overlay {
                Rectangle()
                    .stroke(isShowing ? Theme.Accent.clay
                            : (inRange ? Theme.Accent.clayStrong : Theme.Line.line2),
                            lineWidth: isShowing ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(index)
        .accessibilityIdentifier("book-thumb-\(page)")
        .accessibilityLabel("Page \(page)")
        .accessibilityAddTraits(inRange ? [.isButton, .isSelected] : [.isButton])
    }
}
