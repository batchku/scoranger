import SwiftUI
import UIKit

/// A scroll view that reports its own resizes.
///
/// `updateUIView` runs before SwiftUI has resized the representable, so the
/// centring inset computed there is derived from the *previous* width. Opening
/// the chat panel therefore left the page centred on the old, wider region --
/// mostly hidden under the panel. UIViewRepresentable has no hook for "my
/// bounds changed", so the view reports it itself.
final class BoundsAwareScrollView: UIScrollView {
    var onBoundsChange: (() -> Void)?
    private var lastSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        onBoundsChange?()
    }
}

/// A UIScrollView wrapper that gives SwiftUI content real anchored pinch zoom.
///
/// Build 115 got the anchoring right by handing zoom to UIScrollView, but then
/// banked the gesture: on `scrollViewDidEndZooming` it relaid the page stack out
/// at the new size, reset `zoomScale` to 1 and tried to restore the offset. Three
/// things changing across two layout passes is what made the canvas jump when
/// the fingers lifted, and the recomputed content size was what stopped some
/// zoom levels from scrolling to the end of the score.
///
/// So the geometry is written once per size, measured rather than predicted, and
/// zoom stays UIScrollView's transform — which means UIKit owns the scroll
/// extents at every zoom level, and nothing moves when the gesture ends.
/// `onZoomSettled` reports the settled scale purely so the caller can raise the
/// *raster* resolution of what it draws; that changes sharpness, not position.
///
/// Build 120: the size does change while zoomed — a panel opening or closing
/// resizes the canvas under the score — so `commit` handles that case rather
/// than deferring it, and only an in-flight pinch is waited out.
struct ZoomableScroll<Content: View>: UIViewRepresentable {
    /// Layout width for the content at zoom 1.
    let contentWidth: CGFloat
    /// A finished lasso: the page it was drawn on, its unit points, and
    /// whether it adds to the existing selection.
    var onLasso: ((Int, [CGPoint], Bool) -> Void)?
    /// Two fingers tapped without moving: undo the last ink stroke.
    var onUndoTap: (() -> Void)?
    /// A single tap on a page: (page index, unit point). Used to drop one
    /// element from the selection.
    var onTap: ((Int, CGPoint) -> Void)?
    /// Markup mode. It changes what the Pencil does, and nothing else.
    var annotationActive: Bool = false
    /// Room to leave at the bottom so floating chrome (the pill) can never
    /// cover the end of the score. The caller owns the number because it owns
    /// the pill's geometry.
    var bottomChrome: CGFloat = 0
    let zoomRange: ClosedRange<CGFloat>
    /// Called with the absolute zoom scale once a pinch settles.
    let onZoomSettled: (CGFloat) -> Void
    @ViewBuilder var content: () -> Content

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = BoundsAwareScrollView()
        let coordinator = context.coordinator
        scroll.onBoundsChange = { [weak coordinator] in coordinator?.viewportChanged() }
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = zoomRange.lowerBound
        scroll.maximumZoomScale = zoomRange.upperBound
        scroll.bouncesZoom = true
        scroll.backgroundColor = UIColor(Theme.Surface.ground)
        // .always, not .never: without it the scroll view contributes no
        // safe-area inset and the score runs under the status bar as soon as
        // you scroll. Our own centring inset is added on top of it.
        scroll.contentInsetAdjustmentBehavior = .always
        // the library panel also hosts a scroll view, so tests (and VoiceOver)
        // need to be able to name this one specifically
        scroll.accessibilityIdentifier = "score-canvas"
        scroll.isAccessibilityElement = false
        // the live zoom scale, the only way a UI test can see what a pinch
        // actually did to the canvas
        scroll.accessibilityValue = "zoom 1.00"

