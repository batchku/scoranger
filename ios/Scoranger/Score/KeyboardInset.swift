import CoreGraphics

/// How much of the screen the software keyboard covers, and what a docked panel
/// has to do about it.
///
/// The score screen turns SwiftUI's automatic keyboard avoidance OFF
/// (`.ignoresSafeArea(.keyboard)` on `ContentView.scoreBody`). That avoidance is
/// a safe-area inset on the whole screen: with it on, the canvas lost the
/// keyboard's height, `PagedCanvas.fittedPageWidth` re-fitted the page to what
/// was left, and a full page collapsed to a thumbnail while someone typed a
/// question about it (#59). The music must not resize because a text field took
/// focus.
///
/// The cost of opting out is that the panels which DO own a text field have to
/// lift themselves, which is what `panelBottom` is for.
enum KeyboardInset {
    /// Padding a bottom-docked panel needs so its field clears the keyboard.
    ///
    /// The panel already sits clear of the home indicator, so it needs the part
    /// of the keyboard above that, not the whole height.
    static func panelBottom(keyboard: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
        max(keyboard - safeAreaBottom, 0)
    }
}
