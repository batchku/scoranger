import CoreGraphics
import Foundation

/// One person's markup on one shared set list entry, as it travels.
///
/// Principle 5 of design/FIREBASE.md §0: *"What's shared must include
/// ANNOTATIONS ... and ALL participants can annotate."* §6.3 is how, and the
/// whole design is one sentence: **each participant writes only their own
/// layer.** Nobody ever writes anybody else's, so there is no merge function
/// anywhere in this system and no CRDT -- the conflict is impossible rather
/// than resolved. The security rules enforce it (`ink/{userId}` writable only
/// by that uid), which is what makes it true against a modified client.
///
/// This type is the part with arithmetic in it: what one document holds, and
/// whether it fits.
enum SharedInk {

    /// Firestore's hard limit on a document, bytes.
    ///
    /// 1 MiB, and it is not negotiable or extendable. It matters here because
    /// a person's ink for a whole arrangement is ONE document -- pages inside
    /// it -- and §11.6 recorded that fitting inside this was an assumption
    /// nobody had measured. `SharedInkSizeTests` measures it.
    static let documentLimit = 1_048_576

    /// Headroom left for the document's own fields and Firestore's overhead.
    ///
    /// Firestore counts field names, the document path and per-field type
    /// bytes toward the limit, not just the values, so a payload budget equal
    /// to the limit is a document that fails at 100%. Eight per cent of a MiB
    /// is far more than the handful of short field names here need, and being
    /// generous costs nothing: a page of dense markup measures two orders of
    /// magnitude below either number.
    static let payloadBudget = documentLimit * 92 / 100

    /// Whether a set of pages fits in one document.
    static func fits(_ pages: [Int: Data]) -> Bool {
        size(of: pages) <= payloadBudget
    }

    static func size(of pages: [Int: Data]) -> Int {
        pages.values.reduce(0) { $0 + $1.count }
    }

    /// The pages of a layer that will not fit, largest first.
    ///
    /// Reported rather than silently dropped. A person who has covered forty
    /// pages in ink has to be told which ones are not reaching the band, and
    /// which pages those are is the only useful thing to say.
    static func pagesOverBudget(_ pages: [Int: Data]) -> [Int] {
        var running = 0
        var over: [Int] = []
        // Lowest page first, so the ones that fit are the ones at the front of
        // the score -- which is where a rehearsal starts.
        for page in pages.keys.sorted() {
            let bytes = pages[page]?.count ?? 0
            if running + bytes > payloadBudget {
                over.append(page)
            } else {
                running += bytes
            }
        }
        return over
    }

    // MARK: - the wire form

    /// Page numbers are STRINGS in the document, because a Firestore map's keys
    /// are strings and an integer key would come back as `"3"` anyway. Encoded
    /// and decoded in one place so the two directions cannot disagree.
    static func encode(_ pages: [Int: Data]) -> [String: Data] {
        Dictionary(uniqueKeysWithValues: pages.map { (String($0.key), $0.value) })
    }

    /// Decode, dropping anything whose key is not a page number.
    ///
    /// Dropping rather than failing: a document written by a future build with
    /// an extra key must not make an older build unable to read the pages it
    /// does understand.
    static func decode(_ raw: [String: Any]) -> [Int: Data] {
        var pages: [Int: Data] = [:]
        for (key, value) in raw {
            guard let page = Int(key), page >= 0, let data = value as? Data
            else { continue }
            pages[page] = data
        }
        return pages
    }

    // MARK: - what gets drawn, and in what order

    // MARK: - the page a mark was drawn on

    /// A `PKDrawing`'s coordinates are in its canvas's own unzoomed space, and
    /// this app lays that canvas out at the PAGE'S LAYOUT WIDTH IN POINTS --
    /// about 900 on a 13-inch iPad, about 350 on a phone. So the same circled
    /// accidental is a different pair of numbers on each device, and ink
    /// shipped as-is lands in the wrong place by the ratio of the two widths:
    /// on a phone, an iPad's marks would pile into the top-left corner at a
    /// third scale.
    ///
    /// Nothing about this shows up on one device, which is why it is written
    /// down here: locally the width never changes, so the bug is invisible
    /// until a second device reads the same layer. It cost nothing to find and
    /// would have cost a release to find later.
    ///
    /// So a shared layer carries the width it was drawn at, and the reader
    /// scales by the ratio. A width the writer failed to record is treated as
    /// the reader's own -- ink at slightly the wrong scale beats ink that
    /// vanishes.
    static func scale(drawnAt written: CGFloat?, readAt reading: CGFloat) -> CGFloat {
        guard let written, written > 0, written.isFinite,
              reading > 0, reading.isFinite else { return 1 }
        return reading / written
    }

    /// One participant's layer, ready to draw.
    struct Layer: Equatable {
        let userId: String
        let data: Data
        /// From `InkLayers.palette`, so the same person is the same colour on
        /// everybody's device with no stored assignment.
        let colour: UInt32
        /// Mine is drawn last and is the only one that takes a pencil.
        let isMine: Bool
        /// What to multiply this layer's coordinates by before drawing it
        /// here. 1 for my own, always.
        let scale: CGFloat
    }

    /// Everybody's ink for one page, bottom to top.
    ///
    /// `InkLayers.drawOrder` decides WHOSE, and puts mine last; this attaches
    /// each one's colour and its bytes. Mine being last is not cosmetic: it is
    /// the layer being drawn into, and ink appearing beneath somebody else's
    /// scribble as you write it reads as the pencil failing.
    static func layers(page: Int,
                       byUser: [String: [Int: Data]],
                       widths: [String: CGFloat] = [:],
                       readAt pageWidth: CGFloat = 0,
                       me: String,
                       visibility: InkLayers.Visibility,
                       participants: [String]) -> [Layer] {
        InkLayers.drawOrder(visibility: visibility, me: me,
                            participants: participants)
            .compactMap { userId in
                guard let data = byUser[userId]?[page], !data.isEmpty else { return nil }
                let slot = InkLayers.colourSlot(for: userId,
                                                participants: participants,
                                                slots: InkLayers.palette.count)
                let mine = userId == me
                return Layer(userId: userId, data: data,
                             colour: InkLayers.colour(slot: slot),
                             isMine: mine,
                             // My own layer is never rescaled: it is drawn in
                             // this device's own space and re-scaling it would
                             // move a mark under the pencil that made it.
                             scale: mine ? 1 : scale(drawnAt: widths[userId],
                                                     readAt: pageWidth))
            }
    }
}
