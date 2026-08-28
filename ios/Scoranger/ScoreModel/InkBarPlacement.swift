import CoreGraphics

/// Where the ink tools sit, and how far they may be moved.
///
/// They floated over the music: anchored to the bottom of the score pane but
/// lifted 74 points off it, which on a page that runs to the bottom of the
/// pane puts them in the middle of the last system. Ali's screenshot has them
/// over the staves.
///
/// So they dock, in the footer strip under the page, and can be moved out of
/// the way from a handle. Moving them is a convenience, never the only way to
/// reach anything -- the no-drag rule is about features that can only be
/// reached by dragging, and the tools are all reachable where they are. A tap
/// on the handle puts them back, so a bar dragged somewhere silly is never a
/// trap for someone who cannot drag it again.
enum InkBarPlacement {

    /// How far the docked bar sits off the bottom of the score pane. Clear of
    /// the edge, and clear of the music, which is what 74 was not.
    static let footerInset: CGFloat = 8

    /// The bar's home. Every offset is measured from the dock.
    static let docked: CGSize = .zero

    /// How much of the bar must stay on screen. Anything less and it could be
    /// pushed off an edge with no way to take hold of it again.
    static let mustRemainVisible: CGFloat = 60

    /// Where the bar may go: anywhere on the screen (#46).
    ///
    /// It used to be held above the thumbnail strip and inside the pane, and
    /// Ali asked for the opposite -- the bar is his, and the thing it is
    /// covering is his business. The only limit left is that some of it stays
    /// reachable: a bar dragged entirely off an edge could not be dragged back,
    /// and the tap-to-re-dock is on the bar itself.
    ///
    /// DOWNWARD travel is what changed. The strip and the transport are below
    /// the dock, and holding the bar above them was the clamp he ran into.
    static func clamp(_ offset: CGSize, in bounds: CGSize,
                      barSize: CGSize) -> CGSize {
        guard bounds.width > 0, bounds.height > 0 else { return docked }
        let keepAcross = min(mustRemainVisible, barSize.width)
        let keepDown = min(mustRemainVisible, barSize.height)
        // sideways: until all but `keepAcross` has left the screen
        let sideways = max(0, (bounds.width + barSize.width) / 2 - keepAcross)
        // up: the whole height of the container, which is the whole SCREEN --
        // the bar's layer sits on the score screen rather than on the page
        // canvas, so the strip and the transport are inside it and it can be
        // moved over them (#46)
        let upward = max(0, bounds.height - barSize.height - footerInset)
        // down: it docks near the bottom edge already, so this is the last few
        // points before `keepDown` is all that is left showing
        let downward = max(0, footerInset + barSize.height - keepDown)
        return CGSize(width: min(max(offset.width, -sideways), sideways),
                      height: min(max(offset.height, -upward), downward))
    }

    /// A bar bigger than the pane it is in has nowhere to go.
    static func isMovable(in bounds: CGSize, barSize: CGSize) -> Bool {
        bounds.width > barSize.width || bounds.height > barSize.height + footerInset
    }
}
