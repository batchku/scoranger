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
    /// Chip expanded into steppers for adjusting the estimated range.
    @State private var chipExpanded = false
    /// Pencil markup: off by default so the score reads as a document.
    @StateObject private var annotation = AnnotationController()

    private static let zoomRange: ClosedRange<CGFloat> = 0.5...3.0

    /// Measure count of the displayed version (falls back to the score's
    /// latest version snapshot) — the basis of the linear bar estimate.
    private var measureCount: Int {
        let fromDisplayed = state.displayedVersion?.parts?.first?.measures
        let fromLatest = state.selectedScore.flatMap { score in
            score.versions.first { $0.id == score.latest }?.parts?.first?.measures
        }
        return max(fromDisplayed ?? fromLatest ?? 0, 1)
    }

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width - 24, 1100)
            ZoomableScroll(contentWidth: max(width + 24, geo.size.width),
                           zoomRange: Self.zoomRange) { settled in
                // round so small wobbles don't re-raster every gesture
                let stepped = (settled * 2).rounded() / 2
                if stepped != rasterZoom { rasterZoom = stepped }
            } content: {
                pageStack(width: width, viewport: geo.size)
            }
        }
        .overlay(alignment: .top) { highlightChip }
        .overlay(alignment: .bottom) {
            if annotation.isOn { AnnotationBar(controller: annotation) }
        }
        .toolbar {
            // ONE pencil in the toolbar. "highlighter" is also a pencil glyph,
            // so having both read as two edit buttons; highlight-a-passage is a
            // chat-targeting action and now lives in the score's gear menu.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    annotation.isOn.toggle()
                    if annotation.isOn { state.highlightMode = false }
                } label: {
                    Image(systemName: annotation.isOn ? "pencil.circle.fill" : "lock.circle")
                        .font(.title3)
                        .foregroundStyle(annotation.isOn
                                         ? annotation.ink.swatch : Color.secondary)
                }
                .accessibilityLabel(annotation.isOn
                                    ? "Exit annotation mode" : "Annotate the score")
            }
        }
        .onChange(of: state.highlightMode) { _, on in
            // both modes want the Pencil; only one at a time
            if on { annotation.isOn = false }
        }
    }

    @ViewBuilder
    private func pageStack(width: CGFloat, viewport: CGSize) -> some View {
        // VStack, not LazyVStack: inside a hosted view there is no scroll
        // container to be lazy about, and the eager version at least lays out
        // deterministically. PDFPageImage caps its raster size to compensate.
        VStack(spacing: 12) {
            ForEach(0..<document.pageCount, id: \.self) { index in
                if let page = document.page(at: index) {
                    PageView(page: page,
                             width: width,
                             rasterZoom: rasterZoom,
                             drawingStore: DrawingStore.shared,
                             drawingKey: "\(annotationKey)/p\(index)",
                             annotation: annotation)
                        .overlay {
                            // the committed band stays visible (in unit page
                            // coordinates, so it survives zoom) while a
                            // highlight is active
                            if state.highlightedBars != nil,
                               let band = state.highlightBands[index] {
                                GeometryReader { g in
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.yellow.opacity(0.3))
                                        .frame(width: band.width * g.size.width,
                                               height: band.height * g.size.height)
                                        .offset(x: band.minX * g.size.width,
                                                y: band.minY * g.size.height)
                                }
                                .allowsHitTesting(false)
                            }
                        }
                        .overlay {
                            if state.highlightMode {
                                HighlightCaptureOverlay(
                                    pageIndex: index,
                                    pageCount: max(document.pageCount, 1),
                                    measures: measureCount
                                ) { bars, note, bandRect in
                                    state.highlightedBars = bars
                                    state.highlightNote = note
                                    // one band at a time: a new stroke replaces
                                    // the previous selection
                                    state.highlightBands = [index: bandRect]
                                    chipExpanded = false
                                }
                            }
                        }
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                }
            }
        }
        .frame(width: max(width + 24, viewport.width))
        .padding(.vertical, 12)
    }

    // MARK: highlight chip

    /// "≈ bars X–Y" pill: tap to fine-tune with steppers, x to clear.
    @ViewBuilder
    private var highlightChip: some View {
        if let bars = state.highlightedBars {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "highlighter")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button {
                        chipExpanded.toggle()
                    } label: {
                        Text("≈ bars \(bars.lowerBound)–\(bars.upperBound)")
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    Button {
                        state.clearHighlight()
                        chipExpanded = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear highlight")
                }
                if chipExpanded {
                    Stepper(value: chipLow, in: 1...bars.upperBound) {
                        Text("from bar \(bars.lowerBound)").font(.footnote)
                    }
                    Stepper(value: chipHigh, in: bars.lowerBound...max(measureCount, bars.upperBound)) {
                        Text("to bar \(bars.upperBound)").font(.footnote)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
            .padding(.top, 8)
            .frame(maxWidth: 320)
        }
    }

    private var chipLow: Binding<Int> {
        Binding(
            get: { state.highlightedBars?.lowerBound ?? 1 },
            set: { new in
                guard let bars = state.highlightedBars else { return }
                state.highlightedBars = min(new, bars.upperBound)...bars.upperBound
            })
    }

    private var chipHigh: Binding<Int> {
        Binding(
            get: { state.highlightedBars?.upperBound ?? 1 },
            set: { new in
                guard let bars = state.highlightedBars else { return }
                state.highlightedBars = bars.lowerBound...max(new, bars.lowerBound)
            })
    }
}

/// Highlight-mode capture layer over one page: a stroke's horizontal span,
/// combined with the page's position in the document, maps linearly onto the
/// score's measure count — a deliberate v1 estimate (hence the "≈" chip).
private struct HighlightCaptureOverlay: View {
    let pageIndex: Int
    let pageCount: Int
    let measures: Int
    /// (bar range, provenance note, committed band in unit page coordinates)
    let onHighlight: (ClosedRange<Int>, String, CGRect) -> Void

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let s = dragStart, let c = dragCurrent {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.yellow.opacity(0.3))
                        .frame(width: max(abs(c.x - s.x), 8), height: 44)
                        .position(x: (s.x + c.x) / 2, y: (s.y + c.y) / 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        if dragStart == nil { dragStart = value.startLocation }
                        dragCurrent = value.location
                    }
                    .onEnded { value in
                        defer {
                            dragStart = nil
                            dragCurrent = nil
                        }
                        guard let s = dragStart else { return }
                        let pageWidth = max(geo.size.width, 1)
                        let pageHeight = max(geo.size.height, 1)
                        let x0 = min(s.x, value.location.x) / pageWidth
                        let x1 = max(s.x, value.location.x) / pageWidth
                        // linear position across the whole document, 0…1
                        let g0 = (Double(pageIndex) + Double(x0)) / Double(pageCount)
                        let g1 = (Double(pageIndex) + Double(x1)) / Double(pageCount)
                        let lo = max(1, min(measures, Int(g0 * Double(measures)) + 1))
                        let hi = max(lo, min(measures, Int((g1 * Double(measures)).rounded(.up))))
                        // the drawn band, normalized so it can be re-rendered
                        // at any zoom level
                        let midY = (s.y + value.location.y) / 2
                        let band = CGRect(x: x0,
                                          y: max(0, (midY - 22) / pageHeight),
                                          width: max(x1 - x0, 8 / pageWidth),
                                          height: 44 / pageHeight)
                        onHighlight(lo...hi, "pencil highlight on page \(pageIndex + 1)", band)
                    }
            )
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
        .background(Color.white)
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

    func clear(prefix: String) {
        let safePrefix = prefix.replacingOccurrences(of: "/", with: "_")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.lastPathComponent.hasPrefix(safePrefix) {
            try? FileManager.default.removeItem(at: f)
        }
    }
}
