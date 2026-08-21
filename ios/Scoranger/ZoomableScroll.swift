import SwiftUI
import UIKit

/// A UIScrollView wrapper that gives SwiftUI content real anchored pinch zoom.
///
/// Build 115 got the anchoring right by handing zoom to UIScrollView, but then
/// banked the gesture: on `scrollViewDidEndZooming` it relaid the page stack out
/// at the new size, reset `zoomScale` to 1 and tried to restore the offset. Three
/// things changing across two layout passes is what made the canvas jump when
/// the fingers lifted, and the recomputed content size was what stopped some
/// zoom levels from scrolling to the end of the score.
///
/// So the geometry is now left alone entirely. One layout at `contentWidth`,
/// measured rather than predicted, and zoom stays UIScrollView's transform —
/// which means UIKit owns the scroll extents at every zoom level, and nothing
/// moves when the gesture ends. `onZoomSettled` reports the settled scale purely
/// so the caller can raise the *raster* resolution of what it draws; that
/// changes sharpness, not position.
struct ZoomableScroll<Content: View>: UIViewRepresentable {
    /// Layout width for the content at zoom 1.
    let contentWidth: CGFloat
    let zoomRange: ClosedRange<CGFloat>
    /// Called with the absolute zoom scale once a pinch settles.
    let onZoomSettled: (CGFloat) -> Void
    @ViewBuilder var content: () -> Content

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = zoomRange.lowerBound
        scroll.maximumZoomScale = zoomRange.upperBound
        scroll.bouncesZoom = true
        scroll.backgroundColor = UIColor(white: 0.93, alpha: 1)
        scroll.contentInsetAdjustmentBehavior = .never

        let host = UIHostingController(rootView: AnyView(content()))
        host.view.backgroundColor = .clear
        scroll.addSubview(host.view)
        context.coordinator.host = host
        context.coordinator.scroll = scroll
        context.coordinator.applyLayout(width: contentWidth)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.onZoomSettled = onZoomSettled
        scroll.minimumZoomScale = zoomRange.lowerBound
        scroll.maximumZoomScale = zoomRange.upperBound
        // Swapping the root view re-renders the pages (a new raster scale, a new
        // annotation tool). Geometry is unchanged, so the scroll position is not
        // touched: that is what keeps the settle from jumping.
        context.coordinator.host?.rootView = AnyView(content())
        context.coordinator.applyLayout(width: contentWidth)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onZoomSettled: onZoomSettled) }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var host: UIHostingController<AnyView>?
        weak var scroll: UIScrollView?
        var onZoomSettled: (CGFloat) -> Void
        private var laidOutSize: CGSize = .zero

        init(onZoomSettled: @escaping (CGFloat) -> Void) {
            self.onZoomSettled = onZoomSettled
        }

        /// Size the hosted view from what SwiftUI actually needs at this width.
        /// The previous hand-computed height was the reason the end of a score
        /// could sit outside the scrollable area.
        func applyLayout(width: CGFloat) {
            guard let host, let scroll, width > 0 else { return }
            let measured = host.sizeThatFits(in: CGSize(width: width,
                                                        height: .greatestFiniteMagnitude))
            let size = CGSize(width: width, height: max(measured.height, 1))
            guard size != laidOutSize else { return }
            laidOutSize = size
            host.view.frame = CGRect(origin: .zero, size: size)
            // While zoomed, UIScrollView derives contentSize from the zoomed
            // view; setting it ourselves then would fight it and strand the
            // bottom of the score out of reach.
            if scroll.zoomScale == 1 {
                scroll.contentSize = size
            }
            centreIfNeeded()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host?.view }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centreIfNeeded()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView,
                                     with view: UIView?, atScale scale: CGFloat) {
            // Report only. Nothing here changes layout or offset.
            onZoomSettled(scale)
        }

        /// Centre the content when it is smaller than the viewport, and keep the
        /// insets at zero when it is larger so every part stays reachable.
        func centreIfNeeded() {
            guard let scrollView = scroll, let view = host?.view else { return }
            let shown = CGSize(width: view.frame.width * scrollView.zoomScale,
                               height: view.frame.height * scrollView.zoomScale)
            let dx = max(0, (scrollView.bounds.width - shown.width) / 2)
            let dy = max(0, (scrollView.bounds.height - shown.height) / 2)
            let inset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
            if scrollView.contentInset != inset { scrollView.contentInset = inset }
        }
    }
}
