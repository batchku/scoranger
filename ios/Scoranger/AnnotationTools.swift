import PencilKit
import SwiftUI

/// Annotation mode for the score pages.
///
/// Off (the default) the score behaves like a document: fingers scroll and
/// pinch, and the Pencil does nothing. On, the Pencil draws or erases and a
/// floating bar offers the tool, the colour and undo.
///
/// Undo is PencilKit's own, reached through a canvas that supplies its own
/// UndoManager. The previous version kept a parallel stack of prior drawings
/// keyed by page, which drifted out of step with the canvas: the canvases were
/// held weakly and were rebuilt whenever the hosted SwiftUI tree churned (a
/// colour change was enough), so an undo could restore state into a canvas that
/// no longer existed while the visible one kept the stroke -- the reported bug
/// where an undone line came back after switching colours. PencilKit's manager
/// is attached to the live canvas by construction and cannot drift.
@MainActor
final class AnnotationController: ObservableObject {

    enum Tool: String {
        case pen, eraser
    }

    /// A small fixed palette: enough to mark up a part, few enough to tap.
    enum Ink: String, CaseIterable, Identifiable {
        case red, blue, green, orange, black

        var id: String { rawValue }

        /// Fixed by the design system: the user's marks are content, not palette.
        var uiColor: UIColor {
            switch self {
            case .red:    return UIColor(Theme.Pen.red)
            case .blue:   return UIColor(Theme.Pen.blue)
            case .green:  return UIColor(Theme.Pen.green)
            case .orange: return UIColor(Theme.Pen.amber)
            case .black:  return UIColor(Theme.Pen.black)
            }
        }

        var swatch: Color { Color(uiColor) }
    }

    @Published var isOn = false

    /// Where the reader has moved the ink tools to, measured from the dock.
    /// Held here rather than in the bar so it survives leaving ink mode and
    /// coming back -- a bar that jumps home every time is a bar that has to be
    /// moved every time.
    @Published var barOffset: CGSize = InkBarPlacement.docked
    @Published var tool: Tool = .pen
    @Published var ink: Ink = .red
    /// Mirrors the focused canvas's undo manager so the button can enable and
    /// disable itself; recomputed whenever a drawing changes or an undo runs.
    @Published private(set) var canUndo = false

    /// The canvas the user last drew on. Strong for the lifetime of that canvas
    /// is wrong (pages recycle), so weak, and always re-checked before use.
    private weak var focused: UndoableCanvas?

    /// The PencilKit tool matching the current selection.
    var pkTool: PKTool {
        switch tool {
        case .pen:    return PKInkingTool(.pen, color: ink.uiColor, width: 3)
        // vector: a swipe removes whole strokes, which is far easier to aim
        // with than pixel erasing on a dense score
        case .eraser: return PKEraserTool(.vector)
        }
    }

    /// Note the canvas a change came from and refresh the undo state.
    func noteChange(on canvas: UndoableCanvas) {
        focused = canvas
        refresh()
    }

    /// Undo on a specific canvas (a two-finger tap on that page), or on the
    /// last one drawn (the toolbar button).
    @discardableResult
    func undo(on canvas: UndoableCanvas? = nil) -> Bool {
        let target = canvas ?? focused
        guard let target, target.ownUndoManager.canUndo else { return false }
        target.ownUndoManager.undo()
        // the drawing changed underneath PencilKit's delegate, so persist it
        DrawingStore.shared.save(target.drawing, for: target.drawingKey)
        focused = target
        refresh()
        return true
    }

    func refresh() {
        canUndo = focused?.ownUndoManager.canUndo ?? false
    }
}

/// A canvas that owns its undo manager. PKCanvasView otherwise resolves
/// `undoManager` through the responder chain, which inside a SwiftUI
/// UIViewRepresentable is not dependably ours.
final class UndoableCanvas: PKCanvasView {
    let ownUndoManager = UndoManager()
    /// The store key for this page, so an undo can persist the result.
    var drawingKey: String = ""

    override var undoManager: UndoManager? { ownUndoManager }
}

/// The ink bar (§7.9): pill language, docked in the footer under the page.
/// Handle · pen · eraser · divider · five inks · divider · undo · exit. The
/// live ink grows and takes a ring and a tick.
///
/// It sat 74 points off the bottom, which is over the music on any page that
/// runs the height of the pane -- see InkBarPlacement, which also holds the
/// rule for how far the handle may move it.
struct AnnotationBar: View {
    @ObservedObject var controller: AnnotationController
    /// The pane the bar is free to move around in.
    var bounds: CGSize = .zero

