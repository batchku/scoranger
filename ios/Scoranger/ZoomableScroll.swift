import OSLog
import SwiftUI
import UIKit

/// Rate limit for the park log line (a generic class cannot hold a static).
private nonisolated(unsafe) var zoomableScrollLastParkLog = Date.distantPast

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
    /// A Pencil tap on a page: (page index, unit point, how many taps).
    /// One drops an element; two select the bar on that staff; three select the
    /// bar across every staff.
    var onTap: ((Int, CGPoint, Int, Bool) -> Void)?
    /// The Pencil landed and this stroke replaces the selection.
    var onWillReplaceSelection: (() -> Void)?
    /// A finished single-finger touch, measured. What it MEANT -- a turn, a
    /// selection, a clear, or nothing -- is `CanvasTap`'s single answer, and
    /// the view that knows the mode asks for it (§12).
    var onCanvasTap: ((CanvasTap.Touch) -> Void)?
    /// A press is live: the canvas, sampled, and where the finger is on it.
    /// Nil when the press ends (§9.2).
    var onLoupe: ((LoupeSample?) -> Void)?
    /// A horizontal swipe with no slack left to pan: turn.
    var onSwipeTurn: ((Int) -> Void)?
    /// What the Pencil means right now, which decides whether a press is
    /// possible at all (§13, `TapSelection.allowsPress`).
    var mode: ScoreMode = .read
    /// VoiceOver selects by element, not by point: no press, no loupe.
    var voiceOverRunning = false
    /// Selection off, for performance mode.
    var selectionEnabled: Bool = true
    /// `Select` is armed: one finger draws a loop instead of panning (§9.3).
    /// The same code path the Pencil's lasso uses -- one finger stands in for
    /// it, two still pan and pinch, so the reader can reposition mid-loop.
    var lassoArmed = false
    /// A page turn happened: reset the pan to the new unit's top-left, keeping
    /// the zoom. That is what turning a paper page does -- a violinist reading
    /// at 180% stays at 180% (§6.1).
    var resetPanToken: Int = 0
    /// Markup mode. It changes what the Pencil does, and nothing else.
    var annotationActive: Bool = false
    /// Where to scroll horizontally, and a token so the same destination asked
    /// for twice still moves. Continuous mode's tap zones advance by a viewport
    /// rather than turning a page, and there is no page index for them to
    /// change -- so the request is made directly of the scroll view.
    var scrollTarget: (token: Int, x: CGFloat)?
    /// Room to leave at the bottom so floating chrome (the pill) can never
    /// cover the end of the score. The caller owns the number because it owns
    /// the pill's geometry.
    var bottomChrome: CGFloat = 0
    /// The viewport in CONTENT (unzoomed) coordinates, whenever it moves.
    /// What it is for: deciding which pages are worth rastering at depth.
    var onVisibleRectChange: ((CGRect, CGSize) -> Void)?
    /// Moves the canvas without going through SwiftUI, for the play head --
    /// which reports twenty times a second and must not invalidate the canvas
    /// that often. See `CanvasScroller`.
    var scroller: CanvasScroller?
    /// A DRAG by the reader, as opposed to any of the moves this view makes on
    /// their behalf. Following the music hands over to whoever pushes the
    /// score, and only a hand can push it.
    var onUserScroll: (() -> Void)?
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

        // A finger tap in the outer zones turns the page (§6.2). Safe to add,
        // because a single-finger tap on the page did nothing at all before
        // this: fingers only ever scrolled. It cancels nothing, so a scroll
        // that happens to end still scrolls.
        let turn = TurnTapRecognizer(target: context.coordinator,
                                     action: #selector(Coordinator.turnTapped(_:)))
        turn.cancelsTouchesInView = false
        // Recognising must cost the scroll view nothing: without this, a
        // recogniser that ends can make another fail, and the two that matter
        // here are the pan and the pinch.
        turn.delegate = context.coordinator
        turn.onPress = { [weak coordinator = context.coordinator] point in
            coordinator?.pressed(point)
        }
        turn.atLimitNow = { [weak coordinator = context.coordinator] in
            coordinator?.atHorizontalLimit ?? false
        }
        context.coordinator.turn = turn
        scroll.addGestureRecognizer(turn)

        // A Pencil tap: drops one element from the selection. Pencil only,
        // because dropping an element is a selection edit and the hand does not
        // edit selections. It never blocks anything else -- a tap has no
        // movement, so scrolling and pinching cannot be waiting on it.
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        let pencilTouchTypes: [NSNumber] =
            LassoGestureRecognizer.fingerStandsInForPencil
            ? [NSNumber(value: UITouch.TouchType.pencil.rawValue),
               NSNumber(value: UITouch.TouchType.direct.rawValue)]
            : [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        tap.allowedTouchTypes = pencilTouchTypes

        // Two taps in empty space select that bar; three select it across every
        // staff. The single tap has to wait for both to fail, which costs it
        // about a third of a second -- the price of the bar gesture existing at
        // all, and paid only by the tap that drops one element.
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        doubleTap.allowedTouchTypes = pencilTouchTypes
        scroll.addGestureRecognizer(doubleTap)

        let tripleTap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tripleTap.numberOfTapsRequired = 3
        tripleTap.cancelsTouchesInView = false
        tripleTap.allowedTouchTypes = pencilTouchTypes
        scroll.addGestureRecognizer(tripleTap)

        tap.require(toFail: doubleTap)
        doubleTap.require(toFail: tripleTap)
        scroll.addGestureRecognizer(tap)

        let host = UIHostingController(rootView: AnyView(content()))
        host.view.backgroundColor = .clear
        scroll.addSubview(host.view)
        context.coordinator.host = host
        context.coordinator.scroll = scroll
        context.coordinator.installScroller(scroller)
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
        context.coordinator.lasso?.onWillReplaceSelection = onWillReplaceSelection
        context.coordinator.lasso?.annotationActive = annotationActive
        context.coordinator.lasso?.selectionEnabled = selectionEnabled
        context.coordinator.lasso?.fingerSelects = lassoArmed
        context.coordinator.turn?.armed = lassoArmed
        context.coordinator.turn?.mode = mode
        context.coordinator.turn?.voiceOverRunning = voiceOverRunning
        context.coordinator.turn?.inking = annotationActive
        context.coordinator.onCanvasTap = onCanvasTap
        context.coordinator.onLoupe = onLoupe
        context.coordinator.onSwipeTurn = onSwipeTurn
        context.coordinator.resetPan(token: resetPanToken)
        context.coordinator.onZoomSettled = onZoomSettled
        context.coordinator.onVisibleRectChange = onVisibleRectChange
        context.coordinator.onUserScroll = onUserScroll
        context.coordinator.installScroller(scroller)
        context.coordinator.bottomChrome = bottomChrome
        if let target = scrollTarget {
            context.coordinator.scrollHorizontally(to: target.x, token: target.token)
        }
        scroll.minimumZoomScale = zoomRange.lowerBound
        scroll.maximumZoomScale = zoomRange.upperBound
        // Swapping the root view re-renders the pages (a new raster scale, a new
        // annotation tool). Geometry is unchanged, so the scroll position is not
        // touched: that is what keeps the settle from jumping.
        context.coordinator.host?.rootView = AnyView(content())
        context.coordinator.applyLayout(width: contentWidth)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onZoomSettled: onZoomSettled) }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {

        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer)
            -> Bool { true }

        var host: UIHostingController<AnyView>?
        weak var scroll: UIScrollView?
        weak var lasso: LassoGestureRecognizer?
        var onZoomSettled: (CGFloat) -> Void
        var onVisibleRectChange: ((CGRect, CGSize) -> Void)?
        var bottomChrome: CGFloat = 0
        private var lastReportedVisible: CGRect = .zero
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
            //
            // With NO old content there is no "same music" to keep, and the
            // proportional default was 0.5 -- the middle. On a page that is
            // invisible: the page is the width of the viewport, so the centred
            // offset clamps straight back to the left edge. On the continuous
            // strip, which is the whole score laid end to end, the middle is
            // the middle of the PIECE: opening a score in continuous mode
            // landed the reader at bar 68, on a staff running off both edges
            // with no clef in sight. A first layout starts at the beginning.
            //
            // `goToOrigin` is the same fault one step later. Switching to
            // continuous keeps the PAGES up until the strip is engraved -- so
            // this runs a second time, with a real old content size (one page
            // wide) and a new one forty times it, and a proportional anchor
            // then means the middle of the piece all over again. The caller
            // says when the content is different music rather than the same
            // music re-drawn; see `resetPan`.
            let old = scroll.contentSize
            let keepPlace = !goToOrigin
            goToOrigin = false
            let anchor = CGPoint(
                x: keepPlace && old.width > 0
                    ? (scroll.contentOffset.x + scroll.bounds.width / 2) / old.width : 0,
                y: keepPlace && old.height > 0
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

        var onTap: ((Int, CGPoint, Int, Bool) -> Void)?
        var onCanvasTap: ((CanvasTap.Touch) -> Void)?
        var onLoupe: ((LoupeSample?) -> Void)?
        weak var turn: TurnTapRecognizer?
        private var pressSample: UIImage?

        /// Sample the canvas once, then follow the finger over the sample.
        ///
        /// Once, because re-drawing the hierarchy on every touchesMoved would
        /// put a full-screen render in the middle of a gesture. §10.3 accepts
        /// a held picture anyway -- and a press cannot change what is under it
        /// except by moving, which moves the window over the same sample.
        func pressed(_ point: CGPoint?) {
            guard let point, let scroll else {
                pressSample = nil
                onLoupe?(nil)
                return
            }
            if pressSample == nil {
                let renderer = UIGraphicsImageRenderer(bounds: scroll.bounds)
                pressSample = renderer.image { _ in
                    scroll.drawHierarchy(in: scroll.bounds, afterScreenUpdates: false)
                }
            }
            guard let pressSample else { return }
            onLoupe?(LoupeSample(image: pressSample, touch: point,
                                 canvas: scroll.bounds.size,
                                 zoom: scroll.zoomScale))
        }
        var onSwipeTurn: ((Int) -> Void)?
        private var lastResetToken: Int = -1
        /// Set by `resetPan`, consumed by the next `commit`: the content about
        /// to be laid out is different music, so there is no place to keep.
        private var goToOrigin = false

        private var lastScrollToken = -1

        /// Move to an x offset in CONTENT coordinates, once per token.
        ///
        /// Content coordinates, not the scroll view's: the caller works in the
        /// surface the strip was laid out in, and the zoom between the two is
        /// this object's business, not the caller's.
        func scrollHorizontally(to x: CGFloat, token: Int) {
            guard token != lastScrollToken, let scroll else { return }
            lastScrollToken = token
            let zoomed = x * scroll.zoomScale
            let furthest = max(scroll.contentSize.width - scroll.bounds.width, 0)
            let clamped = min(max(zoomed, -scroll.contentInset.left), furthest)
            scroll.setContentOffset(CGPoint(x: clamped, y: scroll.contentOffset.y),
                                    animated: true)
        }

        /// A turn landed, or the canvas is showing different music: go to the
        /// top-left, keeping the zoom.
        ///
        /// The offset is moved now AND the next layout is told not to restore
        /// a proportional place. Both are needed: a turn changes only the
        /// offset, but a change of layout changes the content SIZE as well, and
        /// the new size arrives one engrave later.
        func resetPan(token: Int) {
            guard token != lastResetToken else { return }
            let first = lastResetToken == -1
            lastResetToken = token
            guard let scroll, !first else { return }
            goToOrigin = true
            scroll.setContentOffset(CGPoint(x: -scroll.contentInset.left,
                                            y: -scroll.contentInset.top),
                                    animated: false)
        }

        /// Is there any horizontal room left to pan?
        ///
        /// Stop-at-edge (Ali's answer to the open question): a drag that
        /// reaches the page's edge stops dead rather than rolling into a turn.
        /// A reader zoomed into a notehead does not want the page to fly away,
        /// and the tap zones are always a tap away.
        var atHorizontalLimit: Bool {
            guard let scroll else { return true }
            let slack = scroll.contentSize.width - scroll.bounds.width
            guard slack > 1 else { return true }
            let x = scroll.contentOffset.x
            return x <= 1 || x >= slack - 1
        }

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
            onTap?(hit.index, hit.unit, recognizer.numberOfTapsRequired,
                   lasso?.isModifierFingerDown ?? false)
        }

        /// The lasso's own state changes need do nothing to the canvas: the
        /// freeze is keyed on the Pencil being DOWN, which starts earlier (the
        /// moment it touches) and ends later (when it lifts) than the stroke.
        @objc func lassoFired(_ recognizer: LassoGestureRecognizer) {}

        @objc func turnTapped(_ recognizer: TurnTapRecognizer) {
            guard let root = recognizer.view else { return }
            if let swipe = recognizer.swipe {
                // live only when there is no horizontal slack: at fit there is
                // nothing to pan, so a drag is free to mean a turn
                guard let scroll,
                      PagedCanvas.swipeMayTurn(
                          zoom: scroll.zoomScale,
                          atLimitWhenItBegan: recognizer.limitAtStart)
                else { return }
                onSwipeTurn?(swipe)
                return
            }
            guard recognizer.state == .ended else { return }
            let hit = LassoGestureRecognizer.page(at: recognizer.landed, in: root)
            onCanvasTap?(CanvasTap.Touch(
                point: recognizer.landed,
                canvas: root.bounds.size,
                isPencil: recognizer.wasPencil,
                maxFingers: recognizer.maxFingers,
                movement: recognizer.movement,
                elapsed: recognizer.elapsed,
                wasPress: recognizer.wasPress,
                page: hit.map { (index: $0.index, unit: $0.unit) }))
        }

        var onUserScroll: (() -> Void)?
        private weak var scroller: CanvasScroller?

        /// Hand the play head a way in. Weak on the way back, so a scroll view
        /// that has gone cannot be moved by a sound that is still playing.
        func installScroller(_ scroller: CanvasScroller?) {
            guard scroller !== self.scroller else { return }
            if let previous = self.scroller, previous !== scroller { previous.uninstall(owner: self) }
            self.scroller = scroller
            scroller?.install(owner: self) { [weak self] playheadX in
                guard let scroll = self?.scroll, scroll.bounds.width > 0 else { return }
                // The LIVE viewport and content size, read here at the moment
                // of the move -- never a cached width. See CanvasScroller for
                // the stuck state a cached zero produced.
                let offset = Playhead.stripOffset(playheadX: playheadX * scroll.zoomScale,
                                                  viewportWidth: scroll.bounds.width,
                                                  surfaceWidth: scroll.contentSize.width)
                let clamped = max(offset, -scroll.contentInset.left)
                let now = Date()
                if now.timeIntervalSince(zoomableScrollLastParkLog) > 1 {
                    zoomableScrollLastParkLog = now
                    Logger(subsystem: "com.irllabs.scoranger", category: "follow").notice(
                        "park: playheadX=\(playheadX, privacy: .public) zoom=\(scroll.zoomScale, privacy: .public) bounds=\(scroll.bounds.width, privacy: .public) content=\(scroll.contentSize.width, privacy: .public) offset=\(clamped, privacy: .public) current=\(scroll.contentOffset.x, privacy: .public)")
                }
                guard abs(clamped - scroll.contentOffset.x) > 0.5 else { return }
                // NOT animated, and NOT setContentOffset(animated:): at twenty
                // a second each animation is overtaken by the next and the
                // score lurches. Small steps, every step, is what smooth is.
                scroll.contentOffset = CGPoint(x: clamped, y: scroll.contentOffset.y)
            }
        }

        deinit { scroller?.uninstall(owner: self) }

        /// A hand on the score. UIScrollView calls this only for a real drag,
        /// which is exactly the distinction the follow gate needs -- every move
        /// this view makes itself goes through `contentOffset` and is silent.
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            onUserScroll?()
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host?.view }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            recentre()
            publishZoom(scrollView)
            reportVisible(scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            reportVisible(scrollView)
        }

        /// The viewport in content coordinates: what is on screen divided by
        /// the zoom, because the hosted view is scaled by a transform and its
        /// own geometry never changes.
        private func reportVisible(_ scrollView: UIScrollView) {
            let scale = max(scrollView.zoomScale, 0.0001)
            let rect = CGRect(x: scrollView.contentOffset.x / scale,
                              y: scrollView.contentOffset.y / scale,
                              width: scrollView.bounds.width / scale,
                              height: scrollView.bounds.height / scale)
            // Only on a real move: this fires continuously through a pan, and
            // re-rendering the page stack on every frame is what the eager
            // layout was avoiding in the first place.
            // x as well as y: the bar readout follows a SIDEWAYS pan across a
            // zoomed page, and a guard that watched only the vertical never
            // reported one.
            guard abs(rect.minY - lastReportedVisible.minY) > 24
                    || abs(rect.minX - lastReportedVisible.minX) > 24
                    || abs(rect.height - lastReportedVisible.height) > 24
                    || abs(rect.width - lastReportedVisible.width) > 24
                    || lastReportedVisible == .zero else { return }
            lastReportedVisible = rect
            // the content in the SAME space as the rect, so a caller can
            // normalise: the scroll view's content coordinates are not the
            // SwiftUI layout's, and mapping between them by assumption put the
            // bar readout eight pages wide
            onVisibleRectChange?(rect, CGSize(width: scrollView.contentSize.width / scale,
                                              height: scrollView.contentSize.height / scale))
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


/// A finished single-finger touch, reported wherever and however it ended.
///
/// Deliberately not a `UITapGestureRecognizer`: that one competes with the
/// others for the same touch, and this must never take a touch away from the
/// lasso or the scroll. What the touch MEANT is `CanvasTap`'s answer, and its
/// alone (§12).
///
/// It used to end every touch by RESETTING ITSELF TO `.failed` in a `defer`,
/// under the heading "never claim the touch". It never fired, then: a
/// recogniser that fails sends no action, so the assignment two lines above it
/// was undone before UIKit could act on it. A finger tap on the outer zone
/// therefore did nothing at all, on any device, for as long as the rule
/// existed -- found by instrumenting the recogniser when a tap-select sweep
/// down a phone page landed nothing at 17 points out of 17.
///
/// Not claiming the touch is what `cancelsTouchesInView = false`,
/// `delaysTouchesBegan = false` and simultaneous recognition are FOR, and all
/// three are set. Recognising is what makes the action fire.
///
/// It reports every single-finger end, including ones that moved or dwelt and
/// ones that were part of a pinch, because the rule that rejects them is in
/// the pure function where it can be fuzzed. What is left here is measurement:
/// where it landed, how far it moved, how long it took, and the most fingers
/// that were ever down.
final class TurnTapRecognizer: UIGestureRecognizer {
    private(set) var landed: CGPoint = .zero
    private(set) var wasPencil = false
    /// -1 or +1 when the touch was a decisive horizontal swipe, nil otherwise.
    /// Whether it MAY turn is decided by the caller, which knows about zoom and
    /// slack; this only reports the shape of the gesture.
    private(set) var swipe: Int?
    /// The most fingers down at any moment of THIS touch. A pinch whose second
    /// finger lifts first still ends as one finger on the glass, and without
    /// this it would be indistinguishable from a tap.
    private(set) var maxFingers = 1
    private(set) var movement: CGFloat = 0
    private(set) var elapsed: TimeInterval = 0
    /// The finger stayed still long enough to raise the loupe.
    private(set) var wasPress = false
    /// While the lasso is armed the finger belongs to it: no press, no loupe,
    /// and nothing for this recogniser to report (§9.3).
    var armed = false

    /// Was the canvas already hard against its horizontal limit when this
    /// touch started? Asked once, at touch-down, because asking at the end
    /// makes every long pan into a turn (`PagedCanvas.swipeMayTurn`).
    private(set) var limitAtStart = false
    /// How the recogniser asks. Supplied by the coordinator, which owns the
    /// scroll view.
    var atLimitNow: (() -> Bool)?

    /// Everything `TapSelection.allowsPress` needs that the recogniser cannot
    /// see for itself. The finger count is its own (§13).
    var mode: ScoreMode = .read
    var voiceOverRunning = false
    var inking = false

    /// Where the finger is while a press is live, and nil the moment it is
    /// not. The canvas puts the loupe there (§9.2).
    var onPress: ((CGPoint?) -> Void)?
    private var pressTimer: Timer?
    private var start: CGPoint = .zero
    private var began: TimeInterval = 0
    private var moved: CGFloat = 0
    private var dx: CGFloat = 0
    private var dy: CGFloat = 0

    /// A swipe is decisive: far enough to be deliberate, and much more across
    /// than down, so a diagonal pan is never mistaken for one.
    private static let swipeDistance: CGFloat = 60
    private static let swipeRatio: CGFloat = 1.8

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        // A touch CYCLE starts when the glass goes from empty to one finger.
        // Counting here rather than trusting `reset()`: UIKit resets a failed
        // recogniser as soon as its own recognition ends, which during a pinch
        // is while the other finger is still down -- and a count cleared there
        // would say "one finger" for the rest of the pinch.
        let down = event.allTouches?.filter {
            $0.phase != .ended && $0.phase != .cancelled
        }.count ?? touches.count
        guard down <= 1 else {
            maxFingers = max(maxFingers, down)
            // a second finger ends any press: this is a pinch now
            endPress()
            if state == .began || state == .changed { state = .cancelled }
            return
        }
        guard let root = view, let touch = touches.first else { return }
        maxFingers = 1
        limitAtStart = atLimitNow?() ?? false
        start = touch.location(in: root)
        began = touch.timestamp
        moved = 0
        dx = 0
        dy = 0
        movement = 0
        elapsed = 0
        swipe = nil
        wasPress = false
        wasPencil = touch.type == .pencil
        armPress()
    }

    /// Raise the loupe if the finger is still there, and still still.
    ///
    /// This is the one place the recogniser CLAIMS a touch. Everywhere else it
    /// fails on purpose, so it can never take a touch from the lasso or the
    /// scroll -- but a press that let the page scroll under it would make the
    /// crosshair meaningless, so from here the finger belongs to the selection
    /// and `.began` cancels the pan in flight.
    private func armPress() {
        pressTimer?.invalidate()
        guard !wasPencil, !armed, pressAllowed else { return }
        pressTimer = Timer.scheduledTimer(
            withTimeInterval: TapSelection.pressDelay, repeats: false
        ) { [weak self] _ in
            guard let self, self.view != nil, self.pressAllowed,
                  TapSelection.mayBecomePress(movedBeforeDelay: self.moved),
                  self.state == .possible else { return }
            self.wasPress = true
            self.state = .began
            self.onPress?(self.here)
        }
    }

    /// ONE predicate for the press and the loupe, so they cannot drift into
    /// a selection committed blind (§13).
    private var pressAllowed: Bool {
        TapSelection.allowsPress(mode: mode, voiceOver: voiceOverRunning,
                                 fingers: maxFingers, inking: inking)
    }

    private var here: CGPoint { CGPoint(x: start.x + dx, y: start.y + dy) }

    private func endPress() {
        pressTimer?.invalidate()
        pressTimer = nil
        if wasPress { onPress?(nil) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let root = view, let touch = touches.first else { return }
        let now = touch.location(in: root)
        moved = max(moved, hypot(now.x - start.x, now.y - start.y))
        dx = now.x - start.x
        dy = now.y - start.y
        if wasPress {
            state = .changed
            onPress?(now)                     // the loupe follows the finger
        } else if moved > PageTurn.tapSlop {
            pressTimer?.invalidate()          // it was a pan after all
            pressTimer = nil
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        endPress()
        guard let root = view, let touch = touches.first else {
            state = .failed
            return
        }
        landed = touch.location(in: root)
        movement = moved
        elapsed = touch.timestamp - began
        // a decisive horizontal swipe, by ONE FINGER: the Pencil's meaning is
        // settled by mode, and a Pencil drag is a lasso or ink
        if !wasPress, maxFingers <= 1, touch.type != .pencil,
           abs(dx) >= Self.swipeDistance,
           abs(dx) >= abs(dy) * Self.swipeRatio {
            swipe = dx < 0 ? 1 : -1     // dragging left brings the NEXT page in
            state = .ended
            return
        }
        swipe = nil
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        endPress()
        wasPress = false
        state = .failed
    }

    override func reset() {
        super.reset()
        moved = 0
        dx = 0
        dy = 0
        swipe = nil
        wasPress = false
        pressTimer?.invalidate()
        pressTimer = nil
        // `maxFingers` is deliberately NOT cleared here -- see touchesBegan.
    }
}
