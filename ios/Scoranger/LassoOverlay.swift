import SwiftUI
import UIKit

/// Recognizes the finger-held Pencil lasso.
///
/// It lives on the scroll view rather than on a page, because a recognizer only
/// sees touches delivered into its own view tree and the scroll view is the one
/// ancestor of everything on the canvas. `cancelsTouchesInView` is on: once the
/// lasso takes over, the PencilKit canvas underneath is sent `touchesCancelled`
/// and no ink is left behind by a gesture that meant "select".
final class LassoGestureRecognizer: UIGestureRecognizer {
    /// Called once, when the lasso closes: (page index, unit (0…1) points).
    /// There is deliberately no per-sample callback — see LassoAnchorView.
    var onEnd: ((Int, [CGPoint]) -> Void)?
    var arbiter = LassoArbiter()

    private var pencilTouch: UITouch?
    private var points: [CGPoint] = []
    private var anchor: LassoAnchorView?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = true
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches where touch.type == .direct && pencilTouch == nil {
            arbiter.fingers += 1
        }
        guard pencilTouch == nil else { return }
        for touch in touches {
            let isPencil = touch.type == .pencil
            guard arbiter.shouldBeginLasso(pencil: isPencil) else { continue }
            guard let anchor = anchor(under: touch) else { continue }
            self.anchor = anchor
            pencilTouch = touch
            points = [touch.location(in: anchor)]
            state = .began
            draw()
            return
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let pencilTouch, touches.contains(pencilTouch), let anchor else { return }
        points.append(pencilTouch.location(in: anchor))
        state = .changed
        draw()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches where touch.type == .direct {
            arbiter.fingers = max(0, arbiter.fingers - 1)
        }
        guard let pencil = pencilTouch, touches.contains(pencil) else { return }
        if let anchor { points.append(pencil.location(in: anchor)) }
        // a dot is not a lasso
        if points.count > 2, let anchor {
            onEnd?(anchor.pageIndex, unitPoints(in: anchor))
        } else {
            anchor?.show([])
        }
        finish(.ended)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches where touch.type == .direct {
            arbiter.fingers = max(0, arbiter.fingers - 1)
        }
        guard let pencil = pencilTouch, touches.contains(pencil) else { return }
        anchor?.show([])
        finish(.cancelled)
    }

    override func reset() {
        super.reset()
        pencilTouch = nil
        points = []
        anchor = nil
    }

    private func finish(_ end: UIGestureRecognizer.State) {
        state = end
        pencilTouch = nil
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

    private let shape = CAShapeLayer()
    /// Unit (0…1) points, live or committed.
    private var path: [CGPoint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        shape.fillColor = UIColor(Theme.Accent.clay).withAlphaComponent(0.10).cgColor
        shape.strokeColor = UIColor(Theme.Accent.clay).cgColor
        shape.lineWidth = 1.5
        shape.lineDashPattern = [6, 3]
        shape.lineJoin = .round
        layer.addSublayer(shape)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
