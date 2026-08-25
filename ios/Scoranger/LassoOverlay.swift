import SwiftUI
import UIKit

/// Recognizes the Pencil lasso, and the two-finger undo tap.
///
/// It lives on the scroll view rather than on a page, because a recognizer only
/// sees touches delivered into its own view tree and the scroll view is the one
/// ancestor of everything on the canvas. That is also why the undo tap lives
/// here now: on the PencilKit canvas it only saw touches while markup mode was
/// on, which is why it felt lost. `cancelsTouchesInView` is on: once the
/// lasso takes over, the PencilKit canvas underneath is sent `touchesCancelled`
/// and no ink is left behind by a gesture that meant "select".
final class LassoGestureRecognizer: UIGestureRecognizer {
    /// Called once, when the lasso closes: (page index, unit (0…1) points,
    /// whether this stroke adds to what is already selected).
    /// There is deliberately no per-sample callback — see LassoAnchorView.
    /// `adding` is always false now: what a lasso does to the existing
    /// selection is the chip's Replace/Add/Subtract mode, not a second finger.
    var onEnd: ((Int, [CGPoint], Bool) -> Void)?
    /// Called when two fingers tap without moving: undo the last ink stroke.
    var onUndoTap: (() -> Void)?
    /// A Pencil went down or came up. The canvas freezes while it is down, so
    /// the resting hand cannot pan the page out from under the stroke.
    var onPencilPresence: ((Bool) -> Void)?
    /// The Pencil has landed and this stroke will REPLACE the selection: clear
    /// it now, not when the lasso closes.
    var onWillReplaceSelection: (() -> Void)?
    /// Markup mode. It changes what the PENCIL does and nothing else.
    var annotationActive = false

    /// Lets a UI test drive the selection pipeline with a finger.
    ///
    /// Stated plainly, because a stand-in like this is how the previous scheme
    /// fooled itself: with this on, the tests exercise everything downstream of
    /// touch classification — which page the lasso landed on, the unit points,
    /// the hit test, the selection, the chip, the handoff to chat — and they do
    /// NOT exercise Pencil input, which no simulator can produce. The
    /// classification itself is covered by `LassoGateTests`.
    static let fingerStandsInForPencil =
        ProcessInfo.processInfo.arguments.contains("-uiTestPencil")

    private func isPencil(_ touch: UITouch) -> Bool {
        touch.type == .pencil || (Self.fingerStandsInForPencil && touch.type == .direct)
    }

