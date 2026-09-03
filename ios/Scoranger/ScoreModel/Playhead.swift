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
    // 3x an undivided 2pt line is a 6pt slab lying over the noteheads.
    /// The line's weight.
    static let weight: CGFloat = 2
    /// How far past the top and bottom staff the line runs.
    static let overshoot: CGFloat = 6
    /// The square handle at the top of the line.
    static let handle: CGFloat = 10
    static let handleRadius: CGFloat = 2

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
    static let parkFraction: CGFloat = 0.30

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
