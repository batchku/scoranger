import CoreGraphics
import Foundation

/// Where the cursor stands on the page.
///
/// The single most important decision in 0.6, and the easy one to get wrong:
/// this is driven by (MEASURE, BEAT), never by converting playback time to an
/// x. Playback expands repeats -- `ops.playback_timeline` calls music21's
/// `expandRepeats()` -- and the engraved page does not. Bar 5 is drawn once and
/// may sound twice, so playback time maps to page position MANY-to-one.
///
/// Taking Verovio's timemap and converting elapsed time to an x works right up
/// until the first repeat, and after that it requires Verovio's expansion and
/// music21's expansion to agree exactly, in every score, forever. When they
/// drift the cursor desyncs silently, which looks like working software.
///
/// So the timeline is asked which measure and how far into it, and the geometry
/// is asked where that measure is. A second pass through bar 5 resolves to bar
/// 5's frame again and the cursor jumps back, which is what a reader expects.
/// The failure mode -- a measure with no frame on this page -- is a cursor that
/// is absent rather than a cursor that lies.
///
/// Everything here is PAGE (SVG user) coordinates. The view scales it and adds
/// the view-space constants: 2pt weight and 6pt overshoot are 2pt and 6pt on
/// screen at any zoom, which is the whole reason they are not baked in here.
enum Playhead {

    /// Where the line is drawn, in page coordinates.
    struct Position: Equatable {
        /// The line's x, interpolated across the bar by the beat.
        let x: CGFloat
        /// The top of the topmost staff and the bottom of the lowest, so the
        /// line spans the system rather than one staff.
        let top: CGFloat
        let bottom: CGFloat

        var height: CGFloat { bottom - top }
    }

    /// The cursor for a measure and a fraction through it.
    ///
    /// `bars` is `BarPosition.bars(onPage:)`, which returns one frame per STAFF
    /// per measure -- a quartet gives four entries for bar 12. Their union is
    /// the vertical span the line draws across, and that is why the frames are
    /// combined rather than the first one taken.
    static func position(measure: Int, fraction: CGFloat,
                         bars: [BarPosition.Bar]) -> Position? {
        let frames = bars.filter { $0.number == measure }.map(\.frame)
        guard !frames.isEmpty else { return nil }
        let union = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        guard union.width > 0 else { return nil }
        let across = min(max(fraction, 0), 1)
        return Position(x: union.minX + union.width * across,
                        top: union.minY, bottom: union.maxY)
    }

    // The view-space constants (§2 of the designer spec). Every one of them is
    // a size ON SCREEN, so the view divides by the zoom before using them: at
    // 3x an undivided line is a slab lying over the noteheads.
    /// The line's weight.
    ///
    /// 1pt, down from the 2pt §2 drew. The owner marked the 2pt line "thin" on
    /// a screenshot -- meaning make it thin -- and 1pt is not a new number: it
    /// is the hairline every rule, border and divider in this app is drawn at,
    /// so the cursor now weighs the same as the lines it crosses and is told
    /// apart by its COLOUR, which is what `clay` on a black-and-white
    /// engraving is for. It stays a size on screen, which is the whole reason
    /// this constant is here and not baked into the geometry.
    static let weight: CGFloat = 1
    /// How far past the top and bottom staff the line runs.
    static let overshoot: CGFloat = 6
    /// The square handle at the top of the line.
    ///
    /// It did not shrink with the line. It is now the only part of the cursor
    /// layer a touch can reach (`ScorePagesView.PlayheadHandle`), and a target
    /// that is hard to land on is worse than a heavy one.
    static let handle: CGFloat = 10
    static let handleRadius: CGFloat = 2

    /// How wide a touch may land from the handle's centre and still be a grab,
    /// in VIEW space.
    ///
    /// Larger than the 10pt square it grabs, because a 10pt target is below
    /// anything a finger can be asked to hit -- and smaller than the 44pt
    /// Apple would ask for, because every point of it is taken away from the
    /// lasso and the Pencil. 32 is the compromise, stated as a number so it
    /// can be argued with: half of it, 16pt, is the radius inside which a
    /// touch stops being a pan and starts being a scrub.
    static let handleTouchTarget: CGFloat = 32

