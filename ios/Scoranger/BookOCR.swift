import PDFKit
import UIKit
import Vision

/// The lines on a scanned book page, read with Apple Vision on the device.
///
/// A scan has no text layer, so `book-detect` cannot see its titles; it names
/// such pages in `needs_ocr` and this reads them. What comes back is only the
/// geometry the engine's heading rule needs -- each line's text, its top and
/// left edges and its height, as fractions of the page -- because the JUDGING
/// stays in the engine (booksplit.py), where one rule serves a vector PDF and
/// a photographed one and is proven in check_book_split.py.
///
/// On device and offline: nothing leaves the iPad.
enum BookOCR {
    /// Long edge of the raster Vision reads, in pixels. On the Comhaltas San
    /// Diego tunebook read at 1100 (100 dpi) every title was found; the
    /// small page numbers mostly were not, which the engine's contents-page
    /// rule is written not to need.
    static let rasterLongEdge: CGFloat = 1600

    /// `{page: [{text, top, height, left}]}` for the given 1-based pages, in
    /// the shape `book-detect` takes as `ocr`. A page that cannot be drawn or
    /// read comes back with no lines, so the engine counts it as read and
    /// treats it as a page with no heading, rather than asking again forever.
    static func read(pages: [Int], of document: PDFDocument,
                     progress: @escaping (Int, Int) -> Void) async -> [String: [[String: Any]]] {
        var out: [String: [[String: Any]]] = [:]
        for (done, number) in pages.enumerated() {
            if Task.isCancelled { break }
            out[String(number)] = await lines(on: document.page(at: number - 1))
            progress(done + 1, pages.count)
        }
        return out
    }

    private static func lines(on page: PDFPage?) async -> [[String: Any]] {
        guard let page else { return [] }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return [] }
        let scale = rasterLongEdge / max(bounds.width, bounds.height)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard let image = page.thumbnail(of: size, for: .mediaBox).cgImage else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // Tune titles are names -- "Sí Bheag Sí Mhór", "Cooley's" -- and a
            // spelling corrector would "fix" them.
            request.usesLanguageCorrection = false
            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                return []
            }
            return (request.results ?? []).compactMap { obs -> [String: Any]? in
                guard let text = obs.topCandidates(1).first?.string else { return nil }
                let box = obs.boundingBox   // normalised, origin bottom-left
                return ["text": text, "top": 1 - box.minY,
                        "height": box.height, "left": box.minX]
            }
        }.value
    }
}
