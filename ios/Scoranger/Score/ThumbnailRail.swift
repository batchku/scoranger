import PDFKit
import SwiftUI

/// The thumbnail rail (design/DESIGN_SYSTEM.md §7.11): 60 wide at the left
/// of the score in paged reading, every page at 40 × 52 with its number in
/// mono, the current page (or spread) ringed in clay. Tap to jump, drag to
/// scrub. Not shown in scroll mode. It replaces the bottom thumbnail strip
/// and the Pages panel.
struct ThumbnailRail: View {
    let document: PDFDocument
    let current: [Int]
    let spread: Bool
    var onJump: (Int) -> Void

    static let width: CGFloat = 60
    private static let thumb = CGSize(width: 40, height: 52)
    private static let gap: CGFloat = 6
    /// A thumbnail and its number, the unit the scrub maps a finger to.
    private static let slot: CGFloat = 52 + 12 + 6

    @State private var scrubbing: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: Self.gap) {
                    ForEach(0..<document.pageCount, id: \.self) { index in
                        thumb(index)
                    }
                }
                .padding(.vertical, Theme.Metric.s8)
                .frame(width: Self.width)
            }
            .onChange(of: current) { _, pages in
                if let first = pages.first {
                    withAnimation { proxy.scrollTo(first, anchor: .center) }
                }
            }
        }
        .frame(width: Self.width)
        .background(Theme.Surface.band)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("thumbnail-rail")
    }

    private func thumb(_ index: Int) -> some View {
        let ringed = current.contains(index) || scrubbing == index
        return Button { onJump(index) } label: {
            VStack(spacing: 2) {
                PageImage(document: document, index: index,
                          drawn: Self.thumb,
                          raster: CGSize(width: 80, height: 104),
                          interpolation: .medium) { phase in
                    PageThumb(width: Self.thumb.width, height: Self.thumb.height)
                        .accessibilityIdentifier(phase == .missing
                                                 ? "thumb-failed-\(index)" : "thumb-pending-\(index)")
                }
                .frame(width: Self.thumb.width, height: Self.thumb.height)
                .background(Theme.Surface.paper)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(ringed ? Theme.Accent.clay : Color.clear, lineWidth: 1.5)
                }
                Text("\(index + 1)").typeRole(.dataS)
                    .foregroundStyle(ringed ? Theme.Accent.clayStrong : Theme.Ink.ink3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(index)
        .accessibilityIdentifier("thumb-\(index)")
        .accessibilityLabel("Page \(index + 1) of \(document.pageCount)")
        .accessibilityAddTraits(current.contains(index) ? [.isButton, .isSelected] : [.isButton])
    }
}
