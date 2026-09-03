import Foundation

/// Choosing a page range out of a book by LOOKING at it.
///
/// A book is a fake book or a method book: four hundred pages, one tune every
/// page or two, and the only way to say which tune you want is a page range.
/// The screen used to ask for that range as two numbers and show nothing, so
/// finding "Misty" in four hundred pages meant guessing — type 137, extract,
/// open it, find it is "Moonglow", delete it, guess again.
///
/// So the pages are on screen, and the two numbers are set by pressing a
/// button on the page you are looking at. The fields stay: a reader who knows
/// the page number still types it, and typing still moves the page under it.
/// Everything below is the arithmetic that keeps the two in step, kept out of
/// the view so it can be tested — ios/ScorangerTests/BookPagesTests.swift.
enum BookPages {

    /// A page number as printed: 1-based, and never off the ends of the book.
    static func clamp(_ page: Int, pages: Int) -> Int {
        guard pages > 0 else { return 1 }
        return min(max(page, 1), pages)
    }

    /// The range the two fields name, or nil when they do not name one.
    ///
    /// Both must be numbers, inside the book, and in order. Stated here so the
    /// button can say whether it will work before it is pressed — the engine
    /// refuses a bad range, but a disabled button is a better answer than an
    /// error.
    static func range(from: String, to: String, pages: Int?) -> (from: Int, to: Int)? {
        guard let pages,
              let first = number(from), let last = number(to),
              first >= 1, last <= pages, first <= last else { return nil }
        return (first, last)
    }

    /// A page number typed into a field, or nil for anything that is not one.
    static func number(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespaces))
    }

    /// The page a typed field is pointing at, for the viewer to follow. nil
    /// when the field says nothing that names a page.
    static func page(inField text: String, pages: Int) -> Int? {
        guard let typed = number(text), typed >= 1, typed <= pages else { return nil }
        return typed
    }

    /// "Starts here": the page you are looking at becomes the first page.
    ///
    /// The last page follows it when it would otherwise be behind it or unset,
    /// so a one-page tune is one press rather than two.
    static func starting(at page: Int, from: String, to: String)
        -> (from: String, to: String) {
        let last = number(to)
        return ("\(page)", (last == nil || last! < page) ? "\(page)" : to)
    }

    /// "Ends here": the page you are looking at becomes the last page, and the
    /// first follows it the same way.
    static func ending(at page: Int, from: String, to: String)
        -> (from: String, to: String) {
        let first = number(from)
        return ((first == nil || first! > page) ? "\(page)" : from, "\(page)")
    }

    /// Whether a page is inside the range the fields name. What the viewer
    /// marks, so the chosen span is visible as a span rather than as two
    /// numbers in two boxes.
    static func isChosen(_ page: Int, from: String, to: String, pages: Int?) -> Bool {
        guard let range = range(from: from, to: to, pages: pages) else { return false }
        return page >= range.from && page <= range.to
    }

    /// What the reader is looking at, said in full. "Page 137 of 420" rather
    /// than "137": the second number is the whole reason the first one is hard
    /// to guess.
    static func label(page: Int, pages: Int) -> String {
        "Page \(page) of \(pages)"
    }

    /// How many pages a range covers, for the sentence under the button.
    static func summary(from: Int, to: Int) -> String {
        from == to ? "page \(from)" : "pages \(from)–\(to) (\(to - from + 1) pages)"
    }
}
