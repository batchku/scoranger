import PDFKit
import PencilKit
import SwiftUI

/// The score as a vertical stack of pages with a PencilKit canvas over each:
/// the Apple Pencil draws, fingers scroll. Drawings persist per score+version+page.
/// Two-finger pinch zooms (0.5×–3×) about the midpoint between the fingers,
/// via UIScrollView; when the pinch settles the pages re-render crisply at the
/// new size.
/// Highlight mode (score gear menu) turns strokes on a page into an
/// estimated bar range handed to the chat as targeting context.
struct ScorePagesView: View {
    let document: PDFDocument
    let annotationKey: String  // "<slug>/<version>"

    @EnvironmentObject var state: AppState
    /// Settled zoom scale, used ONLY to raise the raster resolution of the
    /// rendered pages. Geometry is fixed and the live zoom is UIScrollView's
    /// transform, which is what keeps the canvas from jumping on release.
    @State private var rasterZoom: CGFloat = 1.0
    /// The viewport in content coordinates, and the rows worth drawing at
    /// depth. Everything else renders at a cheap scale.
    @State private var visibleRect: CGRect = .zero
    /// Pencil markup: the shared controller, driven from the pill.
    private var annotation: AnnotationController { state.annotation }

    /// Up to 12x: Ali wants to go all the way in on a single notehead to check
    /// it, and 3x stopped well short of that -- the canvas simply sprang back.
    /// The pages re-raster at the settled scale, so the note stays sharp.
    private static let zoomRange: ClosedRange<CGFloat> = 0.5...12.0

    var body: some View {
        GeometryReader { geo in
            let spread = state.twoPageSpread
            let width = SpreadLayout.pageWidth(viewport: geo.size.width, spread: spread)
            ZoomableScroll(contentWidth: SpreadLayout.contentWidth(viewport: geo.size.width,
                                                                  spread: spread),
                           onLasso: { page, path, adding in
                               select(path: path, onPage: page, adding: adding)
                           },
                           onUndoTap: { _ = annotation.undo() },
                           onTap: { page, point, taps in
                               state.handleTap(at: point, onPage: page, taps: taps)
                           },
                           onWillReplaceSelection: { state.clearSelection() },
                           annotationActive: annotation.isOn,
                           // the pill floats over the canvas: 50pt of pill, its
                           // 20pt bottom padding, and 12 of breathing room
                           bottomChrome: Theme.Metric.pillHeight
                               + Theme.Metric.s20 + Theme.Metric.s12,
                           onVisibleRectChange: { visibleRect = $0 },
                           zoomRange: Self.zoomRange) { settled in
                // round so small wobbles don't re-raster every gesture
                // finer steps than before: at 12x, half-scale rounding threw
                // away most of the resolution the zoom had asked for
                let stepped = (settled * 4).rounded() / 4
                if stepped != rasterZoom { rasterZoom = stepped }
            } content: {
                pageStack(width: width, viewport: geo.size)
            }
            .onAppear {
                if visibleRect == .zero {
                    visibleRect = CGRect(origin: .zero, size: geo.size)
                }
            }
        }
        .overlay(alignment: .top) { selectionChip }
        .overlay(alignment: .topLeading) {
            TouchDiagnosticsOverlay(diagnostics: TouchDiagnostics.shared)
        }
        // Wrapped in a child that OBSERVES the controller. This view reads
        // `state.annotation` through AppState, which publishes nothing when the
        // controller's own state changes -- so the bar's visibility only
        // updated when something else happened to redraw the score pane, and
        // turning edit mode off from the pill left the tools on screen. The
        // pill itself has observed the controller since it was written; this is
        // the same fix, in the one place that was missing it.
        .overlay(alignment: .bottom) { AnnotationBarLayer(controller: annotation) }
    }

