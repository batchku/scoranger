import SwiftUI
import UIKit

/// Recognizes the hold-then-drag lasso, and the two-finger undo tap.
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
    var onEnd: ((Int, [CGPoint], Bool) -> Void)?
    /// Called when two fingers tap without moving: undo the last ink stroke.
    var onUndoTap: (() -> Void)?
    /// Markup mode. It changes what the PENCIL does and nothing else.
    var annotationActive = false

    /// The touch drawing the lasso, once one has been chosen.
    private var drawing: UITouch?
    /// Every touch currently down, with where and when it landed, so the gate
    /// can be asked what the user is doing.
    private var down: [UITouch: (origin: CGPoint, time: TimeInterval)] = [:]
    private var points: [CGPoint] = []
    private var anchor: LassoAnchorView?
    private var holdTimer: Timer?
    private var adding = false
    /// Touches that started moving before the hold elapsed: they are dragging
    /// the page, and must go on dragging it however long they stay down.
    private var scrolling: Set<UITouch> = []

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = true
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    /// How far a touch has travelled from where it landed.
    private func travel(_ touch: UITouch) -> CGFloat {
        guard let root = view, let start = down[touch]?.origin else { return 0 }
        let now = touch.location(in: root)
        return hypot(now.x - start.x, now.y - start.y)
    }

    /// The Pencil currently down, if any. It outranks every finger: outside
    /// markup mode PencilKit takes no touches, so a hand resting beside the
    /// Pencil arrives here as an ordinary direct touch and would otherwise
    /// count as a second finger.
    private var pencilTouch: UITouch? {
        down.keys.first { $0.type == .pencil }
    }

    private var fingerCount: Int {
        down.keys.filter { $0.type == .direct }.count
    }

    private var effectiveTouches: Int {
        LassoGate.effectiveTouchCount(fingers: fingerCount, pencilDown: pencilTouch != nil)
    }

    private func report(_ touch: UITouch, phase: String, began: Bool = false) {
        let kind = touch.type == .pencil ? "pencil" : "finger"
        let line = TouchDiagnostics.describe(
            kind: kind, phase: phase, fingers: fingerCount,
            pencilDown: pencilTouch != nil, heldFor: elapsed(touch),
            markupActive: annotationActive, began: began)
        Task { @MainActor in
            TouchDiagnostics.shared.record(line)
            TouchDiagnostics.shared.setCurrent(line)
        }
    }

    private func elapsed(_ touch: UITouch) -> TimeInterval {
        guard let started = down[touch]?.time else { return 0 }
        return touch.timestamp - started
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let root = view else { return }
        for touch in touches {
            down[touch] = (touch.location(in: root), touch.timestamp)
        }
        for touch in touches { report(touch, phase: "began") }

        // The deciding touch is the Pencil if there is one -- never
        // `touches.first`, which is an arbitrary member of an unordered set.
        guard drawing == nil, let touch = pencilTouch ?? touches.first(where: { $0.type == .direct }),
              LassoGate.lassoStart(isPencil: touch.type == .pencil,
                                   markupActive: annotationActive) != .never,
              effectiveTouches == 1
        else { return }
        armHold(for: touch)
    }

    /// A haptic at the moment the hold takes, and nothing else.
    ///
    /// The decision itself is made in `touchesMoved`, because a timer cannot be
    /// relied on here: `Timer.scheduledTimer` installs into the run loop's
    /// DEFAULT mode, and while a finger is down on a scroll view UIKit runs the
    /// loop in TRACKING mode, where it never fires. That is why selection did
    /// not work on a real device in 0.2.3 while passing in the simulator, whose
    /// synthesized events take a different path. This timer is scheduled in
    /// `.common` so it fires during tracking too -- but if it were starved
    /// again, the only thing lost would be the tap on the wrist.
    private func armHold(for touch: UITouch) {
        holdTimer?.invalidate()
        let timer = Timer(timeInterval: LassoGate.holdThreshold, repeats: false) {
            [weak self, weak touch] _ in
            guard let self, let touch, self.down[touch] != nil,
                  self.drawing == nil, !self.scrolling.contains(touch),
                  self.travel(touch) <= LassoGate.moveSlop else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    private func beginLasso(with touch: UITouch, adding: Bool) {
        guard let anchor = anchor(under: touch) else { return }
        self.anchor = anchor
        self.adding = adding
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

        // The hold is judged here, when the touch starts moving, because a
        // timer is starved while the scroll view is tracking. A finger that
        // travelled before the threshold is scrolling and stays scrolling; a
        // Pencil has nothing to disambiguate from, because it cannot scroll.
        if drawing == nil, effectiveTouches == 1,
           let touch = pencilTouch ?? touches.first(where: { $0.type == .direct }),
           down[touch] != nil, touches.contains(touch) {
            switch LassoGate.lassoStart(isPencil: touch.type == .pencil,
                                        markupActive: annotationActive) {
            case .never:
                break
            case .immediately:
                report(touch, phase: "moved", began: true)
                beginLasso(with: touch, adding: false)
                return
            case .afterHold:
                if LassoGate.disqualifiesLasso(elapsed: elapsed(touch),
                                               movement: travel(touch)) {
                    scrolling.insert(touch)
                    report(touch, phase: "moved(scrolling)")
                } else if LassoGate.shouldBeginLassoOnMove(
                            heldFor: elapsed(touch), touches: effectiveTouches,
                            disqualified: scrolling.contains(touch)) {
                    report(touch, phase: "moved", began: true)
                    beginLasso(with: touch, adding: false)
                    return
                }
            }
        }

        // Two fingers, one of them parked: the moving one draws and adds. Both
        // moving is a pinch, which belongs to the scroll view — so this stays
        // undecided until one of them commits.
        guard drawing == nil, down.count == 2 else { return }
        let ordered = down.keys.sorted { (down[$0]?.time ?? 0) < (down[$1]?.time ?? 0) }
        guard let first = ordered.first, let second = ordered.last, first != second else { return }
        if LassoGate.combine(firstMovement: travel(first),
                             secondMovement: travel(second)) == .add {
            beginLasso(with: second, adding: true)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        // two fingers tapped and gone, having barely moved: undo
        if drawing == nil, down.count == 2,
           let sample = touches.first,
           LassoGate.isUndoTap(touches: down.count,
                               movement: down.keys.map(travel).max() ?? 0,
                               elapsed: elapsed(sample)) {
            onUndoTap?()
        }
        for touch in touches { report(touch, phase: "ended") }
        defer { for touch in touches { down[touch] = nil; scrolling.remove(touch) } }
        guard let drawing, touches.contains(drawing) else { return }
        if let anchor { points.append(drawing.location(in: anchor)) }
        if points.count > 2, let anchor {          // a dot is not a lasso
            onEnd?(anchor.pageIndex, unitPoints(in: anchor), adding)
        } else {
            anchor?.show([])
        }
        finish(.ended)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        defer { for touch in touches { down[touch] = nil } }
        guard let drawing, touches.contains(drawing) else { return }
        anchor?.show([])
        finish(.cancelled)
    }

    override func reset() {
        super.reset()
        holdTimer?.invalidate()
        holdTimer = nil
        drawing = nil
        points = []
        anchor = nil
        adding = false
        down.removeAll()
        scrolling.removeAll()
    }

    private func finish(_ end: UIGestureRecognizer.State) {
        state = end
        holdTimer?.invalidate()
        holdTimer = nil
        drawing = nil
        points = []
        anchor = nil
        adding = false
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
        shape.lineWidth = 1.5
        shape.lineDashPattern = [6, 3]
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
    /// Whether the next lasso removes rather than adds.
    var subtracting: Bool = false

    func makeUIView(context: Context) -> LassoAnchorView {
        let view = LassoAnchorView()
        view.pageIndex = pageIndex
        view.isSubtracting = subtracting
        return view
    }

    func updateUIView(_ view: LassoAnchorView, context: Context) {
        view.pageIndex = pageIndex
        view.isSubtracting = subtracting
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
