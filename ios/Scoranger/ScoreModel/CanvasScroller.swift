import CoreGraphics
import Foundation

/// The one way to move the canvas WITHOUT a SwiftUI update.
///
/// The play head reports twenty times a second. Following it through a
/// `@State` on the canvas would invalidate the canvas's body twenty times a
/// second -- the rasterised pages, the ink layer, the selection boxes, all of
/// it -- which is the same cost `PlayheadLayer` exists to avoid by observing
/// the engine itself instead of being handed a position.
///
/// So the layer that draws the line calls this, and the scroll view moves. It
/// is a plain reference type on purpose: nothing here is `@Published`, so
/// writing to it publishes nothing and redraws nothing.
///
/// `move` is installed by the scroll view when it is made and cleared when it
/// goes; before that, and after, `follow` is a no-op rather than a crash --
/// the play head can be running while the canvas is being rebuilt.
final class CanvasScroller {
    /// Installed by the scroll view: move the content to this x, in CONTENT
    /// (unzoomed) points, with no animation. No animation is the point -- a
    /// twenty-a-second animated scroll fights itself and arrives late, which is
    /// what "it jumps ahead and re-jumps" was.
    var move: ((CGFloat) -> Void)?

    /// Where the last follow asked for, so an unchanged target costs nothing.
    private var last: CGFloat?

    func follow(to x: CGFloat) {
        // Sub-point moves are invisible and still cost a layout pass.
        if let last, abs(last - x) < 0.5 { return }
        last = x
        move?(x)
    }

    /// The reader took over, or the music stopped: forget where we were, so the
    /// next follow moves even if it lands on the same number.
    func forget() { last = nil }
}