    @ViewBuilder
    private func pageStack(width: CGFloat, viewport: CGSize) -> some View {
        // VStack, not LazyVStack: inside a hosted view there is no scroll
        // container to be lazy about, and the eager version at least lays out
        // deterministically. PDFPageImage caps its raster size to compensate.
        let rows = SpreadLayout.rows(pageCount: document.pageCount,
                                     spread: state.twoPageSpread)
        let heights = rows.map { row -> CGFloat in
            row.compactMap { index -> CGFloat? in
                guard let page = document.page(at: index) else { return nil }
                let bounds = page.bounds(for: .mediaBox)
                return width * bounds.height / max(bounds.width, 1)
            }.max() ?? width
        }
        let drawn = SpreadLayout.visibleRows(heights: heights, visible: visibleRect)
        VStack(spacing: SpreadLayout.gutter) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                // .top: a spread's two pages can differ in height (the last
                // page of a score is often short), and they should share a
                // top edge rather than float about a common centre
                HStack(alignment: .top, spacing: SpreadLayout.gutter) {
                    ForEach(row, id: \.self) { index in
                        if let page = document.page(at: index) {
                            pageView(page, index: index, width: width,
                                     atDepth: drawn.contains(rowIndex))
                        }
                    }
                }
            }
        }
        .frame(width: SpreadLayout.contentWidth(viewport: viewport.width,
                                                spread: state.twoPageSpread))
        .padding(.vertical, SpreadLayout.gutter)
    }

    /// One page, with its own lasso anchor. The anchor is what makes a lasso
    /// land on the page it was drawn on: the recognizer picks the anchor whose
    /// frame contains the touch, so the right-hand page of a spread selects
    /// from itself and not from its neighbour.
    private func pageView(_ page: PDFPage, index: Int, width: CGFloat,
                          atDepth: Bool) -> some View {
        PageView(page: page,
                 width: width,
                 rasterZoom: atDepth ? rasterZoom : 1,
                 drawingStore: DrawingStore.shared,
                 drawingKey: "\(annotationKey)/p\(index)",
                 annotation: annotation)
            .overlay {
                // What was caught, drawn over the page. Until this, a working
                // selection looked like nothing had happened: the only signs
                // were the lasso outline, a chip at the top, and chat opening.
                SelectionHighlight(frames: selectedFrames(onPage: index),
                                   pageSize: state.geometry?.page(index)?.size ?? .zero)
                    .allowsHitTesting(false)
            }
            .overlay {
                LassoAnchor(pageIndex: index,
                            committed: state.selectionPaths[index] ?? [])
                    .allowsHitTesting(false)
            }
            .shadow(color: Color(hex: 0x1A1917).opacity(0.14), radius: 5, y: 2)
    }

    /// The frames of everything selected on one page, in page coordinates.
    /// Addresses are durable across re-renders; the frames are looked up fresh
    /// from whatever geometry is on screen now.
    private func selectedFrames(onPage index: Int) -> [CGRect] {
        guard let selection = state.activeSelection,
              let geometry = state.geometry else { return [] }
        return selection.addresses.compactMap { address in
            guard let element = geometry.element(at: address),
                  element.pageIndex == index else { return nil }
            return element.frame
        }
    }

    // MARK: selection chip

    /// What is selected, in the user's terms, and what can be done with it.
    ///
    /// The Replace/Add/Subtract modes are gone. Adding is a finger of the other
    /// hand held down while the Pencil draws -- a thing the hands do rather
    /// than a mode to be in -- and the modes were a trap: Subtract emptied the
    /// selection, an empty selection hid the chip, and the chip was the only
    /// way back out.
    ///
    /// Nothing reaches the chat box until "Use in chat" is tapped. A lasso is
    /// not a request to start typing.
    @ViewBuilder
    private var selectionChip: some View {
        if let selection = state.activeSelection, !selection.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Metric.s6) {
                HStack(spacing: Theme.Metric.s8) {
                    Text(selection.headline).typeRole(.label)
                        .foregroundStyle(Theme.Accent.clayStrong)
                        // named here rather than on the container: an
                        // identifier on a container is inherited by every child
                        .accessibilityIdentifier("selection-chip")
                    Spacer(minLength: Theme.Metric.s8)
                    Button {
                        state.clearSelection()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Ink.ink2)
                            .frame(width: Theme.Metric.hitTarget,
                                   height: Theme.Metric.hitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear selection")
                }
                if let place = selection.placeLine {
                    Text(place).typeRole(.meta)
                        .foregroundStyle(Theme.Ink.ink3)
                        .accessibilityIdentifier("selection-place")
                }
                if let note = state.selectionCarryNote {
                    Text(note).typeRole(.meta)
                        .foregroundStyle(Theme.Status.warn)
                        .accessibilityIdentifier("selection-carry-note")
                }
                HStack(spacing: Theme.Metric.s8) {
                    PanelButton(title: "Use in chat", kind: .primary) {
                        state.confirmSelectionForChat()
                    }
                    .accessibilityIdentifier("selection-confirm")
                    Spacer(minLength: 0)
                }
                Text("Hold a finger down to add · tap an element to drop it")
                    .typeRole(.meta)
                    .foregroundStyle(Theme.Ink.ink3)
            }
            .padding(.horizontal, Theme.Metric.s12)
            .padding(.vertical, Theme.Metric.s8)
            .background(Theme.Surface.panel)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rPanel))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metric.rPanel)
                    .stroke(Theme.Line.line2, lineWidth: 1)
            }
            .modifier(ChipShadow())
            .padding(.top, Theme.Metric.s12)
        }
    }

    private func select(path: [CGPoint], onPage index: Int, adding: Bool) {
        guard let page = state.geometry?.page(index) else {
            state.selectionPaths = [index: path]
            return
        }
        // unit coordinates -> page (SVG user) coordinates
        let polygon = path.map { CGPoint(x: $0.x * page.size.width,
                                         y: $0.y * page.size.height) }
        let caught = page.elements(caughtBy: polygon)
        state.commitSelection(caught, path: path, page: index, adding: adding)
    }

}

