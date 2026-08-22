import CoreGraphics
import Foundation
import PDFKit
import UIKit

/// Prepares a PDF for optical music recognition.
///
/// Audiveris expects what a scanner produces: a raster page at roughly letter
/// size and roughly 300 DPI. Two things that come out of notation software
/// break that expectation:
///
/// * **Oversized pages.** MuseScore will happily export a 2976 x 4209 pt page
///   (41 x 58 inches). Audiveris rasterizes internally at a fixed resolution,
///   so a page that size becomes a ~12000 px wide image whose staff-line
///   spacing is nowhere near what its scale detection expects. It gives up,
///   and the service reports that it could not read the PDF as a score.
/// * **Born-digital vector notation.** Crisp bezier noteheads with no raster
///   layer at all. Audiveris can cope, but only after rasterizing them itself
///   at whatever resolution the page size implies — which is the same trap.
///
/// So the page is re-rendered here: fitted to letter, drawn at 300 DPI, and
/// handed over as an ordinary raster page. Scans, which already look the way
/// OMR wants, are passed through untouched.
enum PDFPreflight {
    /// Letter at 300 DPI — the shape of a scanned page.
    static let targetDPI: CGFloat = 300
    static let targetPageSize = CGSize(width: 612, height: 792)   // points
    /// Anything meaningfully larger than A4 is treated as oversized.
    static let oversizeThreshold: CGFloat = 1.15 * 842

    struct Result {
        let data: Data
        /// What was done and why, for the log and for an error message. nil
        /// when the PDF was already in good shape and was passed through.
        let note: String?
    }

    /// Why this PDF needs re-rendering, if it does.
    static func reasonToNormalize(_ document: PDFDocument) -> String? {
        guard let page = document.page(at: 0) else { return nil }
        let box = page.bounds(for: .mediaBox)
        let longest = max(box.width, box.height)
        if longest > oversizeThreshold {
            return String(format: "pages are %.0f x %.0f pt (%.0f x %.0f inches)",
                          box.width, box.height, box.width / 72, box.height / 72)
        }
        // A text layer means the notation was typeset, not scanned. An OCR'd
        // scan also has one, but re-rendering that at 300 DPI costs nothing.
        if !(page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "the notation is vector, not a scan"
        }
        return nil
    }

    /// Returns a PDF that OMR can work with, and a note when anything changed.
    static func prepare(_ data: Data) -> Result {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            return Result(data: data, note: nil)
        }
        guard let reason = reasonToNormalize(document) else {
            return Result(data: data, note: nil)
        }
        guard let rendered = rasterize(document) else {
            return Result(data: data, note: nil)
        }
        return Result(data: rendered,
                      note: "rendered \(document.pageCount) page"
                          + (document.pageCount == 1 ? "" : "s")
                          + " to \(Int(targetDPI)) DPI for OMR (\(reason))")
    }

    /// Every page, fitted to letter and drawn at `targetDPI`.
    private static func rasterize(_ document: PDFDocument) -> Data? {
        let format = UIGraphicsPDFRendererFormat()
        let pageRect = CGRect(origin: .zero, size: targetPageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let scale = targetDPI / 72

        let data = renderer.pdfData { context in
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                context.beginPage()
                let box = page.bounds(for: .mediaBox)
                guard box.width > 0, box.height > 0 else { continue }

                // the page, scaled to fit letter and centred on it
                let fit = min(pageRect.width / box.width, pageRect.height / box.height)
                let drawn = CGSize(width: box.width * fit, height: box.height * fit)
                let origin = CGPoint(x: (pageRect.width - drawn.width) / 2,
                                     y: (pageRect.height - drawn.height) / 2)

                guard let bitmap = image(of: page, box: box,
                                         pixelSize: CGSize(width: drawn.width * scale,
                                                           height: drawn.height * scale))
                else { continue }
                bitmap.draw(in: CGRect(origin: origin, size: drawn))
            }
        }
        return data.isEmpty ? nil : data
    }

    /// One page as a bitmap. Drawn on white: OMR reads ink on paper, and a
    /// transparent background composites as black in some encoders.
    private static func image(of page: PDFPage, box: CGRect,
                              pixelSize: CGSize) -> UIImage? {
        guard pixelSize.width >= 1, pixelSize.height >= 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(origin: .zero, size: pixelSize))
            cg.saveGState()
            // PDF origin is bottom-left; UIKit's is top-left
            cg.translateBy(x: 0, y: pixelSize.height)
            cg.scaleBy(x: pixelSize.width / box.width, y: -pixelSize.height / box.height)
            cg.translateBy(x: -box.minX, y: -box.minY)
            page.draw(with: .mediaBox, to: cg)
            cg.restoreGState()
        }
    }

    /// A failure the user can act on. The service says what Audiveris did;
    /// this adds what it means and what to try, and what preflight already
    /// tried on the way out.
    static func advice(name: String, error: Error, preflight: String?) -> String {
        let raw = error.localizedDescription
        var lines = ["PDF conversion of “\(name)” failed: \(raw)"]
        if raw.localizedCaseInsensitiveContains("could not read this PDF") {
            lines.append("")
            lines.append("Audiveris reads scans of printed music. Scores exported "
                         + "straight from notation software often defeat it, and so "
                         + "do pages far larger than A4.")
            lines.append(preflight.map { "Scoranger already \($0), and it still failed." }
                         ?? "The page looked like a normal scan, so it was sent as-is.")
            lines.append("Worth trying: export MusicXML from the program that made "
                         + "the PDF and import that instead — it needs no recognition "
                         + "at all. Otherwise export the PDF at A4 or Letter, or scan "
                         + "the printed page at 300 DPI.")
        } else if raw.localizedCaseInsensitiveContains("timed out") {
            lines.append("")
            lines.append("The score was too long or too dense to finish in time. "
                         + "Try importing fewer pages at once.")
        }
        return lines.joined(separator: "\n")
    }
}
