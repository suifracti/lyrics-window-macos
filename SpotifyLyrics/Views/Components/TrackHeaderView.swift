import SwiftUI

struct TrackArtworkView: View {
    let track: Track
    let size: CGFloat
    var showsAlbumLabel: Bool = true

    var body: some View {
        ArtworkView(track: track, size: size, showsAlbumLabel: showsAlbumLabel)
    }
}

struct TrackHeaderView: View {
    let track: Track

    var body: some View {
        HStack(spacing: 12) {
            TrackArtworkView(
                track: track,
                size: LyricsDesignTokens.artworkSize
            )

            TrackMetadataView(track: track, titleSize: 15)
        }
        .frame(minHeight: LyricsDesignTokens.artworkSize)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.title)，\(track.artist)，\(track.album)")
    }
}