    @State private var dragging: CGSize = .zero
    @State private var barSize: CGSize = .zero

    private var offset: CGSize {
        InkBarPlacement.clamp(
            CGSize(width: controller.barOffset.width + dragging.width,
                   height: controller.barOffset.height + dragging.height),
            in: bounds, barSize: barSize)
    }

    var body: some View {
        HStack(spacing: Theme.Metric.s6) {
            handle
            toolButton(.pen, systemImage: "pencil.tip", label: "Draw")
            toolButton(.eraser, systemImage: "eraser", label: "Erase")

            separator

            ForEach(AnnotationController.Ink.allCases) { ink in
                inkDot(ink)
            }

            separator

            Button { controller.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(controller.canUndo ? Theme.Accent.clayStrong
                                                        : Theme.Ink.ink3)
                    .frame(width: 34, height: 34)
                    .frame(width: Theme.Metric.hitTarget, height: Theme.Metric.hitTarget)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!controller.canUndo)
            .accessibilityLabel("Undo annotation")

            separator

            Button { controller.isOn = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Ink.ink2)
                    .frame(width: 34, height: 34)
                    .frame(width: Theme.Metric.hitTarget, height: Theme.Metric.hitTarget)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Finish annotating")
        }
        .padding(.horizontal, Theme.Metric.s8)
        .padding(.vertical, Theme.Metric.s6)
        .background(Theme.Surface.panel)
        .clipShape(Capsule())
        .modifier(InkBarShadow())
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { barSize = geo.size }
                    .onChange(of: geo.size) { _, new in barSize = new }
            }
        }
        .offset(x: offset.width, y: offset.height)
        .padding(.bottom, InkBarPlacement.footerInset)
    }

    /// Drag to move the tools off whatever they are covering; tap to put them
    /// back. The tap matters: it is the way back for anyone who cannot easily
    /// drag, and it means the bar can never be stranded.
    private var handle: some View {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.Ink.ink3)
            .frame(width: 34, height: 34)
            .frame(width: Theme.Metric.hitTarget, height: Theme.Metric.hitTarget)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { dragging = $0.translation }
                    .onEnded { _ in
                        controller.barOffset = offset
                        dragging = .zero
                    })
            .onTapGesture { controller.barOffset = InkBarPlacement.docked }
            .accessibilityIdentifier("ink-bar-handle")
            .accessibilityLabel("Move the ink tools")
            .accessibilityHint("Drag to move them; tap to put them back")
            .accessibilityAddTraits(.isButton)
    }

    private var separator: some View {
        Theme.Rule(vertical: true).frame(height: 20)
            .padding(.horizontal, Theme.Metric.s2)
    }

    private func inkDot(_ ink: AnnotationController.Ink) -> some View {
        let active = controller.ink == ink && controller.tool == .pen
        return Button {
            controller.ink = ink
            controller.tool = .pen
        } label: {
            Circle()
                .fill(ink.swatch)
                .frame(width: active ? 24 : 16, height: active ? 24 : 16)
                .overlay {
                    if active {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .overlay {
                    Circle().stroke(active ? Theme.Ink.ink : Color.clear,
                                    lineWidth: active ? 2 : 1)
                }
                .frame(width: Theme.Metric.hitTarget, height: Theme.Metric.hitTarget)
                .contentShape(Circle())
                .animation(Theme.Motion.pillState, value: active)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ink.rawValue.capitalized) pen")
    }

    private func toolButton(_ tool: AnnotationController.Tool,
                            systemImage: String, label: String) -> some View {
        let selected = controller.tool == tool
        return Button {
            controller.tool = tool
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(selected ? Theme.Accent.clayStrong : Theme.Ink.ink2)
                .frame(width: 34, height: 34)
                .background {
                    if selected { Circle().fill(Theme.Accent.clayTint) }
                }
                .frame(width: Theme.Metric.hitTarget, height: Theme.Metric.hitTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct InkBarShadow: ViewModifier {
    func body(content: Content) -> some View { Theme.Elevation.pill(content) }
}

/// The ink bar, shown while markup is on.
///
/// It hangs off the whole score SCREEN rather than off the page canvas. The
/// canvas stops above the thumbnail strip, so a bar docked to it could never be
/// moved over the strip or the transport however far it was dragged -- which is
/// the clamp Ali ran into (#46). The screen contains all of them.
struct AnnotationBarLayer: View {
    @ObservedObject var controller: AnnotationController

    var body: some View {
        if controller.isOn {
            GeometryReader { geo in
                AnnotationBar(controller: controller, bounds: geo.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .bottom)
            }
        }
    }
}
