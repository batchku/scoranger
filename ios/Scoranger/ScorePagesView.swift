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
    /// Pencil markup: the shared controller, driven from the pill.
    private var annotation: AnnotationController { state.annotation }

    private static let zoomRange: ClosedRange<CGFloat> = 0.5...3.0

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
                           onTap: { page, point in
                               state.dropFromSelection(at: point, onPage: page)
                           },
                           annotationActive: annotation.isOn,
                           // the pill floats over the canvas: 50pt of pill, its
                           // 20pt bottom padding, and 12 of breathing room
                           bottomChrome: Theme.Metric.pillHeight
                               + Theme.Metric.s20 + Theme.Metric.s12,
                           zoomRange: Self.zoomRange) { settled in
                // round so small wobbles don't re-raster every gesture
                let stepped = (settled * 2).rounded() / 2
                if stepped != rasterZoom { rasterZoom = stepped }
            } content: {
                pageStack(width: width, viewport: geo.size)
            }
        }
        .overlay(alignment: .top) { selectionChip }
        .overlay(alignment: .bottom) {
            if annotation.isOn { AnnotationBar(controller: annotation) }
        }
    }

    @ViewBuilder
    private func pageStack(width: CGFloat, viewport: CGSize) -> some View {
        // VStack, not LazyVStack: inside a hosted view there is no scroll
        // container to be lazy about, and the eager version at least lays out
        // deterministically. PDFPageImage caps its raster size to compensate.
        let rows = SpreadLayout.rows(pageCount: document.pageCount,
                                     spread: state.twoPageSpread)
        VStack(spacing: SpreadLayout.gutter) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                // .top: a spread's two pages can differ in height (the last
                // page of a score is often short), and they should share a
                // top edge rather than float about a common centre
                HStack(alignment: .top, spacing: SpreadLayout.gutter) {
                    ForEach(row, id: \.self) { index in
                        if let page = document.page(at: index) {
                            pageView(page, index: index, width: width)
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
    private func pageView(_ page: PDFPage, index: Int, width: CGFloat) -> some View {
        PageView(page: page,
                 width: width,
                 rasterZoom: rasterZoom,
                 drawingStore: DrawingStore.shared,
                 drawingKey: "\(annotationKey)/p\(index)",
                 annotation: annotation)
            .overlay {
                LassoAnchor(pageIndex: index,
                            committed: state.selectionPaths[index] ?? [],
                            subtracting: state.combineMode == .subtract)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color(hex: 0x1A1917).opacity(0.14), radius: 5, y: 2)
    }

    // MARK: selection chip

    /// §7.10 as before, but describing a real selection rather than an
    /// estimate: what was caught, and a way to drop it.
    @ViewBuilder
    private var selectionChip: some View {
        if let selection = state.selection, !selection.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Metric.s6) {
                HStack(spacing: Theme.Metric.s8) {
                    Text("Selection").typeRole(.label)
                        .foregroundStyle(Theme.Accent.clayStrong)
                        // named here rather than on the container: an
                        // identifier on a container is inherited by every
                        // child, which left the mode buttons all called
                        // "selection-chip" and unfindable by their own names
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
                HStack(spacing: Theme.Metric.s4) {
                    let bars = selection.bars
                    barCell("\(bars.first ?? 0)")
                    if bars.count > 1 {
                        Text("–").typeRole(.meta).foregroundStyle(Theme.Ink.ink3)
                        barCell("\(bars.last ?? 0)")
                    }
                    Text("\(selection.addresses.count) elements").typeRole(.meta)
                        .foregroundStyle(Theme.Ink.ink3)
                }
                combineModes
                Text("tap an element to drop it").typeRole(.meta)
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

    /// What the next lasso does to this selection. A mode, not a gesture: a
    /// lasso that removes has to be something the user chose, because over a
    /// region holding both selected and unselected elements there is no way to
    /// guess which they meant.
    private var combineModes: some View {
        HStack(spacing: Theme.Metric.s2) {
            ForEach(SelectionCombine.allCases, id: \.self) { mode in
                let active = state.combineMode == mode
                Button { state.combineMode = mode } label: {
                    Text(mode.label)
                        .typeRole(.meta)
                        .foregroundStyle(active ? Theme.Surface.paper : Theme.Ink.ink2)
                        .padding(.vertical, Theme.Metric.s2)
                        .padding(.horizontal, Theme.Metric.s6)
                        .background(active
                                    ? (mode.strokeIsWarning ? Theme.Status.danger
                                                            : Theme.Accent.clay)
                                    : Theme.Surface.well)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.rCtl))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("combine-\(mode.rawValue)")
                .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
    }

    /// A finished lasso: everything whose position falls inside it, on this
    /// page, whatever kind it is — notes, chord symbols, clefs, dynamics.
    /// Selecting "a bar" is lassoing the notes in it.
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

    private func barCell(_ text: String) -> some View {
        Text(text)
            .typeRole(.data)
            .foregroundStyle(Theme.Ink.ink)
            .padding(.vertical, Theme.Metric.s2)
            .padding(.horizontal, Theme.Metric.s6)
            .background(Theme.Surface.well)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                    .stroke(Theme.Line.line2, lineWidth: 1)
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

    private func render() -> UIImage {
        // 2x for crispness, scaled up with the settled zoom, but bounded: an
        // unbounded raster across a zoomed multi-page score runs to hundreds of
        // megabytes.
        let scale = min(2.0 * rasterZoom, 3000 / max(size.width, 1))
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
