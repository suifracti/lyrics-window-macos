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
    @State private var noiseImage: NSImage?
    @State private var palette = BackdropPalette.neutral
    @State private var accessibilityDisplayRevision = 0

    var body: some View {
        ZStack {
            neutralBackground

            if let outgoingArtworkImage {
                artworkLayers(image: outgoingArtworkImage)
                    .opacity(0.28)
                    .transition(.opacity)
            }

            if let artworkImage {
                artworkLayers(image: artworkImage)
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

    private var effectiveBlurRadius: Double {
        if settings.v3InstrumentalPureImmersion && isInstrumental {
            return 8.0
        }
        return settings.v3BackdropBlurRadius
    }

    private var effectiveScreenBlurRadius: Double {
        if settings.v3InstrumentalPureImmersion && isInstrumental {
            return 2.0
        }
        return settings.v3BackdropBlurRadius * 0.3
    }

    @ViewBuilder
    private func artworkLayers(image: NSImage) -> some View {
        let style = presentationStyle
        let saturation = min(
            1.4,
            style.paletteSaturation * 1.35 + (increaseContrast ? 0.08 : 0)
        )

        // complete artwork plane scaledToFit()
        // texture layer: lower-radius pass over cached thumbnail
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .scaleEffect(style.artworkScreenScale)
            .blur(radius: max(2, effectiveScreenBlurRadius))
            .blendMode(.screen)
            .opacity(min(1, style.artworkScreenOpacity * style.textureIntensity * 1.2))

        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .scaleEffect(style.artworkScale)
            .blur(radius: max(4, effectiveBlurRadius))
            .opacity(min(1, style.artworkOpacity * style.textureIntensity * 1.1))

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

        // Symmetrical ambient radial glow centered on the artwork canvas
        RadialGradient(
            colors: [
                color(palette.glow, saturation: saturation)
                    .opacity(min(1, style.glowIntensity * 0.5)),
                .clear
            ],
            center: UnitPoint(x: 0.16, y: 0.52),
            startRadius: 40,
            endRadius: 750
        )

        // lyric readability layer: trailing dark gradient scrim over the lyrics area for high contrast
        let lyricVeilOpacity = min(0.35, max(0.12, palette.luminance * 0.30))
        LinearGradient(
            colors: [
                .clear,
                Color.black.opacity(lyricVeilOpacity * 0.35),
                Color.black.opacity(lyricVeilOpacity)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )

        // vignette layer: subtle edge darkening
        RadialGradient(
            colors: [
                .clear,
                Color.black.opacity(min(0.40, style.vignetteIntensity * 0.8))
            ],
            center: .center,
            startRadius: 150,
            endRadius: 920
        )

        // noise layer
        if let noiseImage {
            Image(nsImage: noiseImage)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(style.noiseIntensity)
        }
    }

    @MainActor
    private func loadSnapshot(for key: String) async {
        outgoingArtworkImage = artworkImage
        artworkImage = nil
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
        let nextNoise = NSImage(data: snapshot.noiseData)
        withAnimation(.easeInOut(duration: artworkTransitionDuration)) {
            palette = snapshot.palette
            artworkImage = nextArtwork
            noiseImage = nextNoise
        }

        try? await Task.sleep(
            nanoseconds: UInt64(outgoingTransitionDuration * 1_000_000_000)
        )
        guard key == requestKey, !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: outgoingTransitionDuration)) {
            outgoingArtworkImage = nil
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
}

public struct AppleMusicImmersiveV3BackdropSnapshot: Sendable {
    public let artworkData: Data
    public let noiseData: Data
    public let palette: BackdropPalette

    /// The snapshot keeps the sampled values together so V3 and fullscreen
    /// consume the same immutable, track-bound evidence rather than deriving
    /// their own background state.
    public var luminance: Double { palette.luminance }
    public var saturation: Double { palette.saturation }
    public var readabilityVeilOpacity: Double { palette.readabilityVeilOpacity }

    public init(artworkData: Data, noiseData: Data, palette: BackdropPalette) {
        self.artworkData = artworkData
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
        let reducedArtwork = thumbnailData(from: artworkData, maxPixel: 320)
        let palette = BackdropPalette.from(imageData: reducedArtwork)
        let noise = makeNoiseData(seed: seed)
        return AppleMusicImmersiveV3BackdropSnapshot(
            artworkData: reducedArtwork,
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
