import PDFKit
import SwiftUI

// TRANSITIONAL: the bottom thumbnail strip of 0.7, carried out of the retired
// ScoreFooter.swift so the tray can land first. The thumbnail RAIL at the left
// (design/DESIGN_SYSTEM.md §7.11) replaces it in this same build.

/// The page thumbnail strip (NAVIGATION_SYSTEM.md 12.12).
///
/// Grouped in spreads when the spread is on, because that is what a turn
/// actually does. Thumbnails render lazily in a window around the current page:
/// on an iPad Pro a twelve-page score is nothing, on an older iPad a sixty-page
/// one is not (§9.7).
struct ThumbnailStrip: View {
    let document: PDFDocument
    let current: [Int]
    let spread: Bool
    var onJump: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                // LAZY, so only the thumbnails on screen are built. The strip
                // was an eager HStack, which is why it needed a window of six
                // pages either side -- and why the pages outside it were blank
                // (L20). Laziness is the budget now, and it does not lie about
                // what a page looks like.
                LazyHStack(spacing: Theme.Metric.s8) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        HStack(spacing: 2) {
                            ForEach(group, id: \.self) { index in thumb(index) }
                        }
                        .padding(3)
                        .overlay {
                            if spread && group.count > 1 {
                                RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                    .foregroundStyle(Theme.Line.line2)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Metric.s12)
                .padding(.vertical, Theme.Metric.s8)
            }
            .onChange(of: current) { _, pages in
                if let first = pages.first {
                    withAnimation { proxy.scrollTo(first, anchor: .center) }
                }
            }
        }
        .frame(height: Theme.Metric.thumbStripHeight)
        .background(Theme.Surface.panel)
        .overlay(alignment: .top) { Theme.Rule() }
        .accessibilityIdentifier("thumbnail-strip")
    }

    private var groups: [[Int]] {
        SpreadLayout.rows(pageCount: document.pageCount, spread: spread)
    }

    private func thumb(_ index: Int) -> some View {
        Button { onJump(index) } label: {
            ZStack(alignment: .bottomTrailing) {
                // Off the main thread, and abandoned when the cell scrolls
                // away. This strip rasterised INSIDE its body -- the same
                // fault the book browser had, where a flick across 512 pages
                // stopped the main thread once per page because the drawing
                // WAS the view. One view, not a second copy of the fix.
                PageImage(document: document, index: index,
                          drawn: CGSize(width: 52, height: 68),
                          raster: CGSize(width: 104, height: 136),
                          interpolation: .medium) { phase in
                    // A page that will not draw says so. It used to look
                    // exactly like a page that had not been drawn YET, which
                    // is two different problems wearing one face -- and with
                    // cancellation the second is now the ORDINARY outcome of
                    // a flick, so the triangle belongs to .missing alone.
                    PageThumb(width: 52, height: 68)
                        .overlay {
                            if phase == .missing {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.Status.warn)
                            }
                        }
                        .accessibilityIdentifier(phase == .missing
                                                 ? "thumb-failed-\(index)" : "thumb-pending-\(index)")
                }
                .frame(width: 52, height: 68)
                .background(Theme.Surface.paper)
                Text("\(index + 1)").typeRole(.data)
                    .foregroundStyle(Theme.Ink.ink3)
                    .padding(2)
            }
            .overlay {
                Rectangle()
                    .stroke(current.contains(index) ? Theme.Accent.clay : Color.clear,
                            lineWidth: current.contains(index) ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(index)
        .accessibilityIdentifier("thumb-\(index)")
        .accessibilityLabel("Page \(index + 1)")
    }

}
