import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// A single track-bound key projection shared by V3 and fullscreen through
/// the same backdrop view and cache. Playback time is intentionally absent.
enum AppleMusicImmersiveV3BackdropKey {
    static func make(
        identityKey: String,
        artworkURL: URL?,
        forceNoArtwork: Bool
    ) -> String {
        "\(identityKey)|\(artworkURL?.absoluteString ?? "no-artwork")|\(forceNoArtwork ? "debug-no-artwork" : "artwork")"
    }
}

/// The V3 backdrop is deliberately track-bound rather than playback-bound.
/// Cover data is reduced and sampled once per TrackIdentity/artwork key; the
/// SwiftUI view never rebuilds a full-resolution blur on every time tick.
struct AppleMusicImmersiveV3BackdropView: View {
    let track: Track
    let identity: TrackIdentity?
    var isInstrumental: Bool = false
    @ObservedObject var settings: AppSettingsStore

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var artworkImage: NSImage?
    @State private var outgoingArtworkImage: NSImage?
    @State private var ambientArtworkImage: NSImage?
    @State private var outgoingAmbientArtworkImage: NSImage?
    @State private var noiseImage: NSImage?
    @State private var palette = BackdropPalette.neutral
    @State private var accessibilityDisplayRevision = 0

    var body: some View {
        ZStack {
            neutralBackground

            if let outgoingArtworkImage {
                artworkLayers(
                    image: outgoingArtworkImage,
                    ambientImage: outgoingAmbientArtworkImage
                )
                    .opacity(0.28)
                    .transition(.opacity)
            }

            if let artworkImage {
                artworkLayers(image: artworkImage, ambientImage: ambientArtworkImage)
                    .transition(.opacity)
            }

            // The veil is intentionally independent of playback position.
            Color.black.opacity(readabilityVeilOpacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: requestKey) {
            await loadSnapshot(for: requestKey)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
            )
        ) { _ in
            accessibilityDisplayRevision &+= 1
        }
    }

    private var requestKey: String {
        let identityKey = identity?.stableKey ?? track.id
        return AppleMusicImmersiveV3BackdropKey.make(
            identityKey: identityKey,
            artworkURL: track.artworkURL,
            forceNoArtwork: debugForceNoArtwork
        )
    }