/// The ink tools, on screen only while edit mode is on.
///
/// Its whole reason for existing is `@ObservedObject`: the bar has to appear and
/// disappear with the mode, and only a view that observes the controller is
/// redrawn when the mode changes.
/// Boxes over the selected elements, scaled from page coordinates to the size
/// the page is drawn at.
private struct SelectionHighlight: View {
    let frames: [CGRect]
    let pageSize: CGSize

    var body: some View {
        GeometryReader { geo in
            if !frames.isEmpty, pageSize.width > 0, pageSize.height > 0 {
                let sx = geo.size.width / pageSize.width
                let sy = geo.size.height / pageSize.height
                ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.Accent.clay.opacity(0.22))
                        .overlay {
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Theme.Accent.clayStrong.opacity(0.65), lineWidth: 1)
                        }
                        // a hair of padding so a notehead's box reads as a
                        // highlight rather than a tight outline
                        .frame(width: max(frame.width * sx, 6) + 3,
                               height: max(frame.height * sy, 6) + 3)
                        .position(x: frame.midX * sx, y: frame.midY * sy)
                }
            }
        }
    }
}

private struct AnnotationBarLayer: View {
    @ObservedObject var controller: AnnotationController

    var body: some View {
        if controller.isOn {
            AnnotationBar(controller: controller)
        }
    }
}

private struct PageView: View {
    let page: PDFPage
    let width: CGFloat
    let rasterZoom: CGFloat
    let drawingStore: DrawingStore
    let drawingKey: String
    @ObservedObject var annotation: AnnotationController

    var body: some View {
        let bounds = page.bounds(for: .mediaBox)
        let height = width * bounds.height / max(bounds.width, 1)
        ZStack {
            PDFPageImage(page: page,
                         size: CGSize(width: width, height: height),
                         rasterZoom: rasterZoom)
            PencilCanvas(store: drawingStore, key: drawingKey, controller: annotation)
        }
        .frame(width: width, height: height)
        .background(Theme.Surface.paper)
        // the warm ground sits close to paper white in luminance, so without an
        // edge the gap between pages reads as a hole rather than a page break
        .overlay {
            Rectangle().stroke(Theme.Line.line2, lineWidth: 1)
        }
    }
}

private struct PDFPageImage: View {
    let page: PDFPage
    let size: CGSize
    /// Settled zoom: the page is drawn at the same size but rasterised finer,
    /// so zooming in sharpens without moving anything.
    let rasterZoom: CGFloat

    var body: some View {
        Image(uiImage: render())
            .resizable()
            .interpolation(.high)
            .frame(width: size.width, height: size.height)
    }

    /// The widest a page may be rastered, in pixels.
    ///
    /// This was 3000 while EVERY page rastered at the settled zoom: eight of
    /// them at that width is around 380MB, and the watchdog has killed this app
    /// for less. Now only the rows near the viewport draw at depth (see
    /// SpreadLayout.visibleRows), so the budget buys resolution where it can be
    /// seen instead of spreading it over pages that are off screen. Three rows
    /// at 5200px is roughly 320MB in the worst case and typically far less,
    /// while the pages nobody is looking at cost about 2MB each.
    private static let maxRasterWidth: CGFloat = 5200

    private func render() -> UIImage {
        // 2x for crispness, scaled up with the settled zoom, still bounded.
        let scale = min(2.0 * rasterZoom, Self.maxRasterWidth / max(size.width, 1))
        return page.thumbnail(of: CGSize(width: size.width * scale, height: size.height * scale),
                              for: .mediaBox)
    }
}

/// PencilKit canvas: pencil-only input so fingers keep scrolling the score.
/// Interactive only while annotation mode is on — with the mode off the canvas
/// still renders existing marks but passes every touch through, so the score
/// behaves like a plain document.
private struct PencilCanvas: UIViewRepresentable {
    let store: DrawingStore
    let key: String
    @ObservedObject var controller: AnnotationController

    /// The simulator has no Pencil, so UI tests ask for finger drawing to be
    /// able to exercise strokes and undo at all.
    private static let allowFingerDrawing =
        ProcessInfo.processInfo.arguments.contains("-annotateWithFinger")

