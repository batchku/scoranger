import UIKit

/// A picture of a page, turned into something the score view already knows.
///
/// Ali brings scores in as JPEGs and PNGs as well as PDFs. The whole design is
/// that an image takes the PDF's path rather than a parallel one -- and the
/// score view draws PDFs. PDFKit, the paged canvas, page turns, the thumbnail
/// strip, Pencil markup, export: every one of those would need an image
/// variant if the image stayed an image on screen, and each would be a second
/// place for the two to drift apart.
///
/// So it does not stay an image. This wraps it in a single-page PDF at the
/// boundary and everything downstream is untouched. The same helper feeds
/// OMR, which posts `Content-Type: application/pdf`, so the service needs no
/// work either -- that is what made this the clean path rather than teaching
/// six drawing surfaces about images.
///
/// **The artifact stays the original image.** This is a RENDERING, made on
/// demand and never written to the library, which is what "viewable as-is"
/// has to mean: the bytes on disk are the file the reader gave us, and OMR
/// later reads that file rather than a re-encoding of it.
enum ScanImage {

    /// The bytes the score view should draw, for an artifact of this kind.
    ///
    /// A PDF goes through untouched. Re-wrapping one would flatten a
    /// multi-page score into a single page, which is a bug sitting right next
    /// to the one this feature is about, and the test says so.
    static func displayable(_ data: Data, kind: ScoreArtifact.Kind) -> Data? {
        kind == .image ? pdf(from: data) : data
    }

    /// One image, one page, at the image's own proportions.
    ///
    /// The page IS the image rather than the image placed on paper. A
    /// photograph of a chart is not A4, and letterboxing it on to a page size
    /// would put white margins round the reader's music and shrink the notes
    /// to pay for them.
    ///
    /// Nil for bytes that are not an image, rather than a blank page: a blank
    /// page in the library is indistinguishable from a score that failed to
    /// load, and the reader would have no way to tell which they had.
    static func pdf(from data: Data) -> Data? {
        guard !data.isEmpty, let image = UIImage(data: data),
              image.size.width > 0, image.size.height > 0 else { return nil }
        // In POINTS, from the image's pixel size and its own scale, so a
        // photograph taken at 3x does not become a page three times the size
        // of the same picture taken at 1x.
        let size = CGSize(width: image.size.width, height: image.size.height)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero,
                                                            size: size))
        return renderer.pdfData { context in
            context.beginPage()
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
