import SwiftUI

struct TrackMetadataView: View {
    let track: Track
    var titleSize: CGFloat = 20
    var alignment: HorizontalAlignment = .leading

    private var artistLinks: [TrackArtistLink] {
        track.artistLinks.isEmpty
            ? [TrackArtistLink(name: track.artist)]
            : track.artistLinks
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 5) {
            Text(track.title)
                .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                .foregroundStyle(LyricsDesignTokens.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(alignment == .center ? .center : .leading)

            HStack(spacing: 4) {
                ForEach(Array(artistLinks.enumerated()), id: \.offset) { index, artist in
                    if index > 0 {
                        Text(",")
                            .foregroundStyle(LyricsDesignTokens.mutedText)
                    }
                    artistButton(artist)
                }
            }
            .font(.system(size: max(12, titleSize * 0.62), weight: .regular, design: .rounded))
            .lineLimit(1)

            if !track.album.isEmpty {
                albumButton
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.title)，\(track.artist)，\(track.album)")
    }

    @ViewBuilder
    private func artistButton(_ artist: TrackArtistLink) -> some View {
        if let url = artist.url {
            Button(artist.name) {
                _ = NSWorkspace.shared.open(url)
            }
            .buttonStyle(.plain)
            .foregroundStyle(LyricsDesignTokens.secondaryText)
            .help("在 Spotify 打开艺人：\(artist.name)")
        } else {
            Text(artist.name)
                .foregroundStyle(LyricsDesignTokens.secondaryText)
        }
    }

    @ViewBuilder
    private var albumButton: some View {
        if let url = track.albumURL {
            Button(track.album) {
                _ = NSWorkspace.shared.open(url)
            }
            .buttonStyle(.plain)
            .font(.system(size: max(11, titleSize * 0.52), design: .rounded))
            .foregroundStyle(LyricsDesignTokens.mutedText)
            .lineLimit(1)
            .help("在 Spotify 打开专辑：\(track.album)")
        } else {
            Text(track.album)
                .font(.system(size: max(11, titleSize * 0.52), design: .rounded))
                .foregroundStyle(LyricsDesignTokens.mutedText)
                .lineLimit(1)
        }
    }
}