    /// The touch drawing the lasso, once one has been chosen.
    private var drawing: UITouch?
    /// Whether the stroke in progress adds to the selection, decided once at
    /// touchdown and never revisited -- a finger lifted mid-stroke must not
    /// change what the stroke means.
    private var addsToSelection = false
    /// Every touch currently down, with where and when it landed.
    private var down: [UITouch: (origin: CGPoint, time: TimeInterval)] = [:]
    private var points: [CGPoint] = []
    private var anchor: LassoAnchorView?
    /// What the canvas was last told, so the freeze is reported on change only.
    private var canvasFrozen = false

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = true
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        // Recognize alongside the scroll view's own gestures rather than
        // competing with them.
        //
        // With no finger down this never mattered: the Pencil cannot pan, so
        // nothing was contending and the lasso began unopposed. Hold a finger
        // first, though, and the scroll view's pan is already tracking that
        // finger when the Pencil lands -- and two recognizers on one view do
        // not both recognize unless something says they may. That is a whole
        // class of "the Pencil does nothing while I hold a finger", and it
        // costs nothing to rule out: the Pencil cannot pan, and panning is off
        // entirely while it is down, so there is no gesture left to conflict.
        delegate = simultaneous
    }

    private let simultaneous = SimultaneousDelegate()

    private final class SimultaneousDelegate: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }

    /// How far a touch has travelled from where it landed.
    private func travel(_ touch: UITouch) -> CGFloat {
        guard let root = view, let start = down[touch]?.origin else { return 0 }
        let now = touch.location(in: root)
        return hypot(now.x - start.x, now.y - start.y)
    }

    private var pencilTouch: UITouch? {
        down.keys.first { isPencil($0) }
    }

    private var fingerCount: Int {
        down.keys.filter { !isPencil($0) }.count
    }

    private func elapsed(_ touch: UITouch) -> TimeInterval {
        guard let started = down[touch]?.time else { return 0 }
        return touch.timestamp - started
    }

    /// Is a finger of the OTHER hand resting on the page?
    ///
    /// Small contact AND far from the Pencil tip. Either signal alone is
    /// wrong: a hand turned sideways rests well away from the tip and is still
    /// a palm, and a fingertip of the Pencil hand can come to rest right
    /// beside it. Thresholds are provisional (see LassoGate) until measured on
    /// real hardware -- the diagnostics readout prints both numbers for
    /// exactly that.
    /// Readable from outside so a TAP can mean "add this element" while a
    /// finger is held, the same way a drag means "add what I enclose".
    var isModifierFingerDown: Bool { modifierFingerDown }

    private var modifierFingerDown: Bool {
        guard let root = view, let pencil = pencilTouch else { return false }
        let tip = pencil.location(in: root)
        return down.keys.contains { touch in
            guard !isPencil(touch) else { return false }
            let p = touch.location(in: root)
            return LassoGate.isDeliberateModifierFinger(
                radius: touch.majorRadius,
                distanceFromPencil: hypot(p.x - tip.x, p.y - tip.y))
        }
    }

    /// How far this touch is from the Pencil tip, when both are down.
    private func distanceFromPencil(_ touch: UITouch) -> CGFloat? {
        guard let root = view, let pencil = pencilTouch, pencil != touch else { return nil }
        let a = touch.location(in: root), b = pencil.location(in: root)
        return hypot(a.x - b.x, a.y - b.y)
    }

    private func report(_ touch: UITouch, phase: String, began: Bool = false) {
        let isPen = isPencil(touch)
        let kind = isPen ? "pencil" : "finger"
        let line = TouchDiagnostics.describe(
            kind: kind, phase: phase, fingers: fingerCount,
            pencilDown: pencilTouch != nil, heldFor: elapsed(touch),
            markupActive: annotationActive, began: began,
            radius: isPen ? nil : touch.majorRadius,
            distanceFromPencil: isPen ? nil : distanceFromPencil(touch))
        Task { @MainActor in
            TouchDiagnostics.shared.record(line)
            TouchDiagnostics.shared.setCurrent(line)
        }
    }

    /// Freeze the canvas while a Pencil is selecting, thaw it after.
    ///
    /// This is the palm rejection. Outside markup mode PencilKit is not taking
    /// touches, so it is not rejecting anything either, and the hand resting
    /// beside the Pencil reaches the scroll view as an ordinary finger. Turning
    /// scrolling off also cancels a pan already in flight, so a palm that
    /// landed first cannot keep dragging the page once the Pencil arrives.
    private func syncCanvasFreeze() {
        let frozen = !LassoGate.canvasMayMove(pencilDown: pencilTouch != nil,
                                              markupActive: annotationActive)
        guard frozen != canvasFrozen else { return }
        canvasFrozen = frozen
        onPencilPresence?(frozen)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let root = view else { return }
        for touch in touches {
            down[touch] = (touch.location(in: root), touch.timestamp)
        }
        syncCanvasFreeze()
        for touch in touches { report(touch, phase: "began") }

        // Decided here, the instant the Pencil lands: from state alone, with
        // nothing to wait for. A finger already resting means this stroke adds;
        // otherwise the previous selection goes now, so the page never shows a
        // stale highlight underneath a new lasso.
        guard let pencil = pencilTouch, touches.contains(pencil) else { return }
        switch LassoGate.landing(isPencil: true, markupActive: annotationActive,
                                 modifierFingerDown: modifierFingerDown) {
        case .leaveAlone:
            addsToSelection = false
        case .addToExisting:
            addsToSelection = true
        case .replaceNow:
            addsToSelection = false
            onWillReplaceSelection?()
        }
    }

    private func beginLasso(with touch: UITouch) {
        guard let anchor = anchor(under: touch) else { return }
        self.anchor = anchor
        drawing = touch
        points = [touch.location(in: anchor)]
        state = .began
        draw()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let drawing, touches.contains(drawing), let anchor {
            points.append(drawing.location(in: anchor))
            state = .changed
            draw()
            return
        }

        // The Pencil lassos the moment it moves. There is nothing to wait for:
        // it cannot pan the canvas, so a Pencil drag has exactly one meaning.
        // Fingers are not consulted at all -- however many are resting on the
        // glass, and whatever they are doing.
        guard drawing == nil, let touch = pencilTouch, touches.contains(touch),
              LassoGate.lassoBegins(isPencil: true, markupActive: annotationActive)
        else { return }
        report(touch, phase: "moved", began: true)
        beginLasso(with: touch)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        // two fingers tapped and gone, having barely moved: undo
        if drawing == nil, fingerCount == 2, pencilTouch == nil,
           let sample = touches.first,
           LassoGate.isUndoTap(touches: fingerCount,
                               movement: down.keys.map(travel).max() ?? 0,
                               elapsed: elapsed(sample)) {
            onUndoTap?()
        }
        for touch in touches { report(touch, phase: "ended") }
        defer {
            for touch in touches { down[touch] = nil }
            syncCanvasFreeze()
        }
        guard let drawing, touches.contains(drawing) else { return }
        if let anchor { points.append(drawing.location(in: anchor)) }
        if points.count > 2, let anchor {          // a dot is not a lasso
            onEnd?(anchor.pageIndex, unitPoints(in: anchor), addsToSelection)
        } else {
            anchor?.show([])
        }
        finish(.ended)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        defer {
            for touch in touches { down[touch] = nil }
            syncCanvasFreeze()
        }
        guard let drawing, touches.contains(drawing) else { return }
        anchor?.show([])
        finish(.cancelled)
    }

    override func reset() {
        super.reset()
        drawing = nil
        points = []
        anchor = nil
        addsToSelection = false
        down.removeAll()
        syncCanvasFreeze()
    }

    private func finish(_ end: UIGestureRecognizer.State) {
        state = end
        drawing = nil
        points = []
        anchor = nil
    }

    /// Live feedback, straight into the layer.
    private func draw() {
        guard let anchor else { return }
        anchor.show(unitPoints(in: anchor))
    }

    private func unitPoints(in anchor: LassoAnchorView) -> [CGPoint] {
        let size = anchor.bounds.size
        guard size.width > 0, size.height > 0 else { return [] }
        return points.map { CGPoint(x: $0.x / size.width, y: $0.y / size.height) }
    }

    /// Which page the gesture started on. Pages announce themselves by being in
    /// the tree, so nothing has to be registered or kept in sync.
    private func anchor(under touch: UITouch) -> LassoAnchorView? {
        guard let root = view else { return nil }
        let point = touch.location(in: root)
        return Self.anchors(in: root).first { anchor in
            anchor.convert(anchor.bounds, to: root).contains(point)
        }
    }

    /// The page under a point in the recognizer's own view, and where in that
    /// page the point falls, in unit (0…1) coordinates. Shared with the tap
    /// that drops one element from the selection.
    static func page(at point: CGPoint, in root: UIView) -> (index: Int, unit: CGPoint)? {
        for anchor in anchors(in: root) {
            let frame = anchor.convert(anchor.bounds, to: root)
            guard frame.contains(point), frame.width > 0, frame.height > 0 else { continue }
            return (anchor.pageIndex,
                    CGPoint(x: (point.x - frame.minX) / frame.width,
                            y: (point.y - frame.minY) / frame.height))
        }
        return nil
    }

    private static func anchors(in view: UIView) -> [LassoAnchorView] {
        var found: [LassoAnchorView] = []
        if let anchor = view as? LassoAnchorView { found.append(anchor) }
        for subview in view.subviews { found.append(contentsOf: anchors(in: subview)) }
        return found
    }
}

