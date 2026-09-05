import SwiftUI

/// The sync chip, and nothing else.
///
/// This file was 888 lines of mixer -- the panel, its strips, its picker and
/// the layer that parked it -- all replaced by MixerWindowPanel.swift and
/// MixerWindowStrips.swift on design/MIXER_WINDOW.md. The chip stayed because
/// it is not part of the mixer: it belongs to page-following, it just lived
/// next door.

/// The sync chip: the only solid-clay object on the canvas, so it reads as an
/// interruption without needing a colour of its own (§3).
struct SyncChipLayer: View {
    @ObservedObject var state: AppState
    @ObservedObject var playback: PlaybackEngine

    private var playheadPage: Int? {
        guard let bar = playback.soundingBar, let geometry = state.geometry else { return nil }
        return Playhead.page(ofMeasure: bar,
                             pages: geometry.pages.map {
                                 ($0.index, BarPosition.bars(onPage: $0))
                             })
    }

    private var shows: Bool {
        PageFollow.showsSync(isPlaying: playback.isPlaying,
                             isFollowing: state.pageFollow.isFollowing,
                             playheadPage: playheadPage,
                             visiblePages: state.visiblePageIndices,
                             isPerformanceMode: state.scoreMode == .performance)
    }

    var body: some View {
        Group {
            if shows {
                Button {
                    guard let page = playheadPage else { return }
                    state.pageFollow.syncTapped()
                    state.pageIndex = PagedCanvas.index(forPage: page,
                                                        spread: state.twoPageSpread)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text(PageFollow.syncLabel(bar: playback.soundingBar))
                            .typeRole(.label)
                    }
                    .foregroundStyle(Theme.Surface.panel)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Theme.Accent.clayPress)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sync-to-playback")
                .accessibilityLabel(PageFollow.syncLabel(bar: playback.soundingBar))
                .accessibilityAddTraits(.isButton)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: shows)
    }
}
