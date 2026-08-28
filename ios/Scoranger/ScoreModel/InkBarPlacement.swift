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

    /// Keep the bar wholly inside the pane, wherever it is dragged.
    ///
    /// Horizontally it may travel to either edge; vertically only UPWARD, from
    /// the dock -- there is nothing below it to move into, and a bar dragged
    /// off the bottom edge would be unreachable.
    static func clamp(_ offset: CGSize, in bounds: CGSize,
                      barSize: CGSize) -> CGSize {
        guard bounds.width > 0, bounds.height > 0 else { return docked }
        let sideways = max(0, (bounds.width - barSize.width) / 2)
        let upward = max(0, bounds.height - barSize.height - footerInset)
        return CGSize(width: min(max(offset.width, -sideways), sideways),
                      height: min(max(offset.height, -upward), 0))
    }

    /// A bar bigger than the pane it is in has nowhere to go.
    static func isMovable(in bounds: CGSize, barSize: CGSize) -> Bool {
        bounds.width > barSize.width || bounds.height > barSize.height + footerInset
    }
}
