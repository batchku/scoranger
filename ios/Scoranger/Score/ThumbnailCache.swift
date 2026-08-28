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

    private init() {
        // A page thumb is about 30KB. Two hundred of them is a long score's
        // worth and still small; past that the system decides.
        images.countLimit = 200
    }

    /// A key that cannot collide between documents: two scores both have a
    /// page 1, and they do not look alike.
    static func key(document: PDFDocument, index: Int) -> String {
        "\(UInt(bitPattern: ObjectIdentifier(document).hashValue))#\(index)"
    }

    func image(document: PDFDocument, index: Int, size: CGSize) -> UIImage? {
        let key = Self.key(document: document, index: index) as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let page = document.page(at: index) else { return nil }
        let drawn = page.thumbnail(of: size, for: .mediaBox)
        images.setObject(drawn, forKey: key)
        return drawn
    }

    func clear() { images.removeAllObjects() }
}
