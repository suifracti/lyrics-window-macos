import SwiftUI

struct TrackMetadataView: View {
    let track: Track
    var titleSize: CGFloat = 20
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 5) {
            Text(track.title)
                .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                .foregroundStyle(LyricsDesignTokens.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(alignment == .center ? .center : .leading)

            Text(track.artist)
                .font(.system(size: max(12, titleSize * 0.62), weight: .regular, design: .rounded))
                .foregroundStyle(LyricsDesignTokens.secondaryText)
                .lineLimit(1)

            if !track.album.isEmpty {
                Text(track.album)
                    .font(.system(size: max(11, titleSize * 0.52), design: .rounded))
                    .foregroundStyle(LyricsDesignTokens.mutedText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.title)，\(track.artist)，\(track.album)")
    }
}
