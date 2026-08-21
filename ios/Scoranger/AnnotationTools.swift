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

/// The ink bar (§7.9): pill language, sitting 74 from the bottom so it stacks
/// above the canvas toolbar. Pen · eraser · divider · five inks · divider ·
/// undo · exit. The live ink grows and takes a ring and a tick.
struct AnnotationBar: View {
    @ObservedObject var controller: AnnotationController

    var body: some View {
        HStack(spacing: Theme.Metric.s6) {
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
        .overlay { Capsule().stroke(Theme.Line.line2, lineWidth: 1) }
        .modifier(InkBarShadow())
        .padding(.bottom, 74)
    }

    private var separator: some View {
        Rectangle().fill(Theme.Line.line2).frame(width: 1, height: 20)
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
                    Circle().stroke(active ? Theme.Ink.ink : Theme.Line.line2,
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
