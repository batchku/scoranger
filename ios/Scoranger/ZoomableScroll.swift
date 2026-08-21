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
    /// Room to leave at the bottom so floating chrome (the pill) can never
    /// cover the end of the score. The caller owns the number because it owns
    /// the pill's geometry.
    var bottomChrome: CGFloat = 0
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
        scroll.backgroundColor = UIColor(Theme.Surface.ground)
        // .always, not .never: without it the scroll view contributes no
        // safe-area inset and the score runs under the status bar as soon as
        // you scroll. Our own centring inset is added on top of it.
        scroll.contentInsetAdjustmentBehavior = .always

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
        context.coordinator.bottomChrome = bottomChrome
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
        var bottomChrome: CGFloat = 0
        private var laidOutSize: CGSize = .zero
        /// A size measured while zoomed, applied once zoom returns to 1.
        private var pendingSize: CGSize?

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

            // Changing the zoomed view's frame under a zoom transform is what
            // stranded the scroll extents at some zoom levels: UIScrollView
            // derives contentSize from the view it zooms, and mutating that
            // view's frame behind its back leaves the extents stale, so the end
            // of the score becomes unreachable. Defer the resize to zoom 1 and
            // meanwhile keep contentSize consistent with what is on screen.
            if scroll.zoomScale != 1 {
                pendingSize = size
                syncContentSize()
                return
            }
            commit(size)
        }

        private func commit(_ size: CGSize) {
            guard let host, let scroll else { return }
            laidOutSize = size
            pendingSize = nil
            host.view.frame = CGRect(origin: .zero, size: size)
            scroll.contentSize = CGSize(width: size.width * scroll.zoomScale,
                                        height: size.height * scroll.zoomScale)
            centreIfNeeded()
        }

        /// contentSize must always be the zoomed view's on-screen size.
        private func syncContentSize() {
            guard let host, let scroll else { return }
            let scaled = CGSize(width: host.view.frame.width * scroll.zoomScale,
                                height: host.view.frame.height * scroll.zoomScale)
            if scroll.contentSize != scaled { scroll.contentSize = scaled }
            centreIfNeeded()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host?.view }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            syncContentSize()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView,
                                     with view: UIView?, atScale scale: CGFloat) {
            // a resize measured mid-zoom was held back; it is safe now
            if scale == 1, let pending = pendingSize { commit(pending) }
            else { syncContentSize() }
            onZoomSettled(scale)
        }

        /// Centre the content when it is smaller than the viewport, keep the
        /// insets at zero when it is larger so every part stays reachable, and
        /// always leave `bottomChrome` clear so the pill cannot sit on the last
        /// system.
        func centreIfNeeded() {
            guard let scrollView = scroll, let view = host?.view else { return }
            let shown = CGSize(width: view.frame.width * scrollView.zoomScale,
                               height: view.frame.height * scrollView.zoomScale)
            let dx = max(0, (scrollView.bounds.width - shown.width) / 2)
            let dy = max(0, (scrollView.bounds.height - shown.height - bottomChrome) / 2)
            let inset = UIEdgeInsets(top: dy, left: dx,
                                     bottom: dy + bottomChrome, right: dx)
            if scrollView.contentInset != inset { scrollView.contentInset = inset }
        }
    }
}
