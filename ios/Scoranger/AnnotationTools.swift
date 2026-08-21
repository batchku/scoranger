import PencilKit
import SwiftUI

/// Annotation mode for the score pages.
///
/// Off (the default) the score behaves like a document: fingers scroll and
/// pinch, and the Pencil does nothing. On, the Pencil draws or erases and a
/// floating bar offers the tool, the colour and undo.
///
/// Undo is kept here rather than delegated to PencilKit's own undo manager:
/// inside a SwiftUI `UIViewRepresentable` the responder chain that supplies
/// that manager is not reliably ours, whereas a per-page stack of previous
/// drawings is small, predictable, and survives pages being recycled by the
/// enclosing LazyVStack.
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
    /// Republished so the Undo button can enable and disable itself.
    @Published private(set) var undoDepth = 0

    /// Live canvases by page key, held weakly: pages scroll out of the
    /// LazyVStack and must be free to deallocate.
    private var canvases: [String: WeakCanvas] = [:]
    /// The drawing as last persisted per page, i.e. the state an undo restores.
    private var current: [String: PKDrawing] = [:]
    /// Per-page stack of prior drawings.
    private var stacks: [String: [PKDrawing]] = [:]
    /// The page most recently drawn on: what a toolbar undo acts upon.
    private var lastKey: String?
    /// Set while we assign a drawing ourselves, so the change delegate does not
    /// record our own undo as a new edit.
    private var applying = false

    private final class WeakCanvas {
        weak var value: PKCanvasView?
        init(_ value: PKCanvasView) { self.value = value }
    }

    /// The PencilKit tool matching the current selection.
    var pkTool: PKTool {
        switch tool {
        case .pen:    return PKInkingTool(.pen, color: ink.uiColor, width: 3)
        // vector: a swipe removes whole strokes, which is far easier to aim
        // with than pixel erasing on a dense score
        case .eraser: return PKEraserTool(.vector)
        }
    }

    var canUndo: Bool { undoDepth > 0 }

    // MARK: canvas lifecycle

    func register(_ canvas: PKCanvasView, key: String, initial: PKDrawing) {
        canvases[key] = WeakCanvas(canvas)
        current[key] = initial
        refreshDepth()
    }

    func rebind(_ canvas: PKCanvasView, from oldKey: String, to newKey: String,
                initial: PKDrawing) {
        canvases[oldKey] = nil
        register(canvas, key: newKey, initial: initial)
    }

    // MARK: edits

    /// Record an edit the user just made on `key`.
    func recordChange(_ drawing: PKDrawing, key: String) {
        guard !applying else { return }
        stacks[key, default: []].append(current[key] ?? PKDrawing())
        // a runaway stack would pin every intermediate drawing in memory
        if stacks[key]!.count > 50 { stacks[key]!.removeFirst() }
        current[key] = drawing
        lastKey = key
        refreshDepth()
    }

    /// Undo the last edit on `key`, or on the most recently drawn page.
    /// Returns false when there is nothing to undo.
    @discardableResult
    func undo(key explicitKey: String? = nil) -> Bool {
        guard let key = explicitKey ?? lastKey,
              var stack = stacks[key], let previous = stack.popLast() else { return false }
        stacks[key] = stack
        current[key] = previous
        applying = true
        canvases[key]?.value?.drawing = previous
        applying = false
        DrawingStore.shared.save(previous, for: key)
        refreshDepth()
        return true
    }

    /// Forget history for a score/version (its drawings were cleared).
    func reset(prefix: String) {
        for key in stacks.keys where key.hasPrefix(prefix) { stacks[key] = nil }
        for key in current.keys where key.hasPrefix(prefix) { current[key] = nil }
        lastKey = nil
        refreshDepth()
    }

    private func refreshDepth() {
        undoDepth = lastKey.flatMap { stacks[$0]?.count } ?? 0
    }
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
