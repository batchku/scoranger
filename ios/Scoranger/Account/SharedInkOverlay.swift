import PencilKit
import SwiftUI

/// Everybody else's marks, drawn under my own.
///
/// Principle 5 of design/FIREBASE.md §0, the visible half. My own layer is the
/// `PKCanvasView` that already exists and takes the pencil; this draws the
/// other participants' layers beneath it, each in that person's own colour.
///
/// **Read-only, and it has to be.** A second canvas that could take a touch
/// would let somebody draw into a layer that is not theirs, which is the one
/// thing the whole ink design rests on not happening. So each layer is
/// rendered to an image and the whole overlay refuses hit testing.
///
/// Two transforms, and both are corrections rather than styling:
///
///   - **scale**, because a `PKDrawing`'s coordinates are in its canvas's
///     unzoomed space and this app lays that canvas out at the page's layout
///     width in points. An iPad's marks on a phone would otherwise pile into
///     the corner at a third size (`SharedInk.scale`).
///   - **colour**, because two people's black ink on one page is unreadable and
///     nobody can tell whose cue is whose. `PKStroke.ink` is reassigned on a
///     copy; the stored layer is never modified.
struct SharedInkOverlay: View {
    let layers: [SharedInk.Layer]
    let pageSize: CGSize

    var body: some View {
        ZStack {
            ForEach(layers.filter { !$0.isMine }, id: \.userId) { layer in
                if let image = Self.image(layer, pageSize: pageSize) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: pageSize.width, height: pageSize.height)
                }
            }
        }
        .frame(width: pageSize.width, height: pageSize.height)
        // Not negotiable: see the type's note.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One layer as a picture of itself, recoloured and scaled onto this
    /// device's page.
    ///
    /// Returns nil rather than an empty image for a layer that will not
    /// decode: a document written by a later build with a format this one
    /// cannot read must show nothing and log nothing, not a blank rectangle
    /// over the music.
    static func image(_ layer: SharedInk.Layer, pageSize: CGSize) -> UIImage? {
        guard pageSize.width > 0, pageSize.height > 0,
              let drawing = try? PKDrawing(data: layer.data) else { return nil }
        let recoloured = recolour(drawing, to: layer.colour)
        let placed = layer.scale == 1
            ? recoloured
            : recoloured.transformed(using: CGAffineTransform(scaleX: layer.scale,
                                                              y: layer.scale))
        let page = CGRect(origin: .zero, size: pageSize)
        // `from:` is a crop, not a fit: the drawing keeps its own coordinates
        // and anything outside the page is cut. Scaling it to fit instead
        // would move every mark relative to the notes it annotates, which is
        // the one thing markup cannot survive.
        return placed.image(from: page, scale: UIScreen.main.scale)
    }

    /// Every stroke in one person's colour.
    ///
    /// The width and the path are theirs; only the colour is this device's
    /// decision. `PKInk(.pen, ...)` rather than preserving their tool because
    /// a highlighter recoloured is a different mark -- and because a bandmate's
    /// cue is being shown as a bandmate's cue, not reproduced exactly.
    static func recolour(_ drawing: PKDrawing, to rgb: UInt32) -> PKDrawing {
        let colour = UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                             green: CGFloat((rgb >> 8) & 0xFF) / 255,
                             blue: CGFloat(rgb & 0xFF) / 255,
                             alpha: 1)
        return PKDrawing(strokes: drawing.strokes.map { stroke in
            var recoloured = stroke
            recoloured.ink = PKInk(stroke.ink.inkType == .marker ? .marker : .pen,
                                   color: colour)
            return recoloured
        })
    }
}