    func makeUIView(context: Context) -> UndoableCanvas {
        let canvas = UndoableCanvas()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = Self.allowFingerDrawing ? .anyInput : .pencilOnly
        canvas.tool = controller.pkTool
        canvas.delegate = context.coordinator
        canvas.drawingKey = key
        canvas.drawing = store.drawing(for: key)
        canvas.isUserInteractionEnabled = controller.isOn
        // Loading a drawing must not look like an edit: clear anything
        // PencilKit registered while we assigned it.
        canvas.ownUndoManager.removeAllActions()

        if !Self.allowFingerDrawing {
            // drawingPolicy .pencilOnly governs what draws, but the canvas's
            // gesture recognizers still claim finger touches — which ate the
            // two-finger pinch. Restrict every recognizer to pencil touches so
            // finger scrolls and pinches pass through to the scroll view.
            let pencilOnly = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
            canvas.drawingGestureRecognizer.allowedTouchTypes = pencilOnly
            for recognizer in canvas.gestureRecognizers ?? [] {
                recognizer.allowedTouchTypes = pencilOnly
            }
        }

        // Two-finger tap undoes, the way it does in Apple's own note apps.
        // Declared simultaneous so it never cancels the scroll view's pinch.
        let undoTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTwoFingerTap))
        undoTap.numberOfTouchesRequired = 2
        undoTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        undoTap.delegate = context.coordinator
        undoTap.cancelsTouchesInView = false
        canvas.addGestureRecognizer(undoTap)

        context.coordinator.key = key
        context.coordinator.store = store
        context.coordinator.controller = controller
        context.coordinator.publishStrokeCount(canvas)
        return canvas
    }

    func updateUIView(_ canvas: UndoableCanvas, context: Context) {
        if context.coordinator.key != key {
            context.coordinator.key = key
            canvas.drawingKey = key
            canvas.drawing = store.drawing(for: key)
            canvas.ownUndoManager.removeAllActions()
            context.coordinator.publishStrokeCount(canvas)
        }
        context.coordinator.controller = controller
        canvas.isUserInteractionEnabled = controller.isOn
        canvas.tool = controller.pkTool
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        var key: String = ""
        var store: DrawingStore?
        var controller: AnnotationController?

        /// Stroke count as an accessibility value: the only way a UI test can
        /// observe what the canvas actually holds.
        func publishStrokeCount(_ canvas: PKCanvasView) {
            canvas.isAccessibilityElement = true
            canvas.accessibilityIdentifier = "canvas-\(key)"
            canvas.accessibilityValue = "\(canvas.drawing.strokes.count) strokes"
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            store?.save(canvasView.drawing, for: key)
            publishStrokeCount(canvasView)
            guard let canvas = canvasView as? UndoableCanvas else { return }
            MainActor.assumeIsolated {
                controller?.noteChange(on: canvas)
            }
        }

        @objc func handleTwoFingerTap(_ sender: UITapGestureRecognizer) {
            guard let canvas = sender.view as? UndoableCanvas else { return }
            MainActor.assumeIsolated {
                _ = controller?.undo(on: canvas)
                publishStrokeCount(canvas)
            }
        }

        // the score scrolls and pinches under the canvas; never block that
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// Local persistence for pencil annotations (server sync is a later feature).
final class DrawingStore {
    static let shared = DrawingStore()
    private let dir: URL

    init() {
        dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "annotations")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func url(for key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return dir.appending(path: "\(safe).pkdrawing")
    }

    func drawing(for key: String) -> PKDrawing {
        guard let data = try? Data(contentsOf: url(for: key)),
              let drawing = try? PKDrawing(data: data) else { return PKDrawing() }
        return drawing
    }

    func save(_ drawing: PKDrawing, for key: String) {
        try? drawing.dataRepresentation().write(to: url(for: key))
    }

    /// Re-file every drawing of one arrangement under a new slug. The engine
    /// moves the score's artifacts when a slug is renamed; the user's pencil
    /// marks live here, keyed by "<slug>/<version>/pN", so they have to move
    /// too or they are silently orphaned.
    func rename(fromPrefix old: String, toPrefix new: String) {
        let from = old.replacingOccurrences(of: "/", with: "_")
        let to = new.replacingOccurrences(of: "/", with: "_")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.lastPathComponent.hasPrefix(from + "_") {
            let moved = to + String(f.lastPathComponent.dropFirst(from.count))
            try? FileManager.default.moveItem(at: f, to: dir.appending(path: moved))
        }
    }

    func clear(prefix: String) {
        let safePrefix = prefix.replacingOccurrences(of: "/", with: "_")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.lastPathComponent.hasPrefix(safePrefix) {
            try? FileManager.default.removeItem(at: f)
        }
    }
}


private struct ChipShadow: ViewModifier {
    func body(content: Content) -> some View { Theme.Elevation.pill(content) }
}
