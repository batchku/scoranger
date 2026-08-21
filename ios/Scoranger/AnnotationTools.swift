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

        var uiColor: UIColor {
            switch self {
            case .red:    return .systemRed
            case .blue:   return .systemBlue
            case .green:  return .systemGreen
            case .orange: return .systemOrange
            case .black:  return .label
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

/// The floating annotation bar: tool, colour, undo, and a way out of the mode.
struct AnnotationBar: View {
    @ObservedObject var controller: AnnotationController

    var body: some View {
        HStack(spacing: 6) {
            toolButton(.pen, systemImage: "pencil.tip", label: "Draw")
            toolButton(.eraser, systemImage: "eraser", label: "Erase")

            separator

            ForEach(AnnotationController.Ink.allCases) { ink in
                Button {
                    controller.ink = ink
                    // choosing a colour means you want to draw with it
                    controller.tool = .pen
                } label: {
                    // A thin ring round a small dot was too subtle to find at a
                    // glance. The active colour now grows, gains a contrasting
                    // halo, and carries a checkmark.
                    let active = controller.ink == ink && controller.tool == .pen
                    Circle()
                        .fill(ink.swatch)
                        .frame(width: active ? 28 : 20, height: active ? 28 : 20)
                        .overlay {
                            if active {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.35), radius: 1)
                            }
                        }
                        .overlay(
                            Circle().stroke(Color.primary.opacity(active ? 0.9 : 0.15),
                                            lineWidth: active ? 2 : 1)
                        )
                        .padding(active ? 0 : 4)
                        .animation(.snappy(duration: 0.15), value: active)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(ink.rawValue.capitalized) pen")
            }

            separator

            Button {
                controller.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(minWidth: 32, minHeight: 32)
            }
            .buttonStyle(.plain)
            .disabled(!controller.canUndo)
            .foregroundStyle(controller.canUndo ? Color.accentColor : Color.secondary)
            .accessibilityLabel("Undo annotation")

            separator

            Button {
                controller.isOn = false
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .frame(minWidth: 32, minHeight: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Finish annotating")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .fixedSize()
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .padding(.bottom, 12)
    }

    /// A plain rule. Divider() is flexible in an HStack and starves the
    /// controls after it of width.
    private var separator: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 1, height: 24)
    }

    private func toolButton(_ tool: AnnotationController.Tool,
                            systemImage: String, label: String) -> some View {
        let selected = controller.tool == tool
        return Button {
            controller.tool = tool
        } label: {
            Image(systemName: systemImage)
                .frame(minWidth: 32, minHeight: 32)
                .background(selected ? Color.accentColor.opacity(0.18) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
