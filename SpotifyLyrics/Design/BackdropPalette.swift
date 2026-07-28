import AppKit
import Foundation

public struct BackdropColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
    }

    public var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: 1)
    }

    public static let neutral = BackdropColor(red: 0.12, green: 0.14, blue: 0.2)
}

public struct BackdropPalette: Equatable, Sendable {
    public let primary: BackdropColor
    public let secondary: BackdropColor
    public let glow: BackdropColor
    public let luminance: Double
    public let saturation: Double
    public let readabilityVeilOpacity: Double
    public let textureOpacity: Double

    public init(
        primary: BackdropColor,
        secondary: BackdropColor,
        glow: BackdropColor,
        luminance: Double,
        saturation: Double,
        readabilityVeilOpacity: Double,
        textureOpacity: Double
    ) {
        self.primary = primary
        self.secondary = secondary
        self.glow = glow
        self.luminance = luminance
        self.saturation = saturation
        self.readabilityVeilOpacity = readabilityVeilOpacity
        self.textureOpacity = textureOpacity
    }

    public static let neutral = BackdropPalette(
        primary: .neutral,
        secondary: BackdropColor(red: 0.08, green: 0.1, blue: 0.16),
        glow: BackdropColor(red: 0.24, green: 0.19, blue: 0.3),
        luminance: 0.14,
        saturation: 0.38,
        readabilityVeilOpacity: 0.34,
        textureOpacity: 0.28
    )

    public static func from(image: NSImage) -> BackdropPalette {
        guard let imageData = image.tiffRepresentation else {
            return .neutral
        }
        return from(imageData: imageData)
    }

    /// Computes the palette from immutable image data so callers can move the
    /// work off the main actor. The result is deterministic for a given cover.
    public static func from(imageData: Data) -> BackdropPalette {
        guard let representation = NSBitmapImageRep(data: imageData) else {
            return .neutral
        }

        let width = max(1, representation.pixelsWide)
        let height = max(1, representation.pixelsHigh)
        let step = max(1, max(width, height) / 32)
        var samples: [(color: BackdropColor, saturation: Double, luminance: Double)] = []

        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                guard let color = representation.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                let sample = BackdropColor(
                    red: Double(color.redComponent),
                    green: Double(color.greenComponent),
                    blue: Double(color.blueComponent)
                )
                samples.append((sample, saturation(of: sample), luminance(of: sample)))
            }
        }

        guard !samples.isEmpty else { return .neutral }
        let average = BackdropColor(
            red: samples.map { $0.color.red }.reduce(0, +) / Double(samples.count),
            green: samples.map { $0.color.green }.reduce(0, +) / Double(samples.count),
            blue: samples.map { $0.color.blue }.reduce(0, +) / Double(samples.count)
        )
        let vivid = samples.max { lhs, rhs in
            (lhs.saturation * 0.8 + lhs.luminance * 0.2) < (rhs.saturation * 0.8 + rhs.luminance * 0.2)
        }?.color ?? average
        let primary = blend(average, vivid, amount: 0.62)
        let secondary = blend(primary, BackdropColor(red: 0.02, green: 0.03, blue: 0.08), amount: 0.45)
        let glow = blend(vivid, BackdropColor(red: 0.8, green: 0.55, blue: 0.32), amount: 0.22)
        let averageLuminance = luminance(of: average)
        let averageSaturation = samples.map(\.saturation).reduce(0, +) / Double(samples.count)

        let veil: Double
        switch averageLuminance {
        case 0.72...:
            veil = 0.58
        case 0.5..<0.72:
            veil = 0.46
        case ..<0.16:
            veil = 0.34
        default:
            veil = 0.4
        }

        return BackdropPalette(
            primary: primary,
            secondary: secondary,
            glow: glow,
            luminance: averageLuminance,
            saturation: averageSaturation,
            readabilityVeilOpacity: max(veil, averageSaturation > 0.7 ? 0.44 : 0.28),
            textureOpacity: averageLuminance > 0.82 ? 0.24 : 0.34
        )
    }

    private static func luminance(of color: BackdropColor) -> Double {
        (color.red * 0.2126) + (color.green * 0.7152) + (color.blue * 0.0722)
    }

    private static func saturation(of color: BackdropColor) -> Double {
        let maximum = max(color.red, color.green, color.blue)
        let minimum = min(color.red, color.green, color.blue)
        guard maximum > 0 else { return 0 }
        return (maximum - minimum) / maximum
    }

    private static func blend(_ lhs: BackdropColor, _ rhs: BackdropColor, amount: Double) -> BackdropColor {
        let amount = min(1, max(0, amount))
        return BackdropColor(
            red: lhs.red + (rhs.red - lhs.red) * amount,
            green: lhs.green + (rhs.green - lhs.green) * amount,
            blue: lhs.blue + (rhs.blue - lhs.blue) * amount
        )
    }
}

/// Track-bound cache for the relatively expensive cover sampling step.
///
/// Playback position never participates in the cache key. A new palette is
/// computed only when the track/artwork identity changes, and the sampling is
/// performed in a detached utility task rather than in a SwiftUI body.
public actor BackdropPaletteCache {
    public static let shared = BackdropPaletteCache()

    private var values: [String: BackdropPalette] = [:]
    private var order: [String] = []
    private var inFlight: [String: Task<BackdropPalette, Never>] = [:]
    private let capacity = 64

    public init() {}

    public func palette(for key: String, imageData: Data) async -> BackdropPalette {
        if let cached = values[key] {
            return cached
        }

        if let task = inFlight[key] {
            return await task.value
        }

        let task = Task.detached(priority: .utility) {
            BackdropPalette.from(imageData: imageData)
        }
        inFlight[key] = task

        let palette = await task.value
        inFlight[key] = nil
        values[key] = palette
        order.removeAll { $0 == key }
        order.append(key)

        if order.count > capacity, let evicted = order.first {
            order.removeFirst()
            values[evicted] = nil
        }

        return palette
    }
}
