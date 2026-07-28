import AppKit
import SwiftUI

struct TrackBackdropView: View {
    let track: Track
    let identity: TrackIdentity?
    let isLiveTrack: Bool

    @State private var currentPayload: BackdropPayload?
    @State private var outgoingPayload: BackdropPayload?

    var body: some View {
        ZStack {
            neutralBackground

            if let outgoingPayload {
                backdropLayers(for: outgoingPayload)
                    .opacity(0.24)
                    .transition(.opacity)
            }

            if let currentPayload {
                backdropLayers(for: currentPayload)
                    .transition(.opacity)
            }

            Color.black.opacity(currentPayload?.palette.readabilityVeilOpacity ?? 0.36)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: requestKey) {
            await reload(for: requestKey)
        }
    }

    private var requestKey: String? {
        guard isLiveTrack, let identity else { return nil }
        return "\(identity.stableKey)|\(track.artworkURL?.absoluteString ?? "no-artwork")"
    }

    private var neutralBackground: some View {
        let palette = BackdropPalette.neutral
        return LinearGradient(
            colors: [
                color(palette.primary),
                color(palette.secondary)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func backdropLayers(for payload: BackdropPayload) -> some View {
        let palette = payload.palette
        return ZStack {
            Image(nsImage: payload.image)
                .resizable()
                .scaledToFill()
                .scaleEffect(1.34)
                .blur(radius: 72)
                .opacity(palette.textureOpacity)

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.34)

            LinearGradient(
                colors: [
                    color(palette.primary).opacity(0.86),
                    color(palette.secondary).opacity(0.94),
                    color(palette.glow).opacity(0.64)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    color(palette.glow).opacity(0.36),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 16,
                endRadius: 560
            )
        }
        .clipped()
    }

    @MainActor
    private func reload(for key: String?) async {
        let previous = currentPayload
        outgoingPayload = previous
        currentPayload = nil

        guard let key, isLiveTrack, let artworkURL = track.artworkURL else {
            outgoingPayload = nil
            return
        }
        guard !Task.isCancelled else { return }

        guard let image = await ArtworkImageLoader.shared.image(for: artworkURL) else {
            guard key == requestKey, !Task.isCancelled else { return }
            outgoingPayload = nil
            return
        }
        guard key == requestKey, !Task.isCancelled else { return }

        guard let imageData = image.tiffRepresentation else {
            guard key == requestKey, !Task.isCancelled else { return }
            outgoingPayload = nil
            return
        }

        // Palette sampling is keyed only by the current track/artwork and is
        // performed off the main actor. Playback progress never re-enters it.
        let palette = await BackdropPaletteCache.shared.palette(
            for: key,
            imageData: imageData
        )
        guard key == requestKey, !Task.isCancelled else { return }

        let payload = BackdropPayload(
            key: key,
            image: image,
            palette: palette
        )
        withAnimation(.easeInOut(duration: 0.42)) {
            currentPayload = payload
        }

        try? await Task.sleep(nanoseconds: 460_000_000)
        guard key == requestKey, !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            outgoingPayload = nil
        }
    }

    private func color(_ value: BackdropColor) -> Color {
        Color(red: value.red, green: value.green, blue: value.blue)
    }
}

private struct BackdropPayload {
    let key: String
    let image: NSImage
    let palette: BackdropPalette
}
