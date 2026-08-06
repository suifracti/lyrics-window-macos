import AppKit
import SwiftUI

private struct DirectionDBackdropTreatmentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var directionDBackdropTreatment: Bool {
        get { self[DirectionDBackdropTreatmentKey.self] }
        set { self[DirectionDBackdropTreatmentKey.self] = newValue }
    }
}

struct TrackBackdropView: View {
    let track: Track
    let identity: TrackIdentity?
    let isLiveTrack: Bool

    @State private var currentPayload: BackdropPayload?
    @State private var outgoingPayload: BackdropPayload?
    @Environment(\.directionDBackdropTreatment) private var directionDBackdropTreatment

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

            Color.black.opacity(directionDBackdropTreatment
                ? min(0.70, max(0.26, (currentPayload?.palette.readabilityVeilOpacity ?? 0.36) * 0.82))
                : (currentPayload?.palette.readabilityVeilOpacity ?? 0.36))
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
        return ZStack {
            LinearGradient(
                colors: [
                    color(palette.primary),
                    color(palette.secondary),
                    color(palette.glow).opacity(directionDBackdropTreatment ? 0.72 : 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if directionDBackdropTreatment {
                RadialGradient(
                    colors: [color(palette.glow).opacity(0.34), .clear],
                    center: UnitPoint(x: 0.18, y: 0.42),
                    startRadius: 24,
                    endRadius: 560
                )
            }
        }
    }

    private func backdropLayers(for payload: BackdropPayload) -> some View {
        let palette = payload.palette
        return ZStack {
            Image(nsImage: payload.image)
                .resizable()
                .scaledToFill()
                .scaleEffect(directionDBackdropTreatment ? 1.24 : 1.34)
                .blur(radius: directionDBackdropTreatment ? 48 : 72)
                .opacity(directionDBackdropTreatment
                    ? min(0.70, palette.textureOpacity + 0.22)
                    : palette.textureOpacity)

            if directionDBackdropTreatment {
                Image(nsImage: payload.image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.12)
                    .blur(radius: 22)
                    .blendMode(.screen)
                    .opacity(0.10)
            }

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(directionDBackdropTreatment ? 0.14 : 0.34)

            LinearGradient(
                colors: [
                    color(palette.primary).opacity(directionDBackdropTreatment ? 0.62 : 0.86),
                    color(palette.secondary).opacity(directionDBackdropTreatment ? 0.74 : 0.94),
                    color(palette.glow).opacity(directionDBackdropTreatment ? 0.42 : 0.64)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    color(palette.glow).opacity(directionDBackdropTreatment ? 0.48 : 0.36),
                    .clear
                ],
                center: directionDBackdropTreatment
                    ? UnitPoint(x: 0.16, y: 0.44)
                    : .topTrailing,
                startRadius: 16,
                endRadius: 560
            )

            if directionDBackdropTreatment {
                // One continuous canvas: the lyric side is quieter, not a
                // second opaque panel.
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.10), Color.black.opacity(0.30)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                RadialGradient(
                    colors: [.clear, Color.black.opacity(0.44)],
                    center: .center,
                    startRadius: 160,
                    endRadius: 900
                )
            }
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
