import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The V3 backdrop is deliberately track-bound rather than playback-bound.
/// Cover data is reduced and sampled once per TrackIdentity/artwork key; the
/// SwiftUI view never rebuilds a full-resolution blur on every time tick.
struct AppleMusicImmersiveV3BackdropView: View {
    let track: Track
    let identity: TrackIdentity?

    @State private var artworkImage: NSImage?
    @State private var outgoingArtworkImage: NSImage?
    @State private var noiseImage: NSImage?
    @State private var palette = BackdropPalette.neutral

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
            Color.black.opacity(0.42)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: requestKey) {
            await loadSnapshot(for: requestKey)
        }
    }

    private var requestKey: String {
        let identityKey = identity?.stableKey ?? track.id
        return "\(identityKey)|\(track.artworkURL?.absoluteString ?? "no-artwork")"
    }

    private var neutralBackground: some View {
        LinearGradient(
            colors: [
                color(BackdropPalette.neutral.primary),
                color(BackdropPalette.neutral.secondary)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private func artworkLayers(image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .scaleEffect(1.5)
            .blur(radius: 120)
            .opacity(0.58)

        LinearGradient(
            colors: [
                color(palette.primary).opacity(0.78),
                color(palette.secondary).opacity(0.9),
                color(palette.glow).opacity(0.52)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        RadialGradient(
            colors: [
                color(palette.glow).opacity(0.28),
                .clear
            ],
            center: .topTrailing,
            startRadius: 12,
            endRadius: 620
        )

        if let noiseImage {
            Image(nsImage: noiseImage)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(0.035)
        }
    }

    @MainActor
    private func loadSnapshot(for key: String) async {
        outgoingArtworkImage = artworkImage
        artworkImage = nil
        noiseImage = nil

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
        withAnimation(.easeInOut(duration: 0.42)) {
            palette = snapshot.palette
            artworkImage = nextArtwork
            noiseImage = nextNoise
        }

        try? await Task.sleep(nanoseconds: 460_000_000)
        guard key == requestKey, !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            outgoingArtworkImage = nil
        }
    }

    private func color(_ value: BackdropColor) -> Color {
        Color(red: value.red, green: value.green, blue: value.blue)
    }
}

public struct AppleMusicImmersiveV3BackdropSnapshot: Sendable {
    public let artworkData: Data
    public let noiseData: Data
    public let palette: BackdropPalette

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
