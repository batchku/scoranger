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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Settled zoom scale, used ONLY to raise the raster resolution of the
    /// rendered pages. Geometry is fixed and the live zoom is UIScrollView's
    /// transform, which is what keeps the canvas from jumping on release.
    @State private var rasterZoom: CGFloat = 1.0
    /// The viewport in content coordinates, and the rows worth drawing at
    /// depth. Everything else renders at a cheap scale.
    @State private var visibleRect: CGRect = .zero
    /// Pencil markup: the shared controller, driven from the top bar.
    private var annotation: AnnotationController { state.annotation }
    /// What the Pencil means right now (§6). Selection is OFF in performance
    /// mode, which is what frees the Pencil to turn pages.
    var mode: ScoreMode = .read
    /// Where a page turn is scrolling to, if one is in flight.
    @State private var scrollTarget: CGFloat?

    /// Fit to twelve.
    ///
    /// The floor is FIT, not 0.5: the unit on screen is sized to fit the
    /// viewport, so zooming out below 1 would only add ground around it -- and
    /// it is what makes "you can never see more than two pages" true without
    /// anything enforcing it. The ceiling stays 12 so a notehead can be
    /// inspected; the page re-rasters at the settled scale.
    private static let zoomRange: ClosedRange<CGFloat> =
        PagedCanvas.minimumZoom...PagedCanvas.maximumZoom

    var body: some View {
        GeometryReader { geo in
            let spread = state.twoPageSpread
            let unit = PagedCanvas.unit(at: state.pageIndex,
                                        pageCount: document.pageCount, spread: spread)
            let width = PagedCanvas.fittedPageWidth(
                viewport: geo.size, pageAspect: aspect(of: unit.first),
                pages: max(unit.count, 1), gutter: SpreadLayout.gutter,
                margin: SpreadLayout.margin)
            ZoomableScroll(contentWidth: width * CGFloat(max(unit.count, 1))
                               + SpreadLayout.gutter * CGFloat(max(unit.count - 1, 0)),
                           onLasso: { page, path, adding in
                               select(path: path, onPage: page, adding: adding)
                           },
                           onUndoTap: { _ = annotation.undo() },
                           onTap: { page, point, taps, fingerHeld in
                               state.handleTap(at: point, onPage: page, taps: taps,
                                               modifierFingerDown: fingerHeld)
                           },
                           onWillReplaceSelection: { state.clearSelection() },
                           onTurnTap: { point, width, isPencil in
                               turn(at: point, width: width, isPencil: isPencil)
                           },
                           onSwipeTurn: { direction in step(by: direction) },
                           selectionEnabled: mode != .performance,
                           resetPanToken: state.pageIndex,
                           annotationActive: annotation.isOn,
                           // the pill floats over the canvas: 50pt of pill, its
                           // 20pt bottom padding, and 12 of breathing room
                           // the ink bar's height, not the pill's -- the pill
                           // lost its score-view role and this inset outlived
                           // the thing it was measuring (batch-2 #9)
                           bottomChrome: Theme.Metric.scoreBottomChrome
                               + Theme.Metric.s20 + Theme.Metric.s12,
                           onVisibleRectChange: { rect, content in
                               visibleRect = rect
                               publishVisibleBars(contentRect: rect,
                                                  contentSize: content,
                                                  unit: unit, width: width)
                               // The unit IS what is visible now: no bands, no
                               // boundary arithmetic, no mapping a scroll
                               // offset back to a page.
                               if state.visiblePageIndices != unit {
                                   state.visiblePageIndices = unit
                               }
                           },
                           zoomRange: Self.zoomRange) { settled in
                // round so small wobbles don't re-raster every gesture
                // finer steps than before: at 12x, half-scale rounding threw
                // away most of the resolution the zoom had asked for
                let stepped = (settled * 4).rounded() / 4
                if stepped != rasterZoom { rasterZoom = stepped }
            } content: {
                pageUnit(unit, width: width)
            }
            // A turn slides the new unit in, out to the left and in from the
            // right, reversed going back. It is a transition on the unit, not
            // a scroll to an offset, which is why there is no offset to keep.
            .id(state.pageIndex)
            .transition(.asymmetric(insertion: .move(edge: .trailing),
                                    removal: .move(edge: .leading)))
            .animation(Theme.Motion.overlay(reduced: reduceMotion), value: state.pageIndex)
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

    /// Turn the scroll view's visible rect into "which slice of each page is on
    /// screen", in page (SVG user) coordinates, for the bar readout.
    ///
    /// Two spaces meet here. `contentRect` is the scroll view's and moves as
    /// the reader pans and zooms; each page's own frame is computed from the
    /// layout, not measured -- a GeometryReader inside this scroll view never
    /// reported, because SwiftUI is not re-laid-out as UIKit scrolls it.
    /// Intersecting them gives the visible slice of each page, and the page's
    /// own scale converts it into the coordinates the geometry index uses.
    private func publishVisibleBars(contentRect: CGRect, contentSize: CGSize,
                                    unit: [Int], width: CGFloat) {
        guard contentSize.width > 0, contentSize.height > 0 else { return }
        // The scroll view's content coordinates are NOT the SwiftUI layout's,
        // so the two are reconciled by proportion rather than by assuming a
        // shared unit -- assuming one made the visible slice eight pages wide.
        let layoutWidth = CGFloat(unit.count) * width
            + CGFloat(max(unit.count - 1, 0)) * SpreadLayout.gutter
        let layoutHeight = width * (unit.compactMap { aspect(of: $0) }.max() ?? 1.414)
            + SpreadLayout.gutter * 2
        let kx = layoutWidth / contentSize.width
        let ky = layoutHeight / contentSize.height
        let visible = CGRect(x: contentRect.minX * kx, y: contentRect.minY * ky,
                             width: contentRect.width * kx, height: contentRect.height * ky)
        var out: [Int: CGRect] = [:]
        for (position, index) in unit.enumerated() {
            guard let size = state.geometry?.page(index)?.size,
                  size.width > 0, size.height > 0 else { continue }
            let frame = BarPosition.pageFrame(position: position, width: width,
                                              aspect: aspect(of: index),
                                              gutter: SpreadLayout.gutter)
            let slice = frame.intersection(visible)
            guard !slice.isNull, !slice.isEmpty else { continue }
            let sx = size.width / frame.width
            let sy = size.height / frame.height
            out[index] = CGRect(x: (slice.minX - frame.minX) * sx,
                                y: (slice.minY - frame.minY) * sy,
                                width: slice.width * sx,
                                height: slice.height * sy)
        }
        if out != state.visibleBarRects { state.visibleBarRects = out }
    }

    /// POSITION ◀ ▲ ▼ ▶ │ SIZE A⁻ 14 pt A⁺ │ Reset, and the pending line.
    @ViewBuilder
    private var adjustRow: some View {
        if let session = state.adjustSession {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Theme.Metric.s6) {
                    Text("POSITION").typeRole(.label).foregroundStyle(Theme.Ink.ink3)
                    nudge(.left, "chevron.left", "left")
                    nudge(.up, "chevron.up", "up")
                    nudge(.down, "chevron.down", "down")
                    nudge(.right, "chevron.right", "right")

                    Divider().frame(height: 16)

                    Text("SIZE").typeRole(.label).foregroundStyle(Theme.Ink.ink3)
                    resize(.smaller, "textformat.size.smaller", "smaller")
                    Text("\(session.pending.size) pt")
                        .typeRole(.data).foregroundStyle(Theme.Ink.ink)
                        .frame(minWidth: 40)
                        .accessibilityIdentifier("adjust-size")
                    resize(.bigger, "textformat.size.larger", "bigger")

                    Divider().frame(height: 16)

                    Button("Reset") { state.adjust { $0.reset() } }
                        .typeRole(.meta)
                        .foregroundStyle(Theme.Accent.clayStrong)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("adjust-reset")
                    Spacer(minLength: 0)
                }
                if let pending = session.pendingDescription {
                    HStack(spacing: Theme.Metric.s8) {
                        Text("pending: \(pending)")
                            .typeRole(.meta).foregroundStyle(Theme.Ink.ink2)
                            .accessibilityIdentifier("adjust-pending")
                        Button("Revert") { state.adjust { $0.revert() } }
                            .typeRole(.meta)
                            .foregroundStyle(Theme.Accent.clayStrong)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("adjust-revert")
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    /// One nudge button. Press-and-hold repeats, but a plain tap always works
    /// on its own -- the repeat is a convenience, never the only way.
    private func nudge(_ direction: ChordAdjustSession.Direction,
                       _ glyph: String, _ word: String) -> some View {
        let enabled = state.adjustSession?.canNudge(direction) ?? false
        return Button {
            state.adjust { $0.nudge(direction) }
        } label: {
            Image(systemName: glyph)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 32, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.42)
        .accessibilityLabel("Move \(word) half a staff space")
        .accessibilityIdentifier("adjust-\(word)")
    }

    private func resize(_ step: ChordAdjustSession.SizeStep,
                        _ glyph: String, _ word: String) -> some View {
        let enabled = state.adjustSession?.canResize(step) ?? false
        return Button {
            state.adjust { $0.resize(step) }
        } label: {
            Image(systemName: glyph)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 32, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.42)
        .accessibilityLabel("Make it \(word)")
        .accessibilityIdentifier("adjust-\(word)")
    }

    /// A finished touch that might be a turn. Who may turn, and in which zone,
    /// is still PageTurn's answer -- the §6 arbitration table is unchanged.
    /// What a turn DOES is all that changed: it steps the index.
    private func turn(at point: CGPoint, width: CGFloat, isPencil: Bool) {
        guard let zone = PageTurn.turn(isPencil: isPencil, mode: mode, x: point.x,
                                       width: width, movement: 0, elapsed: 0)
        else { return }
        step(by: zone == .next ? 1 : -1)
    }

    /// Step the unit. Rapid turns coalesce to the latest rather than queueing
    /// animations, or the score keeps sliding after the reader stops.
    private func step(by direction: Int) {
        guard let next = PagedCanvas.step(from: state.pageIndex, by: direction,
                                          pageCount: document.pageCount,
                                          spread: state.twoPageSpread) else { return }
        state.pageIndex = PagedCanvas.coalesce(pending: nil, latest: next)
    }

    private func aspect(of page: Int?) -> CGFloat {
        guard let page, let pdf = document.page(at: page) else { return 1.414 }
        let bounds = pdf.bounds(for: .mediaBox)
        return bounds.height / max(bounds.width, 1)
    }

    /// The unit on screen: one page, or two with the spread on.
    ///
    /// Nothing else is rendered. That is the whole change -- the vertical stack
    /// of every page is gone, and with it the raster window that existed to
    /// stop a twelve-page score drawing itself twelve times over. One or two
    /// pages can afford full resolution.
    @ViewBuilder
    private func pageUnit(_ unit: [Int], width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: SpreadLayout.gutter) {
            ForEach(unit, id: \.self) { index in
                if let page = document.page(at: index) {
                    pageView(page, index: index, width: width, atDepth: true)
                }
            }
        }
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
                // Position and size, for a selection of chord symbols. One
                // row, docked with the chip rather than floating beside the
                // element: a cluster that followed the selection would sit on
                // the music, land off the page near an edge, and move under the
                // thumb as the symbol moved -- and the symbol is the thing you
                // need to watch while you nudge it.
                if selection.isAdjustable, state.adjustSession != nil {
                    adjustRow
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
            // the pane, so the bar can be moved around inside it and no
            // further -- the clamp needs to know how much room there is
            GeometryReader { geo in
                AnnotationBar(controller: controller, bounds: geo.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .bottom)
            }
            .allowsHitTesting(true)
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
            // The canvas is laid out at the zoomed size and scaled back down,
            // so PencilKit magnifies the ink itself instead of the outer
            // transform stretching a picture of it. See InkSharpness.
            let ink = InkSharpness.canvasZoom(zoom: rasterZoom)
            PencilCanvas(store: drawingStore, key: drawingKey,
                         controller: annotation, canvasZoom: ink)
                .frame(width: width * ink, height: height * ink)
                .scaleEffect(1 / ink, anchor: .topLeading)
                .frame(width: width, height: height, alignment: .topLeading)
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
    /// What PencilKit is asked to magnify the ink by. The view is laid out
    /// this much larger and scaled back down, so the strokes are RE-DRAWN at
    /// the zoom rather than stretched with everything else.
    var canvasZoom: CGFloat = 1

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
        // its own scrolling would fight the score's; only the zoom is wanted
        canvas.isScrollEnabled = false
        canvas.bouncesZoom = false
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = InkSharpness.maximumFactor
        Self.sharpen(canvas, to: canvasZoom)
        return canvas
    }

    /// Hand the magnification to PencilKit.
    ///
    /// Setting `contentScaleFactor` -- on the canvas, on every subview, with
    /// the drawing reassigned to force a repaint -- was tried first and
    /// changed nothing on screen: PencilKit renders its strokes on its own
    /// terms and does not take that as an instruction to redraw. Its own
    /// `zoomScale` does, which is what laying the canvas out large and scaling
    /// it back down is for.
    private static func sharpen(_ canvas: PKCanvasView, to zoom: CGFloat) {
        let wanted = max(1, min(zoom, InkSharpness.maximumFactor))
        guard InkSharpness.isWorthRedrawing(from: canvas.zoomScale,
                                            to: wanted) else { return }
        canvas.zoomScale = wanted
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
        Self.sharpen(canvas, to: canvasZoom)
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


struct ChipShadow: ViewModifier {
    func body(content: Content) -> some View { Theme.Elevation.pill(content) }
}