    /// A size on screen, written in the space the layer draws in.
    ///
    /// The same rule as `SelectionInk.onScreen` and deliberately delegating to
    /// it rather than repeating it: the cursor and the selection ink are two
    /// marks with one law, and the divide-by-zoom was written twice before,
    /// with two different guards against a zoom that is not a number yet.
    static func onScreen(_ size: CGFloat, zoom: CGFloat) -> CGFloat {
        SelectionInk.onScreen(size, zoom: zoom)
    }

    // MARK: - Dragging the handle (0.6.6)

    /// Is this touch a grab of the handle?
    ///
    /// Asked in the SAME space the two points are given in, whichever that is:
    /// the caller hands over a touch and the handle's centre in one coordinate
    /// system and the target already converted into it, so the rule does not
    /// need to know whether it is looking at page units or surface points. A
    /// square and not a circle, because the handle is a square and a reader
    /// aiming at its corner should hit it.
    static func handleGrabbed(touch: CGPoint, handle: CGPoint,
                              target: CGFloat) -> Bool {
        guard target > 0 else { return false }
        let half = target / 2
        return abs(touch.x - handle.x) <= half && abs(touch.y - handle.y) <= half
    }

    /// The bar the reader has dragged the handle onto, in PAGE coordinates.
    ///
    /// Y FIRST, and that is the whole of it. A page holds several systems
    /// stacked, and bar 3 of the first system sits at the same x as bar 40 of
    /// the fourth -- so a rule that reads x alone lands the play head on
    /// whichever of them the search happened to reach first, and a two-inch
    /// horizontal drag jumps thirty bars. The system is chosen by the y the
    /// finger is at, and only then is the bar chosen by its x.
    ///
    /// Nothing is refused. A finger dragged into the margin, above the first
    /// system or past the last bar of a line still means something -- the
    /// nearest bar to where it is -- and a scrub that stops responding at the
    /// edge of the music reads as a broken gesture rather than as a limit.
    ///
    /// - Parameters:
    ///   - point: where the finger is, in page (SVG user) coordinates.
    ///   - bars: `BarPosition.bars(onPage:)` -- one frame per STAFF per
    ///     measure, so the frames are unioned per measure first, exactly as
    ///     `position(measure:fraction:bars:)` does. Taking them one at a time
    ///     would let the cello's staff win a drag aimed at the violin's.
    static func bar(at point: CGPoint, bars: [BarPosition.Bar]) -> Int? {
        var union: [Int: CGRect] = [:]
        for bar in bars {
            union[bar.number] = union[bar.number].map { $0.union(bar.frame) } ?? bar.frame
        }
        guard !union.isEmpty else { return nil }

        // The system: the bars whose vertical span the finger is in, or --
        // when it is in none of them -- the bars nearest it vertically.
        let vertical = union.mapValues { verticalDistance(from: point.y, to: $0) }
        guard let nearest = vertical.values.min() else { return nil }
        let onSystem = union.filter { (vertical[$0.key] ?? .infinity) <= nearest + 0.5 }

        // The bar: the one the finger is inside, else the nearest along the
        // line. Ties go to the lower measure number so the same drag always
        // lands the same way.
        var best: Int?
        var bestDistance = CGFloat.infinity
        for (number, frame) in onSystem {
            let distance = horizontalDistance(from: point.x, to: frame)
            if distance < bestDistance || (distance == bestDistance && number < (best ?? .max)) {
                best = number
                bestDistance = distance
            }
        }
        return best
    }

    private static func verticalDistance(from y: CGFloat, to frame: CGRect) -> CGFloat {
        if y < frame.minY { return frame.minY - y }
        if y > frame.maxY { return y - frame.maxY }
        return 0
    }

    private static func horizontalDistance(from x: CGFloat, to frame: CGRect) -> CGFloat {
        if x < frame.minX { return frame.minX - x }
        if x > frame.maxX { return x - frame.maxX }
        return 0
    }

