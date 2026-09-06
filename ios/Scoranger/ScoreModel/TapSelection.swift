import CoreGraphics

/// What a tap on the canvas means, and where the loupe goes.
///
/// IPHONE_0.6.14 §9.1 and §9.2. Pure, and separate from the canvas, because
/// both are DECISIONS -- which granularity a scale implies, where a magnifier
/// belongs relative to a finger -- while the canvas is the wiring that carries
/// them out. `selectBar` and `addToSelection` already exist in `AppState`;
/// what did not exist is the rule for choosing between them.
enum TapSelection {

    /// What one tap selects.
    enum Granularity: Equatable {
        /// The bar under the tap, on the staff under the tap.
        case measure
        /// The single element under the tap.
        case note
    }

    /// Below this a tap means a bar; at it and above, a note.
    ///
    /// Not arbitrary: it is the granularity that is both legible and hittable
    /// at that scale. At fit a notehead is about 3.9pt against a 25pt
    /// fingertip -- unhittable -- while a bar is a comfortable target. At 2x
    /// the notehead is 7.8pt and the loupe closes the rest of the gap.
    ///
    /// The boundary belongs to `note`: a reader who has zoomed to exactly 2x
    /// has asked for the finer thing.
    static let noteZoom: CGFloat = 2

    /// The rule, with §9.1's first override folded in: tapping a bar that is
    /// ALREADY selected drills into it and takes the note nearest the tap, at
    /// any zoom. That is the way to a note without zooming, and it is why the
    /// rule needs no mode and no second control.
    static func granularity(atZoom zoom: CGFloat,
                            onSelected: Bool = false) -> Granularity {
        if onSelected { return .note }
        return zoom >= noteZoom ? .note : .measure
    }

    // MARK: - The loupe (§9.2)

    /// The circle's diameter, and how far its centre sits from the touch.
    ///
    /// Zoom fixes resolution; it does not fix the finger covering the thing
    /// being selected, and no amount of zoom will. This is the pattern every
    /// iOS reader knows from text selection.
    static let loupeSize: CGFloat = 96
    static let loupeOffset: CGFloat = 88
    /// Nearer than this to the safe area and it would be drawn under the
    /// status bar and the top bar, so it flips below the touch instead.
    static let loupeFlipMargin: CGFloat = 100

    struct Loupe: Equatable {
        /// Where the circle is drawn.
        let centre: CGPoint
        /// The point under the finger, which the crosshair marks and release
        /// commits. NOT the circle's centre -- release commits what the
        /// crosshair is on, so confusing the two would select the wrong thing.
        let hit: CGPoint
        /// Whether it had to go below the touch.
        let flipped: Bool
    }

    static func loupe(at touch: CGPoint, in bounds: CGSize,
                      safeAreaTop: CGFloat) -> Loupe {
        let flipped = touch.y - loupeOffset < safeAreaTop + loupeFlipMargin
        let y = flipped ? touch.y + loupeOffset : touch.y - loupeOffset
        // Slide rather than hang off: half a loupe shows half the answer.
        let half = loupeSize / 2
        let x = min(max(touch.x, half), max(bounds.width - half, half))
        return Loupe(centre: CGPoint(x: x, y: y), hit: touch, flipped: flipped)
    }

    /// Twice what the reader can already see, rather than a fixed power: the
    /// loupe's job is to double the current scale, whatever that is.
    static func loupeScale(zoom: CGFloat) -> CGFloat { zoom * 2 }

    /// Shown, except where it would be WRONG rather than merely unhelpful.
    ///
    /// VoiceOver selects by element and not by point, so a magnifier over a
    /// touch means nothing there. Two fingers down is a pinch, and a pinch is
    /// not a selection.
    ///
    /// A pinch with one finger still down does NOT hide it -- see
    /// `loupeOpacity`: it freezes and dims instead, because a loupe that
    /// vanishes and returns reads as a glitch.
    static func showsLoupe(voiceOver: Bool, fingers: Int,
                           pinching: Bool) -> Bool {
        !voiceOver && fingers < 2
    }

    /// Dimmed while the scale is moving. It holds its last sample and
    /// re-samples on the first frame after the scale settles -- the same
    /// moment the canvas re-rasters. Stale music at a changing scale is worse
    /// than a visible pause.
    static func loupeOpacity(pinching: Bool) -> CGFloat { pinching ? 0.7 : 1 }
}
