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
/// **What travels is the LINE's x, not an offset.** The layer used to compute
/// the offset itself from a viewport width it had been handed -- a `@State`
/// initialised once from a GeometryReader and corrected only when the scroll
/// view reported a real move. Under load that width was zero at the moment it
/// was read; the offset for a zero viewport is zero; a strip parked at zero
/// never moves and so never reports; the width never corrected. The score did
/// not scroll -- on Ali's iPad and, reproduced, under the four-worker gate,
/// while the same test parked the line at exactly a quarter when run alone.
/// The scroll view has the live viewport and content size at the moment of
/// the move, so it does the arithmetic (`Playhead.stripOffset`) and the layer
/// only says where the line is.
///
/// `park` is installed by the scroll view when it is made and cleared when it
/// goes; before that, and after, `follow` is a no-op rather than a crash --
/// the play head can be running while the canvas is being rebuilt.
final class CanvasScroller {
    /// Installed by the scroll view: park the line drawn at this x, in CONTENT
    /// (unzoomed) points, at the park point -- computing the offset from its
    /// own live bounds and content size, with no animation. No animation is
    /// the point: a twenty-a-second animated scroll fights itself and arrives
    /// late, which is what "it jumps ahead and re-jumps" was.
    var park: ((CGFloat) -> Void)?
    /// Who installed `park`. A scroll view being torn down clears the closure
    /// ONLY if it is still the one that owns it: when the layout switches, the
    /// paged scroll view's coordinator can be deinitialised AFTER the
    /// continuous one has installed itself -- late under load, early when the
    /// machine is idle -- and an unconditional clear in that deinit left the
    /// strip with no way to move. Reproduced under a four-worker gate, and on
    /// Ali's iPad as "the score doesn't scroll"; passed every time run alone.
    weak var parkOwner: AnyObject?

    func install(owner: AnyObject, park: @escaping (CGFloat) -> Void) {
        self.park = park
        self.parkOwner = owner
    }

    /// Clear, if and only if `owner` is still the installer.
    func uninstall(owner: AnyObject) {
        guard parkOwner === owner else { return }
        park = nil
        parkOwner = nil
    }

    /// Where the last follow asked for, so an unchanged x costs nothing.
    private var last: CGFloat?

    func follow(playheadX x: CGFloat) {
        // Sub-point moves are invisible and still cost a layout pass.
        if let last, abs(last - x) < 0.5 { return }
        last = x
        park?(x)
    }

    /// The reader took over, or the music stopped: forget where we were, so the
    /// next follow moves even if it lands on the same number.
    func forget() { last = nil }
}
