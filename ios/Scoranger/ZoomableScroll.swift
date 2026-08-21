import SwiftUI
import UIKit

/// A UIScrollView wrapper that gives SwiftUI content real anchored pinch zoom.
///
/// The previous implementation multiplied the *page width* by a SwiftUI
/// `MagnifyGesture`'s magnification. That relaid the page stack out on every
/// frame, so content reflowed around the scroll origin instead of scaling about
/// the fingers: the score slid away under the gesture. UIScrollView's own
/// zooming keeps the midpoint between the fingers fixed, which is the behaviour
/// being asked for, and it comes with matched panning and rubber-banding.
///
/// Zoom is a view transform during the gesture, so the rendered bitmap stretches
/// while pinching. When the gesture settles, `onZoomSettled` reports the factor
/// so the caller can re-render the pages crisply at the new size; the scroll
/// offset is then restored proportionally, leaving the same music under the
/// same point on screen.
struct ZoomableScroll<Content: View>: UIViewRepresentable {
    /// Content size in points at zoom 1. The hosted view is pinned to this.
    let contentSize: CGSize
    let zoomRange: ClosedRange<CGFloat>
    /// Called when a pinch settles, with the factor relative to the last commit.
    let onZoomSettled: (CGFloat) -> Void
    @ViewBuilder var content: () -> Content

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = zoomRange.lowerBound
        scroll.maximumZoomScale = zoomRange.upperBound
        scroll.bouncesZoom = true
        scroll.showsVerticalScrollIndicator = true
        scroll.showsHorizontalScrollIndicator = true
        scroll.backgroundColor = UIColor(white: 0.93, alpha: 1)
        // the pages are drawn edge to edge; no automatic inset juggling
        scroll.contentInsetAdjustmentBehavior = .never

        let host = UIHostingController(rootView: AnyView(content()))
        host.view.backgroundColor = .clear
        scroll.addSubview(host.view)
        context.coordinator.host = host
        context.coordinator.scroll = scroll
        layout(scroll, context.coordinator)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.host?.rootView = AnyView(content())
        context.coordinator.onZoomSettled = onZoomSettled
        scroll.minimumZoomScale = zoomRange.lowerBound
        scroll.maximumZoomScale = zoomRange.upperBound
        layout(scroll, context.coordinator)
    }

    /// Pin the hosted view to the content size and centre it when it is
    /// narrower than the viewport.
    private func layout(_ scroll: UIScrollView, _ coordinator: Coordinator) {
        guard let view = coordinator.host?.view else { return }
        if coordinator.pendingContentSize != contentSize {
            coordinator.pendingContentSize = contentSize
            view.frame = CGRect(origin: .zero, size: contentSize)
            scroll.contentSize = contentSize
            coordinator.centreIfNeeded()
            // a re-render at a new size means the transform has been banked
            if scroll.zoomScale != 1 { scroll.setZoomScale(1, animated: false) }
            if let restore = coordinator.offsetToRestore {
                scroll.contentOffset = restore
                coordinator.offsetToRestore = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onZoomSettled: onZoomSettled) }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var host: UIHostingController<AnyView>?
        weak var scroll: UIScrollView?
        var onZoomSettled: (CGFloat) -> Void
        var pendingContentSize: CGSize = .zero
        /// Offset to reapply once the caller has re-rendered at the new size.
        var offsetToRestore: CGPoint?

        init(onZoomSettled: @escaping (CGFloat) -> Void) {
            self.onZoomSettled = onZoomSettled
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host?.view }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centreIfNeeded()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView,
                                     with view: UIView?, atScale scale: CGFloat) {
            guard abs(scale - 1) > 0.001 else { return }
            // Bank the gesture: the caller re-renders at scale x the current
            // size, and the offset scales with it so the same music stays put.
            offsetToRestore = CGPoint(x: scrollView.contentOffset.x,
                                      y: scrollView.contentOffset.y)
            onZoomSettled(scale)
        }

        func centreIfNeeded() {
            guard let scrollView = scroll, let view = host?.view else { return }
            let scaled = view.frame.size
            let dx = max(0, (scrollView.bounds.width - scaled.width) / 2)
            let dy = max(0, (scrollView.bounds.height - scaled.height) / 2)
            scrollView.contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
        }
    }
}
