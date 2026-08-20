import PDFKit
import PencilKit
import SwiftUI

/// The score as a vertical stack of pages with a PencilKit canvas over each:
/// the Apple Pencil draws, fingers scroll. Drawings persist per score+version+page.
/// Two-finger pinch zooms the page width (0.5×–3×); scrolling pans.
/// Highlight mode (toolbar highlighter) turns strokes on a page into an
/// estimated bar range handed to the chat as targeting context.
struct ScorePagesView: View {
    let document: PDFDocument
    let annotationKey: String  // "<slug>/<version>"

    @EnvironmentObject var state: AppState
    /// Committed zoom factor applied to the base page width.
    @State private var zoom: CGFloat = 1.0
    /// Live pinch factor while a MagnifyGesture is in flight (resets to 1).
    @GestureState private var pinch: CGFloat = 1.0
    @State private var highlightMode = false
    /// Chip expanded into steppers for adjusting the estimated range.
    @State private var chipExpanded = false

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
            let effectiveZoom = min(max(zoom * pinch, Self.zoomRange.lowerBound),
                                    Self.zoomRange.upperBound)
            let width = min(geo.size.width - 24, 1100) * effectiveZoom
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(spacing: 12) {
                    ForEach(0..<document.pageCount, id: \.self) { index in
                        if let page = document.page(at: index) {
                            PageView(page: page,
                                     width: width,
                                     drawingStore: DrawingStore.shared,
                                     drawingKey: "\(annotationKey)/p\(index)")
                                .overlay {
                                    // the committed band stays visible (in unit
                                    // page coordinates, so it survives zoom)
                                    // while a highlight is active
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
                                    if highlightMode {
                                        HighlightCaptureOverlay(
                                            pageIndex: index,
                                            pageCount: max(document.pageCount, 1),
                                            measures: measureCount
                                        ) { bars, note, bandRect in
                                            state.highlightedBars = bars
                                            state.highlightNote = note
                                            // one band at a time: a new stroke
                                            // replaces the previous selection
                                            state.highlightBands = [index: bandRect]
                                            chipExpanded = false
                                        }
                                    }
                                }
                                .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                        }
                    }
                }
                .frame(minWidth: geo.size.width)
                .padding(.vertical, 12)
                .animation(nil, value: width)
            }
            .background(Color(white: 0.93))
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, pinchState, _ in
                        pinchState = value.magnification
                    }
                    .onEnded { value in
                        zoom = min(max(zoom * value.magnification, Self.zoomRange.lowerBound),
                                   Self.zoomRange.upperBound)
                    }
            )
        }
        .overlay(alignment: .top) { highlightChip }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    highlightMode.toggle()
                } label: {
                    Image(systemName: "highlighter")
                        .foregroundStyle(highlightMode ? Color.orange : Color.accentColor)
                }
                .accessibilityLabel(highlightMode ? "Exit highlight mode" : "Highlight a passage")
            }
        }
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
    let drawingStore: DrawingStore
    let drawingKey: String

    var body: some View {
        let bounds = page.bounds(for: .mediaBox)
        let height = width * bounds.height / max(bounds.width, 1)
        ZStack {
            PDFPageImage(page: page, size: CGSize(width: width, height: height))
            PencilCanvas(store: drawingStore, key: drawingKey)
        }
        .frame(width: width, height: height)
        .background(Color.white)
    }
}

private struct PDFPageImage: View {
    let page: PDFPage
    let size: CGSize

    var body: some View {
        Image(uiImage: render())
            .resizable()
            .interpolation(.high)
            .frame(width: size.width, height: size.height)
    }

    private func render() -> UIImage {
        let scale: CGFloat = 2.0
        return page.thumbnail(of: CGSize(width: size.width * scale, height: size.height * scale),
                              for: .mediaBox)
    }
}

/// PencilKit canvas: pencil-only input so fingers keep scrolling the score.
private struct PencilCanvas: UIViewRepresentable {
    let store: DrawingStore
    let key: String

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly
        canvas.tool = PKInkingTool(.pen, color: .systemRed, width: 3)
        canvas.delegate = context.coordinator
        canvas.drawing = store.drawing(for: key)
        // drawingPolicy .pencilOnly governs what draws, but the canvas's
        // gesture recognizers still claim finger touches — which ate the
        // two-finger pinch. Restrict every recognizer to pencil touches so
        // finger scrolls and pinches pass through to the SwiftUI ScrollView
        // and MagnifyGesture.
        let pencilOnly = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        canvas.drawingGestureRecognizer.allowedTouchTypes = pencilOnly
        for recognizer in canvas.gestureRecognizers ?? [] {
            recognizer.allowedTouchTypes = pencilOnly
        }
        context.coordinator.key = key
        context.coordinator.store = store
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if context.coordinator.key != key {
            context.coordinator.key = key
            canvas.drawing = store.drawing(for: key)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var key: String = ""
        var store: DrawingStore?

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            store?.save(canvasView.drawing, for: key)
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
