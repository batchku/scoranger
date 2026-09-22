import SwiftUI

/// A page's own tools, at its foot, on a phone (Ph2).
///
/// On an iPad a page's tools are the panel BESIDE it, at rest: the set list's
/// Add, Share, People and Delete sit in a column that costs the page nothing.
/// A phone has no column. Until 0.8.2 the rest state was pushed over the page
/// anyway, so opening a set list on an iPhone showed "This set list" instead
/// of the set list -- the running order, the title and Play were all behind
/// it, and the only way to the music was Done.
///
/// So the tools come off the panel and sit on one fixed line at the foot of
/// the page, above the home indicator and outside the scroll. Each one pushes
/// its page, which is the panel state it would have opened on an iPad
/// (Ph3) -- the same destination by the same route, reached from the page
/// that owns it.
///
/// The strip scrolls sideways rather than shrinking its labels: four 36pt
/// capsules fit at 393pt, and the fifth an accessibility text size makes of
/// them must be reachable rather than clipped (§6.3).
struct PageFootStrip: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        var glyph: String?
        var destructive = false
        var action: () -> Void
    }

    let items: [Item]
    /// What the page must leave under its last row so the strip covers
    /// nothing. Read by the page, not applied here: the strip is an overlay
    /// and an overlay cannot push what it sits on.
    static let inset: CGFloat = 60

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Metric.s6) {
                ForEach(items) { item in
                    Button(action: item.action) {
                        HStack(spacing: Theme.Metric.s4) {
                            if let glyph = item.glyph {
                                Image(systemName: glyph)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text(item.title).typeRole(.control).lineLimit(1)
                        }
                        .foregroundStyle(item.destructive ? Theme.Status.danger : Theme.Ink.ink)
                        .padding(.horizontal, Theme.Metric.s12)
                        .frame(minHeight: 36)
                        .background(Theme.Surface.paper)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(item.id)
                    .accessibilityLabel(item.title)
                }
            }
            .padding(.horizontal, Theme.Metric.pageSide)
            .padding(.vertical, Theme.Metric.s8)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Surface.panel)
        .overlay(alignment: .top) { Theme.Rule() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("page-foot-strip")
    }
}
