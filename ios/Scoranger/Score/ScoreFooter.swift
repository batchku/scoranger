import PDFKit
import SwiftUI

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
        .overlay(alignment: .top) { Rectangle().fill(Theme.Line.line).frame(height: 1) }
        .accessibilityIdentifier("thumbnail-strip")
    }

    private var groups: [[Int]] {
        SpreadLayout.rows(pageCount: document.pageCount, spread: spread)
    }

    private func thumb(_ index: Int) -> some View {
        Button { onJump(index) } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let drawn = ThumbnailCache.shared.image(
                        document: document, index: index,
                        size: CGSize(width: 104, height: 136)) {
                        Image(uiImage: drawn)
                            .resizable().interpolation(.medium)
                    } else {
                        // A page that will not draw says so. It used to look
                        // exactly like a page that had not been drawn YET,
                        // which is two different problems wearing one face.
                        PageThumb(width: 52, height: 68)
                            .overlay {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.Status.warn)
                            }
                            .accessibilityIdentifier("thumb-failed-\(index)")
                    }
                }
                .frame(width: 52, height: 68)
                .background(Theme.Surface.paper)
                Text("\(index + 1)").typeRole(.data)
                    .foregroundStyle(Theme.Ink.ink3)
                    .padding(2)
            }
            .overlay {
                Rectangle()
                    .stroke(current.contains(index) ? Theme.Accent.clay : Theme.Line.line2,
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

/// The transport (12.13).
///
/// Drawn, mostly inert, and honest about it. Previous and next are LIVE and
/// step the current setlist -- the one piece of this that works today, and the
/// most useful thing to have on a music stand (§1).
struct Transport: View {
    let setlistLabel: String?
    var canStep: Bool
    var onPrevious: () -> Void
    var onNext: () -> Void

    var body: some View {
        HStack(spacing: Theme.Metric.s8) {
            stepButton("backward.end", label: "Previous in setlist",
                       id: "transport-prev", action: onPrevious)
            stepButton("forward.end", label: "Next in setlist",
                       id: "transport-next", action: onNext)
            if let setlistLabel {
                Text(setlistLabel).typeRole(.data)
                    .foregroundStyle(Theme.Ink.ink2)
                    .padding(.horizontal, Theme.Metric.s8)
                    .padding(.vertical, 4)
                    .background(Theme.Surface.panel)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                            .stroke(Theme.Line.line2, lineWidth: 1)
                    }
                    .accessibilityIdentifier("transport-setlist")
            }
            inert
            Spacer()
            Text("PLAYBACK NOT WIRED YET").typeRole(.meta)
                .foregroundStyle(Theme.Ink.ink3)
                .padding(.horizontal, Theme.Metric.s8)
                .padding(.vertical, 3)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Theme.Line.line2)
                }
        }
        .padding(.horizontal, Theme.Metric.s12)
        .frame(height: Theme.Metric.transportHeight)
        .background(Theme.Surface.band)
        .overlay(alignment: .top) { Rectangle().fill(Theme.Line.line).frame(height: 1) }
        .accessibilityIdentifier("transport")
    }

    /// The parts with no engine behind them. Shown at 42% and not tappable --
    /// a control that looks live and does nothing is worse than one that
    /// plainly is not.
    private var inert: some View {
        HStack(spacing: Theme.Metric.s8) {
            ForEach(["play.fill", "repeat", "record.circle"], id: \.self) { glyph in
                Image(systemName: glyph).font(.system(size: 13))
                    .foregroundStyle(Theme.Ink.ink2)
                    .frame(width: 32, height: 32)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                            .stroke(Theme.Line.line2, lineWidth: 1)
                    }
            }
            Text("0:00").typeRole(.data).foregroundStyle(Theme.Ink.ink3)
        }
        .opacity(0.42)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func stepButton(_ glyph: String, label: String, id: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph).font(.system(size: 13))
                .foregroundStyle(canStep ? Theme.Ink.ink : Theme.Ink.ink3)
                .frame(width: 32, height: 32)
                .background(Theme.Surface.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Metric.rCtl)
                        .stroke(Theme.Line.line2, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canStep)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
    }
}