    /// Debug-only visual validation switch. It exercises the same neutral
    /// fallback path without creating a second artwork loader or altering
    /// production behavior.
    private var debugForceNoArtwork: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["SPOTIFYLYRICS_BACKDROP_NO_ARTWORK"] == "1"
#else
        false
#endif
    }

    private var presentationID: BackdropPresentationID {
        BackdropPresentationID.active
    }

    private var presentationStyle: BackdropPresentationStyle {
        presentationID.style
    }

    private var reduceTransparency: Bool {
        // Referencing the revision makes the view redraw when the system
        // accessibility display options change without reloading artwork.
        let _ = accessibilityDisplayRevision
        return NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    private var increaseContrast: Bool {
        let _ = accessibilityDisplayRevision
        return NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    private var readabilityVeilOpacity: Double {
        let style = presentationStyle
        let baseVeil = max(
            style.minimumLyricVeil,
            palette.readabilityVeilOpacity * style.lyricVeilMultiplier
        )

        // Moderate luminance adjustment for bright covers to preserve artwork glow
        let luminanceBoost = palette.luminance > 0.5 ? (palette.luminance - 0.5) * 0.32 : 0.0
        let paletteVeil = min(0.38, baseVeil + luminanceBoost)

        if reduceTransparency {
            return min(0.90, max(0.62, paletteVeil + 0.18))
        }

        if increaseContrast {
            return min(0.88, paletteVeil + 0.14)
        }

        return min(0.42, paletteVeil)
    }

    private var artworkTransitionDuration: Double {
        accessibilityReduceMotion
            ? LyricsDesignTokens.Motion.reduceMotionDuration
            : presentationStyle.transitionDuration
    }

    private var outgoingTransitionDuration: Double {
        accessibilityReduceMotion
            ? LyricsDesignTokens.Motion.reduceMotionDuration
            : presentationStyle.outgoingTransitionDuration
    }

    private var neutralBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    color(BackdropPalette.neutral.primary),
                    color(BackdropPalette.neutral.secondary),
                    color(BackdropPalette.neutral.glow)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [
                    color(BackdropPalette.neutral.glow).opacity(0.42),
                    .clear
                ],
                center: UnitPoint(x: 0.16, y: 0.5),
                startRadius: 20,
                endRadius: 520
            )
        }
    }

    private var normalizedBlur: Double {
        max(0, min(100, settings.v3BackdropBlurRadius)) / 100.0
    }

    private var effectiveBlurRadius: Double {
        if settings.v3InstrumentalPureImmersion && isInstrumental {
            return 4.0
        }
        // Crisp continuous linear mapping (0% = 0.0pt, 25% = 7.0pt, 60% = 16.8pt, 100% = 28.0pt)
        // 0% is 100% clear artwork image, 100% maxes out at a soft 28pt blur instead of heavy mush
        return normalizedBlur * 28.0
    }

    private var effectiveScreenBlurRadius: Double {
        if settings.v3InstrumentalPureImmersion && isInstrumental {
            return 1.2
        }
        return normalizedBlur * 14.0
    }

    private var coverLightCenter: UnitPoint {
        let position = settings.v3ArtworkPosition
        if position == "right" {
            return UnitPoint(x: 0.78, y: 0.42)
        } else if position == "center" {
            return UnitPoint(x: 0.50, y: 0.38)
        } else {
            return UnitPoint(x: 0.22, y: 0.42)
        }
    }

    @ViewBuilder
    private func artworkLayers(image: NSImage, ambientImage: NSImage?) -> some View {
        switch settings.v3ArtworkPresentation {
        case .ambient:
            ambientArtworkLayers(image: image, ambientImage: ambientImage)
        case .stage:
            stageArtworkLayers(image: image, ambientImage: ambientImage)
        case .classic:
            legacyArtworkLayers(image: image)
        }
    }

    @ViewBuilder
    private func stageArtworkLayers(image: NSImage, ambientImage: NSImage?) -> some View {
        let saturation = min(
            1.32,
            presentationStyle.paletteSaturation * 1.20 + (increaseContrast ? 0.06 : 0)
        )

        // Extend album colour beyond the aspect-fitted artwork without using
        // an arbitrary readable crop as the whole window.
        LinearGradient(
            colors: [
                ambientColor(palette.primary, saturation: saturation, maximumLuminance: 0.36),
                ambientColor(palette.secondary, saturation: saturation, maximumLuminance: 0.24),
                Color(red: 0.045, green: 0.048, blue: 0.058)
            ],
            startPoint: coverLightCenter,
            endPoint: settings.v3ArtworkPosition == "right" ? .topLeading : .bottomTrailing
        )

        if let ambientImage {
            Image(nsImage: ambientImage)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .scaleEffect(1.18)
                .blur(radius: normalizedBlur * 68, opaque: true)
                .saturation(saturation)
                .brightness(-normalizedBlur * 0.12)
                .opacity(normalizedBlur * 0.42)
        }

        // One recognisable, aspect-fitted artwork plane sits inside the
        // colour field. There is no duplicate foreground cover card.
        GeometryReader { geometry in
            let scale = min(1.4, max(0.8, settings.v3ArtworkSizeScale))
            let artworkAspectRatio = image.size.width > 0 && image.size.height > 0
                ? image.size.width / image.size.height
                : 1.0
            let artworkRect = stageArtworkPlaneSize(
                canvas: geometry.size,
                artworkAspectRatio: artworkAspectRatio,
                requestedScale: scale
            )

            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: artworkRect.width, height: artworkRect.height)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .position(x: artworkRect.midX, y: artworkRect.midY)
                .blur(radius: normalizedBlur * 10.0)
                .saturation(1.0 + normalizedBlur * (saturation - 1.0))
                .brightness(-normalizedBlur * 0.08)
                .opacity(1.0 - normalizedBlur * 0.12)
                .shadow(
                    color: Color.black.opacity(0.20 + normalizedBlur * 0.10),
                    radius: 28,
                    x: 0,
                    y: 10
                )
        }

        stageReadingVeil

        RadialGradient(
            colors: [
                .clear,
                Color.black.opacity(min(0.38, presentationStyle.vignetteIntensity * 0.70))
            ],
            center: coverLightCenter,
            startRadius: 220,
            endRadius: 980
        )

        if let noiseImage {
            Image(nsImage: noiseImage)
                .resizable(resizingMode: .tile)
                .blendMode(.softLight)
                .opacity(min(0.045, presentationStyle.noiseIntensity))
        }
    }

    /// Stage is the only complete-cover backdrop. The user size range changes
    /// how much of the canvas it occupies, but never lets the square exceed
    /// the available window and silently turn back into a cropped wallpaper.
    private func stageArtworkPlaneSize(
        canvas: CGSize,
        artworkAspectRatio: CGFloat,
        requestedScale: CGFloat
    ) -> CGRect {
        V3ResponsiveGeometry.stageArtworkRect(
            canvasSize: canvas,
            artworkAspectRatio: artworkAspectRatio,
            requestedScale: requestedScale,
            position: settings.v3ArtworkPosition
        )
    }

    @ViewBuilder
    private var stageReadingVeil: some View {
        if settings.v3ArtworkPosition == "right" {
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.54), location: 0),
                    .init(color: Color.black.opacity(0.24), location: 0.46),
                    .init(color: .clear, location: 0.78)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else if settings.v3ArtworkPosition == "center" {
            LinearGradient(
                colors: [Color.black.opacity(0.14), Color.black.opacity(0.30)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.18),
                    .init(color: Color.black.opacity(0.16), location: 0.48),
                    .init(color: Color.black.opacity(0.58), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    @ViewBuilder
    private func ambientArtworkLayers(image: NSImage, ambientImage: NSImage?) -> some View {
        let style = presentationStyle
        let saturation = min(
            1.3,
            style.paletteSaturation * 1.18 + (increaseContrast ? 0.06 : 0)
        )
        let diffusionRadius = normalizedBlur * 66.0

        // A luminance-clamped album field keeps very bright artwork legible
        // without falling back to an unrelated black canvas.
        LinearGradient(
            colors: [
                ambientColor(palette.primary, saturation: saturation, maximumLuminance: 0.42),
                ambientColor(palette.secondary, saturation: saturation * 0.90, maximumLuminance: 0.30),
                Color(red: 0.055, green: 0.060, blue: 0.072)
            ],
            startPoint: coverLightCenter,
            endPoint: settings.v3ArtworkPosition == "right" ? .topLeading : .bottomTrailing
        )

        // At 0% the slider means what it says: the high-resolution artwork is
        // visible without an artificial blur. As diffusion increases it fades
        // into the low-frequency derivative instead of abruptly becoming a
        // different composition.
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .scaleEffect(1.02 + normalizedBlur * 0.06)
            .blur(radius: normalizedBlur * 8.0, opaque: true)
            .saturation(1.0 + normalizedBlur * (saturation - 1.0))
            .brightness(-normalizedBlur * 0.10)
            .opacity(0.52 * (1.0 - normalizedBlur))

        // The 48px derivative owns only the diffused end of the slider.
        if let ambientImage {
            Image(nsImage: ambientImage)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .scaleEffect(1.12)
                .blur(radius: diffusionRadius, opaque: true)
                .saturation(saturation)
                .brightness(-normalizedBlur * 0.10)
                .opacity(normalizedBlur * 0.46)
        }

        RadialGradient(
            colors: [
                ambientColor(palette.glow, saturation: saturation, maximumLuminance: 0.58)
                    .opacity(0.34),
                ambientColor(palette.primary, saturation: saturation, maximumLuminance: 0.40)
                    .opacity(0.12),
                .clear
            ],
            center: coverLightCenter,
            startRadius: 18,
            endRadius: 680 + normalizedBlur * 220
        )
        .blendMode(.screen)

        ambientReadingVeil

        RadialGradient(
            colors: [
                .clear,
                Color.black.opacity(min(0.36, style.vignetteIntensity * 0.72))
            ],
            center: coverLightCenter,
            startRadius: 180,
            endRadius: 980
        )

        if let noiseImage {
            Image(nsImage: noiseImage)
                .resizable(resizingMode: .tile)
                .blendMode(.softLight)
                .opacity(min(0.055, style.noiseIntensity))
        }
    }

    @ViewBuilder
    private var ambientReadingVeil: some View {
        if settings.v3ArtworkPosition == "right" {
            LinearGradient(
                colors: [Color.black.opacity(0.42), Color.black.opacity(0.18), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else if settings.v3ArtworkPosition == "center" {
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.34)],
                center: .center,
                startRadius: 160,
                endRadius: 920
            )
        } else {
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.16), Color.black.opacity(0.46)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    @ViewBuilder
    private func legacyArtworkLayers(image: NSImage) -> some View {
        let style = presentationStyle
        let saturation = min(
            1.4,
            style.paletteSaturation * 1.35 + (increaseContrast ? 0.08 : 0)
        )

        // complete artwork plane scaledToFit()
        // Layer 0: Static Album Ambient Base (Dark-neutral album color transition, 100% independent of Blur slider)
        LinearGradient(
            colors: [
                color(palette.primary, saturation: saturation * 0.35).opacity(0.80),
                color(palette.secondary, saturation: saturation * 0.25).opacity(0.60)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        // Layer 1: Restrained Cover Ambient Light Source (Dynamic anchor emitting from physical album cover)
        ZStack {
            color(palette.primary, saturation: saturation)
                .opacity(0.85)

            RadialGradient(
                colors: [
                    color(palette.primary, saturation: saturation * 1.15).opacity(0.14),
                    .clear
                ],
                center: coverLightCenter,
                startRadius: 40,
                endRadius: 900
            )

            RadialGradient(
                colors: [
                    color(palette.glow, saturation: saturation * 1.10).opacity(0.08),
                    .clear
                ],
                center: coverLightCenter,
                startRadius: 20,
                endRadius: 750
            )
        }
        .opacity(0.35 + 0.65 * normalizedBlur)

        // Layer 2: Main scaled cover substrate. Unlike the old implementation,
        // both the full 80–140% range and crop position now affect this image.
        GeometryReader { geometry in
            let scale = min(1.4, max(0.8, settings.v3ArtworkSizeScale))
            let mainSubstrateImage = Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(style.artworkScale * scale)
                .offset(x: classicArtworkOffset(for: geometry.size.width))
                .blur(radius: effectiveBlurRadius)
                .opacity(min(1, style.artworkOpacity * style.textureIntensity))

            if settings.v3ArtworkPosition == "left" {
                mainSubstrateImage
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0.00),
                                .init(color: .black, location: 0.28),
                                .init(color: .black.opacity(0.85), location: 0.45),
                                .init(color: .black.opacity(0.40), location: 0.62),
                                .init(color: .black.opacity(0.12), location: 0.78),
                                .init(color: .clear, location: 0.92)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            } else {
                mainSubstrateImage
            }
        }

        // Layer 3: Specular Screen Light Bloom Pass (Only active when blur > 0 to avoid obscuring 0% clear artwork)
        if effectiveScreenBlurRadius > 0 {
            GeometryReader { geometry in
                let scale = min(1.4, max(0.8, settings.v3ArtworkSizeScale))

                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(style.artworkScreenScale * scale)
                    .offset(x: classicArtworkOffset(for: geometry.size.width))
                    .blur(radius: effectiveScreenBlurRadius)
                    .blendMode(.screen)
                    .opacity(0.35 * style.textureIntensity * normalizedBlur)
            }
        }

        // Layer 4: Overlay blend color gradient for vivid color saturation
        LinearGradient(
            colors: [
                color(palette.primary, saturation: saturation)
                    .opacity(min(1, 0.28 * style.paletteOpacity)),
                color(palette.secondary, saturation: saturation)
                    .opacity(min(1, 0.22 * style.paletteOpacity)),
                color(palette.glow, saturation: saturation)
                    .opacity(min(1, 0.18 * style.paletteOpacity))
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .blendMode(.overlay)

        // Layer 5: Soft Continuous Spatial Light Falloff towards lyrics reading area
        let lightDecayOpacity = min(0.18, max(0.05, palette.luminance * 0.15))
        LinearGradient(
            colors: [
                .clear,
                Color.black.opacity(lightDecayOpacity * 0.40),
                Color.black.opacity(lightDecayOpacity)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )

        // Layer 6: Edge Vignette Darkening
        RadialGradient(
            colors: [
                .clear,
                Color.black.opacity(min(0.35, style.vignetteIntensity * 0.65))
            ],
            center: .center,
            startRadius: 160,
            endRadius: 950
        )

        // Procedural Grain Noise Overlay (防断层极轻微感)
        if let noiseImage {
            Image(nsImage: noiseImage)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(style.noiseIntensity * 0.8)
        }
    }

    private func classicArtworkOffset(for width: CGFloat) -> CGFloat {
        switch settings.v3ArtworkPosition {
        case "right": return width * 0.10
        case "center": return 0
        default: return width * -0.10
        }
    }

    @MainActor
    private func loadSnapshot(for key: String) async {
        outgoingArtworkImage = artworkImage
        outgoingAmbientArtworkImage = ambientArtworkImage
        artworkImage = nil
        ambientArtworkImage = nil
        noiseImage = nil
        // A track without artwork must not inherit the previous track's
        // palette while its new snapshot is being resolved.
        palette = .neutral

        if debugForceNoArtwork {
            outgoingArtworkImage = nil
            return
        }

        guard let artworkURL = track.artworkURL,
              let image = await ArtworkImageLoader.shared.image(for: artworkURL),
              let imageData = image.tiffRepresentation,
              !Task.isCancelled else {
            outgoingArtworkImage = nil
            return
        }

        let snapshot = await AppleMusicImmersiveV3BackdropCache.shared.snapshot(
            for: key,
            artworkData: imageData
        )
        guard key == requestKey, !Task.isCancelled else { return }

        let nextArtwork = NSImage(data: snapshot.artworkData)
        let nextAmbientArtwork = NSImage(data: snapshot.ambientArtworkData)
        let nextNoise = NSImage(data: snapshot.noiseData)
        withAnimation(.easeInOut(duration: artworkTransitionDuration)) {
            palette = snapshot.palette
            artworkImage = nextArtwork
            ambientArtworkImage = nextAmbientArtwork
            noiseImage = nextNoise
        }

        try? await Task.sleep(
            nanoseconds: UInt64(outgoingTransitionDuration * 1_000_000_000)
        )
        guard key == requestKey, !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: outgoingTransitionDuration)) {
            outgoingArtworkImage = nil
            outgoingAmbientArtworkImage = nil
        }
    }

    private func color(_ value: BackdropColor, saturation: Double = 1) -> Color {
        let luminance = (value.red * 0.2126)
            + (value.green * 0.7152)
            + (value.blue * 0.0722)
        let amount = min(1, max(0, saturation))
        return Color(
            red: luminance + (value.red - luminance) * amount,
            green: luminance + (value.green - luminance) * amount,
            blue: luminance + (value.blue - luminance) * amount
        )
    }

    private func ambientColor(
        _ value: BackdropColor,
        saturation: Double,
        maximumLuminance: Double
    ) -> Color {
        // Near-monochrome and white artwork otherwise collapses into flat
        // cement gray. Blend only a restrained midnight-blue anchor into
        // those palettes; colorful covers remain entirely album-derived.
        let lowChromaAnchorAmount = min(
            0.30,
            max(0, (0.16 - palette.saturation) / 0.16) * 0.30
        )
        let anchor = BackdropColor(red: 0.08, green: 0.12, blue: 0.18)
        let anchored = BackdropColor(
            red: value.red + (anchor.red - value.red) * lowChromaAnchorAmount,
            green: value.green + (anchor.green - value.green) * lowChromaAnchorAmount,
            blue: value.blue + (anchor.blue - value.blue) * lowChromaAnchorAmount
        )
        let sourceLuminance = max(
            0.001,
            (anchored.red * 0.2126) + (anchored.green * 0.7152) + (anchored.blue * 0.0722)
        )
        let scale = min(1, maximumLuminance / sourceLuminance)
        let red = anchored.red * scale
        let green = anchored.green * scale
        let blue = anchored.blue * scale
        let clampedLuminance = (red * 0.2126) + (green * 0.7152) + (blue * 0.0722)
        let amount = min(1, max(0, saturation))
        return Color(
            red: clampedLuminance + (red - clampedLuminance) * amount,
            green: clampedLuminance + (green - clampedLuminance) * amount,
            blue: clampedLuminance + (blue - clampedLuminance) * amount
        )
    }
}

public struct AppleMusicImmersiveV3BackdropSnapshot: Sendable {
    public let artworkData: Data
    public let ambientArtworkData: Data
    public let noiseData: Data
    public let palette: BackdropPalette

    /// The snapshot keeps the sampled values together so V3 and fullscreen
    /// consume the same immutable, track-bound evidence rather than deriving
    /// their own background state.
    public var luminance: Double { palette.luminance }
    public var saturation: Double { palette.saturation }
    public var readabilityVeilOpacity: Double { palette.readabilityVeilOpacity }

    public init(
        artworkData: Data,
        ambientArtworkData: Data,
        noiseData: Data,
        palette: BackdropPalette
    ) {
        self.artworkData = artworkData
        self.ambientArtworkData = ambientArtworkData
        self.noiseData = noiseData
        self.palette = palette
    }
}

/// Cached low-resolution artwork and optional procedural texture for V3.
/// The key includes TrackIdentity so a reused cover URL on another track does
/// not accidentally keep stale color treatment.
public actor AppleMusicImmersiveV3BackdropCache {
    public static let shared = AppleMusicImmersiveV3BackdropCache()

    private var values: [String: AppleMusicImmersiveV3BackdropSnapshot] = [:]
    private var inFlight: [String: Task<AppleMusicImmersiveV3BackdropSnapshot, Never>] = [:]
    private var order: [String] = []
    private let capacity = 48

    public init() {}

    public func snapshot(
        for key: String,
        artworkData: Data
    ) async -> AppleMusicImmersiveV3BackdropSnapshot {
        if let cached = values[key] {
            return cached
        }
        if let task = inFlight[key] {
            return await task.value
        }

        let task = Task.detached(priority: .utility) {
            Self.makeSnapshot(artworkData: artworkData, seed: Self.seed(for: key))
        }
        inFlight[key] = task

        let snapshot = await task.value
        inFlight[key] = nil
        values[key] = snapshot
        order.removeAll { $0 == key }
        order.append(key)
        if order.count > capacity, let evicted = order.first {
            order.removeFirst()
            values[evicted] = nil
        }
        return snapshot
    }

    private nonisolated static func makeSnapshot(
        artworkData: Data,
        seed: UInt64
    ) -> AppleMusicImmersiveV3BackdropSnapshot {
        // The visible artwork is also used by the zero-blur ambient and
        // stage presentations. 640px makes a large window look soft even
        // when the user explicitly selects 0%; keep the derivative small,
        // but retain enough resolution for the actual artwork plane.
        let reducedArtwork = thumbnailData(from: artworkData, maxPixel: 1280)
        let ambientArtwork = thumbnailData(from: artworkData, maxPixel: 48)
        let palette = BackdropPalette.from(imageData: reducedArtwork)
        let noise = makeNoiseData(seed: seed)
        return AppleMusicImmersiveV3BackdropSnapshot(
            artworkData: reducedArtwork,
            ambientArtworkData: ambientArtwork,
            noiseData: noise,
            palette: palette
        )
    }

    private nonisolated static func thumbnailData(from data: Data, maxPixel: Int) -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return data
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ), let encoded = encode(thumbnail, as: .jpeg) else {
            return data
        }
        return encoded
    }

    private nonisolated static func makeNoiseData(seed: UInt64) -> Data {
        let size = 96
        var value = seed
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            value = value &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let gray = UInt8(112 + ((value >> 56) & 31))
            bytes[index] = gray
            bytes[index + 1] = gray
            bytes[index + 2] = gray
            bytes[index + 3] = 26
        }

        let rawData = Data(bytes)
        guard let provider = CGDataProvider(data: rawData as CFData),
              let image = CGImage(
                  width: size,
                  height: size,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: size * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ),
              let encoded = encode(image, as: .png) else {
            return Data()
        }
        return encoded
    }

    private nonisolated static func encode(_ image: CGImage, as type: UTType) -> Data? {
        let output = CFDataCreateMutable(nil, 0)
        guard let output,
              let destination = CGImageDestinationCreateWithData(
                  output,
                  type.identifier as CFString,
                  1,
                  nil
              ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private nonisolated static func seed(for key: String) -> UInt64 {
        key.utf8.reduce(14_695_981_039_346_656_037) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}
