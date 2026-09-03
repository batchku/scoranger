import PDFKit
import UIKit

/// Page thumbnails for the strip, rendered once each.
///
/// The strip used to draw only the six pages either side of the one you were
/// on and leave the rest as empty placeholders -- so a nine-page score showed
/// seven pages and two blanks, which reads as a broken render rather than as
/// a deliberate budget. The budget was real: the strip is a plain HStack, so
/// every thumbnail was built on every pass, and re-rasterising sixty pages per
/// pass is what §9.7 was avoiding.
///
/// Two changes make the window unnecessary. The strip is lazy, so only the
/// thumbnails on screen are built at all; and each one is rasterised ONCE and
/// kept here, so scrolling back over a page costs a dictionary lookup.
///
/// `NSCache` rather than a dictionary: these are images, and the system is
/// entitled to take them back under pressure -- when it does, the thumbnail
/// simply renders again.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let images = NSCache<NSString, UIImage>()

    /// One token per document, minted on first sight and dropped when the
    /// document is.
    ///
    /// The key used to be the document's ADDRESS. An address is only unique
    /// among documents that are alive at the same time, and these are not: a
    /// new engraving is made on every render and the previous one is released,
    /// so the next `PDFDocument` can land on the address the last one had --
    /// and inherit a whole score's worth of its thumbnails. The strip is what
    /// made the pictures unreadable; this is what could make them the wrong
    /// score's.
    ///
    /// Weak keys, so a document that goes away takes its token with it and the
    /// table cannot grow without bound.
    private let tokens = NSMapTable<PDFDocument, NSString>.weakToStrongObjects()
    private var nextToken = 0
    private let lock = NSLock()

    private init() {
        // A page thumb is about 30KB. Two hundred of them is a long score's
        // worth and still small; past that the system decides.
        images.countLimit = 200
    }

    /// A key that cannot collide between documents: two scores both have a
    /// page 1, and they do not look alike. Nor can a document inherit the key
    /// of one that has been released.
    static func key(document: PDFDocument, index: Int) -> String {
        "\(shared.token(for: document))#\(index)"
    }

    private func token(for document: PDFDocument) -> String {
        lock.lock()
        defer { lock.unlock() }
        if let existing = tokens.object(forKey: document) { return existing as String }
        nextToken += 1
        let minted = "d\(nextToken)" as NSString
        tokens.setObject(minted, forKey: document)
        return minted as String
    }

    func image(document: PDFDocument, index: Int, size: CGSize) -> UIImage? {
        let key = Self.key(document: document, index: index) as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let page = document.page(at: index) else { return nil }
        let span = PerfMetrics.shared.begin(PerfMetrics.Name.thumbnail)
        let drawn = page.thumbnail(of: size, for: .mediaBox)
        span?.end()
        images.setObject(drawn, forKey: key)
        return drawn
    }

    func clear() { images.removeAllObjects() }
}
