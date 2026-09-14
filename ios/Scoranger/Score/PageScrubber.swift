import SwiftUI

/// Where the reader is in the document, and how to get somewhere else, in the
/// 28 points a phone can spare (§9.6).
///
/// It stands in for the thumbnail rail at compact width and only there. The
/// rail is better where there is room for it -- a legible thumbnail says what
/// a page IS, which no tick can -- so both exist and the size class chooses.
///
/// The rules are `PageScrubberLayout`'s and are tested without a screen: which
/// page a finger is asking for, where a tick belongs, and when ticks stop
/// being worth drawing at all.
struct PageScrubber: View {
    let pageCount: Int
    let current: Int
    var onJump: (Int) -> Void

    /// The page under the finger while a drag is live. Committed on release,
    /// but SHOWN as it moves: a scrubber that only reports where it landed is
    /// a scrubber you cannot aim.
    @State private var dragging: Int?

    private var shown: Int { dragging ?? current }

    var body: some View {
        HStack(spacing: Theme.Metric.s8) {
            GeometryReader { geo in
                ticks(in: geo.size)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let page = PageScrubberLayout.page(
                                    atX: value.location.x, width: geo.size.width,
                                    pages: pageCount)
                                if page != dragging { dragging = page }
                            }
                            .onEnded { value in
                                let page = PageScrubberLayout.page(
                                    atX: value.location.x, width: geo.size.width,
                                    pages: pageCount)
                                dragging = nil
                                onJump(page)
                            })
            }
            Text(PageScrubberLayout.label(page: shown, pages: pageCount))
                .typeRole(.meta)
                .foregroundStyle(Theme.Ink.ink3)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("scrubber-page")
        }
        .padding(.horizontal, Theme.Metric.s12)
        // minHeight for the text to grow into, and fixedSize so the row does
        // NOT grow into the slack of the stack it sits in. Without the second
        // half a minimum reads as "take everything left over": the scrubber
        // swallowed 700pt of a phone and the page it belongs to was fitted
        // into what remained, at half width.
        .frame(minHeight: PageScrubberLayout.height)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.Surface.panel)
        .overlay(alignment: .top) { Theme.Rule() }
        .accessibilityIdentifier("page-scrubber")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Page scrubber")
        .accessibilityValue(PageScrubberLayout.label(page: shown, pages: pageCount))
    }

    @ViewBuilder
    private func ticks(in size: CGSize) -> some View {
        let pitch = PageScrubberLayout.pitch(width: size.width, pages: pageCount)
        ZStack(alignment: .leading) {
            // The track, which is what a long book collapses to. It is drawn
            // under the ticks at every length so the row reads as one control
            // rather than as a scatter that happens to be in a line.
            Capsule()
                .fill(Theme.Line.line2)
                .frame(height: 2)
                .frame(maxHeight: .infinity, alignment: .center)
            if PageScrubberLayout.showsTicks(width: size.width, pages: pageCount) {
                ForEach(0..<max(pageCount, 0), id: \.self) { index in
                    tick(index, pitch: pitch, height: size.height,
                         width: size.width)
                }
            } else if pageCount > 0 {
                // No countable ticks: the CURRENT page still gets its mark,
                // because "where am I" is the question the row exists for and
                // it does not stop being askable at 300 pages.
                tick(shown, pitch: pitch, height: size.height, width: size.width)
            }
        }
    }

    private func tick(_ index: Int, pitch: CGFloat, height: CGFloat,
                      width: CGFloat) -> some View {
        let isCurrent = index == shown
        return Capsule()
            .fill(isCurrent ? Theme.Accent.clayStrong : Theme.Line.line2)
            .frame(width: PageScrubberLayout.tickWidth,
                   height: isCurrent ? PageScrubberLayout.currentTickHeight
                                     : PageScrubberLayout.tickHeight)
            .position(x: PageScrubberLayout.x(ofPage: index, width: width,
                                              pages: pageCount),
                      y: height / 2)
    }
}