        // The Pencil selects. The recognizer sits here because it must see
        // touches delivered to any page below it. Scrolling is never made to
        // wait for it: fingers pan at once, and the Pencil is not allowed to
        // pan at all, so the two can never be waiting on each other.
        let lasso = LassoGestureRecognizer(target: context.coordinator,
                                           action: #selector(Coordinator.lassoFired(_:)))
        scroll.addGestureRecognizer(lasso)
        context.coordinator.lasso = lasso

        // Fingers pan; the Pencil never does. By default a scroll view pans
        // with the Pencil too, so a Pencil lasso was competing with a scroll it
        // could not win. This is also what makes the split clean enough to need
        // no arbitration: the two instruments cannot want the same thing.
        scroll.panGestureRecognizer.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue)
        ]
        context.coordinator.lasso?.onPencilPresence = {
            [weak coordinator] frozen in coordinator?.freezeCanvas(frozen)
        }

        // A Pencil tap: drops one element from the selection. Pencil only,
        // because dropping an element is a selection edit and the hand does not
        // edit selections. It never blocks anything else -- a tap has no
        // movement, so scrolling and pinching cannot be waiting on it.
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.allowedTouchTypes = LassoGestureRecognizer.fingerStandsInForPencil
            ? [NSNumber(value: UITouch.TouchType.pencil.rawValue),
               NSNumber(value: UITouch.TouchType.direct.rawValue)]
            : [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        scroll.addGestureRecognizer(tap)

        let host = UIHostingController(rootView: AnyView(content()))
        host.view.backgroundColor = .clear
        scroll.addSubview(host.view)
        context.coordinator.host = host
        context.coordinator.scroll = scroll
        context.coordinator.applyLayout(width: contentWidth)
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.lasso?.onEnd = onLasso
        context.coordinator.lasso?.onUndoTap = onUndoTap
        context.coordinator.lasso?.onPencilPresence = {
            [weak coordinator = context.coordinator] frozen in
            coordinator?.freezeCanvas(frozen)
        }
        context.coordinator.onTap = onTap
        context.coordinator.lasso?.annotationActive = annotationActive
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
        weak var lasso: LassoGestureRecognizer?
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

            // Never mid-gesture: resizing the view UIScrollView is actively
            // zooming fights the pinch and leaves the extents stale, which is
            // what made the end of a score unreachable in build 118. Any other
            // time -- including sitting at 2x when a panel opens -- the resize
            // has to happen, or the page overflows a content area still sized
            // for the old width and part of it can no longer be panned to.
            if scroll.isZooming || scroll.isZoomBouncing {
                pendingSize = size
                recentre()
                return
            }
            commit(size)
        }

        private func commit(_ size: CGSize) {
            guard let host, let scroll else { return }
            laidOutSize = size
            pendingSize = nil

            // where the viewport sits in the content, so the same music is
            // still in view after the resize
            let old = scroll.contentSize
            let anchor = CGPoint(
                x: old.width > 0
                    ? (scroll.contentOffset.x + scroll.bounds.width / 2) / old.width : 0.5,
                y: old.height > 0
                    ? (scroll.contentOffset.y + scroll.bounds.height / 2) / old.height : 0)

            // Geometry can only be written at zoom 1: under a zoom transform the
            // hosted view's `frame` IS the zoomed frame, and UIScrollView keeps
            // it and contentSize in step itself. So drop to 1, resize, put the
            // scale back, and let UIKit re-derive the extents.
            let scale = scroll.zoomScale
            if scale != 1 { scroll.setZoomScale(1, animated: false) }
            host.view.transform = .identity
            host.view.frame = CGRect(origin: .zero, size: size)
            scroll.contentSize = size
            if scale != 1 { scroll.setZoomScale(scale, animated: false) }

            centreIfNeeded()
            let now = scroll.contentSize
            scroll.contentOffset = CGPoint(
                x: anchor.x * now.width - scroll.bounds.width / 2,
                y: anchor.y * now.height - scroll.bounds.height / 2)
            centreIfNeeded()   // clamps the restored offset into range
        }

        /// While a zoom is live, contentSize belongs to UIScrollView.
        ///
        /// Zooming scales the hosted view about the pinch anchor and UIScrollView
        /// then re-anchors the view's frame and contentSize together. Writing
        /// contentSize ourselves broke that pairing: computed from the
        /// transformed `frame` it squared the scale (1600pt of empty scrollable
        /// area at 1.8x), and computed from `bounds` it ignored the view's new
        /// frame origin, which put part of the page outside the scrollable
        /// range -- a hard limit a few hundred points inside the canvas, at
        /// every zoom level. So during zoom we only re-centre.
        private func recentre() {
            centreIfNeeded()
        }

        /// The viewport itself resized (a panel opened or closed, or the
        /// device rotated). The content width comes from SwiftUI and is already
        /// correct by then; what is stale is the centring inset and, with it,
        /// where the page sits. Re-centre against the bounds we now have.
        func viewportChanged() {
            centreIfNeeded()
        }

        var onTap: ((Int, CGPoint) -> Void)?

        /// Pan and zoom are off while a Pencil is down to select.
        ///
        /// Both of them: disabling scrolling alone still leaves the pinch live,
        /// and a hand steadying the iPad next to the Pencil is two fingers on
        /// the glass. Turning scrolling off also cancels a pan already in
        /// flight, so a palm that landed before the Pencil stops dragging the
        /// page the moment the Pencil arrives.
        func freezeCanvas(_ frozen: Bool) {
            guard let scroll else { return }
            scroll.isScrollEnabled = !frozen
            scroll.pinchGestureRecognizer?.isEnabled = !frozen
        }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let root = recognizer.view else { return }
            let point = recognizer.location(in: root)
            guard let hit = LassoGestureRecognizer.page(at: point, in: root) else { return }
            onTap?(hit.index, hit.unit)
        }

        /// The lasso's own state changes need do nothing to the canvas: the
        /// freeze is keyed on the Pencil being DOWN, which starts earlier (the
        /// moment it touches) and ends later (when it lifts) than the stroke.
        @objc func lassoFired(_ recognizer: LassoGestureRecognizer) {}

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host?.view }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            recentre()
            publishZoom(scrollView)
        }

        private func publishZoom(_ scrollView: UIScrollView) {
            scrollView.accessibilityValue = String(format: "zoom %.2f",
                                                   scrollView.zoomScale)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView,
                                     with view: UIView?, atScale scale: CGFloat) {
            // a resize measured mid-gesture was held back; it is safe now
            if let pending = pendingSize { commit(pending) } else { recentre() }
            publishZoom(scrollView)
            onZoomSettled(scale)
        }

        /// Centre the content when it is smaller than the viewport, keep the
        /// insets at zero when it is larger so every part stays reachable, and
        /// always leave `bottomChrome` clear so the pill cannot sit on the last
        /// system.
        func centreIfNeeded() {
            guard let scrollView = scroll else { return }
            // contentSize, not the hosted view's frame: UIScrollView keeps the
            // two in step through a zoom, and it is the extents that the
            // centring inset has to agree with
            let shown = scrollView.contentSize
            let dx = max(0, (scrollView.bounds.width - shown.width) / 2)
            let dy = max(0, (scrollView.bounds.height - shown.height - bottomChrome) / 2)
            let inset = UIEdgeInsets(top: dy, left: dx,
                                     bottom: dy + bottomChrome, right: dx)
            if scrollView.contentInset != inset { scrollView.contentInset = inset }
            clampOffset(scrollView, shown: shown, inset: inset)
        }

        /// A contentOffset left over from a wider viewport stays out of range
        /// until something scrolls: UIScrollView clamps on gesture, not when the
        /// inset changes. Without this the re-centred page still draws off to
        /// one side after a panel opens.
        private func clampOffset(_ scrollView: UIScrollView,
                                 shown: CGSize, inset: UIEdgeInsets) {
            func fit(_ offset: CGFloat, _ content: CGFloat, _ viewport: CGFloat,
                     _ lead: CGFloat, _ trail: CGFloat) -> CGFloat {
                let low = -lead
                let high = max(low, content - viewport + trail)
                return min(max(offset, low), high)
            }
            let target = CGPoint(
                x: fit(scrollView.contentOffset.x, shown.width,
                       scrollView.bounds.width, inset.left, inset.right),
                y: fit(scrollView.contentOffset.y, shown.height,
                       scrollView.bounds.height, inset.top, inset.bottom))
            if target != scrollView.contentOffset { scrollView.contentOffset = target }
        }
    }
}
