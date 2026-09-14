import SwiftUI

/// The page under the fingertip, magnified, so the finger is not covering the
/// thing it is selecting.
///
/// IPHONE_0.6.14 §9.2. Zoom fixes resolution and does nothing about occlusion:
/// a fingertip covers whatever is under it at every scale, so at 4x the reader
/// can see the notehead perfectly right up until they reach for it. This is the
/// pattern every iOS reader already knows from text selection, and it is the
/// single control that most decides whether phone selection feels precise or
/// approximate.
///
/// It shows a SAMPLE rather than a live view, which is deliberate (§10.3): the
/// canvas is sampled once when the press begins and the loupe holds that
/// picture, dimming while a scale is moving rather than vanishing. A magnifier
/// that flickers out and back reads as a glitch; a still one reads as held.
struct LoupeSample: Equatable {
    let image: UIImage
    /// Where the finger is, in the canvas's own coordinates.
    let touch: CGPoint
    let canvas: CGSize
    /// The canvas's scale when the sample was taken, which the loupe doubles.
    let zoom: CGFloat
}

struct LoupeView: View {
    let sample: LoupeSample
    let safeAreaTop: CGFloat
    var pinching: Bool = false

    private var placement: TapSelection.Loupe {
        TapSelection.loupe(at: sample.touch, in: sample.canvas,
                           safeAreaTop: safeAreaTop)
    }

    var body: some View {
        let size = TapSelection.loupeSize
        let scale = TapSelection.loupeScale(zoom: sample.zoom) / max(sample.zoom, 0.01)
        ZStack {
            // The sample, slid so the touch point lands in the middle and
            // scaled about that point. `scaleEffect` scales about the view's
            // own centre, so the offset is applied first and in image points.
            Image(uiImage: sample.image)
                .resizable()
                .frame(width: sample.canvas.width, height: sample.canvas.height)
                .offset(x: sample.canvas.width / 2 - sample.touch.x,
                        y: sample.canvas.height / 2 - sample.touch.y)
                .scaleEffect(scale)
            crosshair
        }
        .frame(width: size, height: size)
        .background(Theme.Surface.paper)
        .clipShape(Circle())
        .modifier(PanelShadow())
        .opacity(TapSelection.loupeOpacity(pinching: pinching))
        .position(placement.centre)
        .allowsHitTesting(false)
        // Not hidden from accessibility, and not for the tests' sake: under
        // VoiceOver the loupe is never BUILT (`TapSelection.showsLoupe`),
        // because VoiceOver selects by element and a magnifier over a touch
        // point means nothing there. So when it exists at all, it is on a
        // screen someone is looking at.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("loupe")
        .accessibilityLabel("Magnifier")
    }

    /// What release commits is what the CROSSHAIR is on, not what the finger
    /// is on, so it is drawn -- an unmarked magnified circle would leave the
    /// reader guessing which of two neighbouring notes they had.
    private var crosshair: some View {
        let arm: CGFloat = 9
        return ZStack {
            Rectangle().frame(width: arm * 2, height: 1)
            Rectangle().frame(width: 1, height: arm * 2)
        }
        .foregroundStyle(Theme.Accent.clay)
    }
}

/// The one elevation the loupe is allowed: `ePanel`, from the token set.
/// Written as a modifier because `Theme.Elevation.panel` takes a view and
/// modifier chains cannot pass through it mid-chain.
private struct PanelShadow: ViewModifier {
    func body(content: Content) -> some View { Theme.Elevation.panel(content) }
}
