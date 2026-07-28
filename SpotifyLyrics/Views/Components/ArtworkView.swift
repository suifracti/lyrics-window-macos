import AppKit
import SwiftUI

/// Reusable artwork surface shared by the focus and immersive layouts.
struct ArtworkView: View {
    let track: Track
    let size: CGFloat
    var showsAlbumLabel: Bool = true
    /// V2 keeps its established icon-like radius; V3 opts into a small
    /// album-cover radius without changing the shared component's default.
    var cornerRadiusRatio: CGFloat = 0.18
    @State private var remoteArtwork: NSImage?

    var body: some View {
        ZStack {
            fallbackArtwork

            if let remoteArtwork {
                Image(nsImage: remoteArtwork)
                    .resizable()
                    .scaledToFill()
                    .overlay(Color.black.opacity(showsAlbumLabel ? 0.04 : 0.13))
                    .transition(.opacity)
            }

            if showsAlbumLabel {
                VStack {
                    Spacer()
                    Text(track.album.uppercased())
                        .font(.system(size: max(8, size * 0.1), weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(LyricsDesignTokens.primaryText.opacity(0.78))
                        .padding(.bottom, size * 0.1)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * cornerRadiusRatio, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * cornerRadiusRatio, style: .continuous)
                .stroke(LyricsDesignTokens.controlBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(showsAlbumLabel ? 0.28 : 0.18), radius: size * 0.08, y: size * 0.04)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("专辑封面，(track.album)")
        .task(id: "\(track.id)|\(track.artworkURL?.absoluteString ?? "no-artwork")") {
            remoteArtwork = nil
            remoteArtwork = await ArtworkImageLoader.shared.image(for: track.artworkURL)
        }
    }

    private var fallbackArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.34, green: 0.25, blue: 0.24),
                            Color(red: 0.16, green: 0.19, blue: 0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Color(red: 0.83, green: 0.67, blue: 0.45).opacity(0.42))
                .frame(width: size * 0.72, height: size * 0.72)
                .blur(radius: size * 0.12)
                .offset(x: size * 0.18, y: -size * 0.14)

            Image(systemName: track.artworkName)
                .font(.system(size: size * 0.31, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(LyricsDesignTokens.primaryText)
        }
    }
}
