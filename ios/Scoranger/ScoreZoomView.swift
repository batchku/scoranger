import PDFKit
import SwiftUI

/// Compact-width (iPhone) score view: a pinch-zoomable, vertically scrolling
/// PDFView. No pencil markup here — that stays on the iPad's ScorePagesView.
struct ScoreZoomView: UIViewRepresentable {
    let document: PDFDocument

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        /// The document currently shown, for identity comparison in
        /// updateUIView (weak: AppState owns the document).
        weak var shownDocument: PDFDocument?
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.maxScaleFactor = 5
        view.backgroundColor = UIColor(white: 0.93, alpha: 1)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        // AppState polls every 2s; only touch .document when the instance
        // actually changed — a blind reassignment resets the user's zoom.
        guard context.coordinator.shownDocument !== document else { return }
        context.coordinator.shownDocument = document
        view.document = document
        view.minScaleFactor = view.scaleFactorForSizeToFit
        view.scaleFactor = view.scaleFactorForSizeToFit
    }
}