/// A page's presence in the view tree, its coordinate space, and the lasso
/// drawn on it.
///
/// It draws the live path itself, in UIKit. Pushing every Pencil sample through
/// `@Published` state re-rendered the whole page stack per touch — eight pages
/// of rasterized music — and the watchdog killed the app mid-gesture. State is
/// written once, when the lasso closes.
final class LassoAnchorView: UIView {
    var pageIndex: Int = 0
    /// A lasso that removes is drawn in the removing colour, so the gesture
    /// never looks like the one that adds.
    var isSubtracting = false {
        didSet { if isSubtracting != oldValue { applyColours() } }
    }

    private let shape = CAShapeLayer()
    /// Unit (0…1) points, live or committed.
    private var path: [CGPoint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        // Fine rather than crude: at 1.5pt with 6pt dashes the outline read as
        // a marquee drawn over the music. A hairline with short dashes sits
        // with the engraving instead of on top of it.
        shape.lineWidth = 0.75
        shape.lineDashPattern = [2.5, 2.5]
        shape.lineJoin = .round
        applyColours()
        layer.addSublayer(shape)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func applyColours() {
        let tint = UIColor(isSubtracting ? Theme.Status.danger : Theme.Accent.clay)
        shape.fillColor = tint.withAlphaComponent(0.10).cgColor
        shape.strokeColor = tint.cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shape.frame = bounds
        redraw()
    }

    /// Unit points, from the recognizer while drawing or from state once
    /// committed. Same drawing either way.
    func show(_ unitPoints: [CGPoint]) {
        guard unitPoints != path else { return }
        path = unitPoints
        redraw()
    }

    private func redraw() {
        guard path.count > 1, bounds.width > 0, bounds.height > 0 else {
            shape.path = nil
            return
        }
        let mapped = path.map { CGPoint(x: $0.x * bounds.width, y: $0.y * bounds.height) }
        let bezier = UIBezierPath()
        bezier.move(to: mapped[0])
        for point in mapped.dropFirst() { bezier.addLine(to: point) }
        bezier.close()
        shape.path = bezier.cgPath
    }
}

struct LassoAnchor: UIViewRepresentable {
    let pageIndex: Int
    /// The committed lasso for this page, if any.
    let committed: [CGPoint]
    func makeUIView(context: Context) -> LassoAnchorView {
        let view = LassoAnchorView()
        view.pageIndex = pageIndex
        return view
    }

    func updateUIView(_ view: LassoAnchorView, context: Context) {
        view.pageIndex = pageIndex
        view.show(committed)
    }
}

/// The lasso as drawn — live while the Pencil moves, and again once committed
/// so the user can see what they caught.
struct LassoShape: Shape {
    /// Unit (0…1) page coordinates.
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        let mapped = points.map { CGPoint(x: $0.x * rect.width, y: $0.y * rect.height) }
        path.move(to: mapped[0])
        for point in mapped.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}