    /// Which page of the engraving holds a measure, or nil when none does.
    ///
    /// Used for page-follow and for the Sync chip's "is the playhead visible"
    /// question. Nil is a real answer: the remote-engine path builds no
    /// geometry at all, and following nothing beats following a guess.
    static func page(ofMeasure measure: Int,
                     pages: [(index: Int, bars: [BarPosition.Bar])]) -> Int? {
        pages.first { page in page.bars.contains { $0.number == measure } }?.index
    }

    /// Whether the page should be turned yet.
    ///
    /// The turn happens at 85% of the page width, so the next page arrives
    /// BEFORE the music does. A turn that waited for the playhead to leave
    /// would put the reader a page behind at exactly the moment they need to
    /// read ahead.
    static let turnThreshold: CGFloat = 0.85

    static func shouldTurnPage(x: CGFloat, pageWidth: CGFloat) -> Bool {
        pageWidth > 0 && x >= pageWidth * turnThreshold
    }

    // MARK: - The continuous strip: the line stands still and the score moves

    /// Where the line parks, as a fraction of the viewport from its left edge
    /// (design/PLAYBACK_0.6.md §2).
    ///
    /// A third of the way in leaves two thirds of the screen as music the
    /// player has not reached yet, which is what reading ahead means.
    /// A quarter of the way in (Ali, 2026-09-10: "about 25% from the left").
    /// Was 0.30. A quarter behind the line for what has just been played,
    /// three quarters ahead for what is coming, which is what a player reads.
    static let parkFraction: CGFloat = 0.25

    /// Where the strip must sit for the line to stand still under the music.
    ///
    /// The DAW rule, and the reason it is stated as a scroll offset rather than
    /// as a moving line: the line is drawn at the sounding moment's own place
    /// in the engraving, and the SCORE is moved so that place lands at the park
    /// point. Everything else falls out of the clamp:
    ///
    /// - at the start of the piece the offset clamps to 0, so the score holds
    ///   still and the line travels in from the first bar to the park point;
    /// - in the body of the piece the offset tracks the line exactly, so the
    ///   line is motionless and the music streams past it;
    /// - at the end the offset clamps to the last screenful and the line
    ///   travels on to the final bar.
    ///
    /// Both arguments are in SURFACE points (the strip as laid out on screen),
    /// which is the space the scroll view's content offset lives in.
    static func stripOffset(playheadX: CGFloat, viewportWidth: CGFloat,
                            surfaceWidth: CGFloat,
                            park: CGFloat = parkFraction) -> CGFloat {
        guard viewportWidth > 0, surfaceWidth > 0 else { return 0 }
        let furthest = max(surfaceWidth - viewportWidth, 0)
        return min(max(playheadX - viewportWidth * park, 0), furthest)
    }

    /// The notes the line is crossing: at most one per staff.
    ///
    /// The geometry carries no onset time -- it is a picture of the page, and
    /// the map from beats to elements the designer's spec asks for does not
    /// exist yet. But an engraving IS a time axis: within a bar, a note's x
    /// position is its onset. So the note under the line on each staff is the
    /// last one the line has reached, and it stays lit until the line reaches
    /// the next -- which is exactly "highlighted for the note's duration".
    ///
    /// One per STAFF, because every part sounds at once and highlighting only
    /// the top one would say the others are silent.
    ///
    /// - Parameters:
    ///   - notes: the note-like elements of the measure being played, with the
    ///     staff each belongs to. Page (SVG user) coordinates.
    ///   - x: the line, in the same coordinates.
    static func sounding(notes: [(staff: Int, frame: CGRect)],
                         x: CGFloat) -> [CGRect] {
        var best: [Int: CGRect] = [:]
        for note in notes where note.frame.minX <= x {
            // the rightmost note the line has already reached, per staff
            if let held = best[note.staff], held.minX >= note.frame.minX { continue }
            best[note.staff] = note.frame
        }
        return best.keys.sorted().compactMap { best[$0] }
    }
}
