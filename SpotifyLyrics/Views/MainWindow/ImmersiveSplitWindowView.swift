import SwiftUI

struct ImmersiveSplitWindowView: View {
    @ObservedObject var state: PlaybackState

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= LyricsDesignTokens.immersiveSplitBreakpoint {
                wideLayout
            } else {
                narrowLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var wideLayout: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                artworkColumn(
                    size: min(
                        230,
                        max(180, geometry.size.height - 330)
                    )
                )
                .frame(minWidth: 290, idealWidth: 360, maxWidth: 430)

                Divider()
                    .overlay(LyricsDesignTokens.controlBorder.opacity(0.8))

                lyricsColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, LyricsDesignTokens.immersiveWindowPadding)
        .padding(.vertical, 22)
    }

    private var narrowLayout: some View {
        ScrollView(.vertical) {
            VStack(spacing: 20) {
                artworkColumn(size: 220)
                lyricsColumn
                    .frame(minHeight: 360)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .scrollIndicators(.hidden)
    }

    private func artworkColumn(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer(minLength: 0)
                ArtworkView(
                    track: state.currentTrack,
                    size: size,
                    showsAlbumLabel: false
                )
                Spacer(minLength: 0)
            }

            TrackMetadataView(track: state.currentTrack, titleSize: 24)

            HStack(spacing: 10) {
                Button {
                    // Favorite is intentionally visual-only until the playback
                    // provider exposes a library mutation API.
                } label: {
                    Label("收藏", systemImage: "heart")
                        .labelStyle(.iconOnly)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(LyricsDesignTokens.secondaryText)
                .help("收藏（暂未连接 Spotify Library API）")

                Button {
                    // Keep this as a safe placeholder for future track actions.
                } label: {
                    Label("更多", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(LyricsDesignTokens.secondaryText)
                .help("更多歌曲操作")

                Spacer()
            }

            PlaybackControlsView(state: state, vertical: true)

            if !state.canControlSpotify || state.isUsingMockPreview {
                statusSummary
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.trailing, 26)
    }

    private var lyricsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("歌词")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LyricsDesignTokens.mutedText)
                    .textCase(.uppercase)
                Spacer()
                if state.canControlSpotify {
                    Label("Spotify 已连接", systemImage: "circle.fill")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Color.green.opacity(0.86))
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            LyricsViewport(state: state)
        }
    }

    private var statusSummary: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.canControlSpotify ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(state.providerStatusMessage)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(LyricsDesignTokens.mutedText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("播放来源：\(state.providerStatusMessage)")
    }
}
