import Foundation

/// A renderer descriptor is the pure, value-only half of the Preview Adapter
/// registry. SwiftUI adapters resolve the same kind below, but the registry
/// itself never owns an ObservableObject, a task, a timer, or a window.
public struct PresentationPreviewRendererDescriptor: Equatable, Hashable, Sendable {
    public let stableID: String
    public let category: PresentationCategory
    public let kind: String
    public let signature: String

    public init(stableID: String, category: PresentationCategory, kind: String, signature: String) {
        self.stableID = stableID
        self.category = category
        self.kind = kind
        self.signature = signature
    }
}

public struct PresentationPreviewRendererRegistry: Sendable {
    public static let shared = PresentationPreviewRendererRegistry()

    public let descriptors: [PresentationPreviewRendererDescriptor]

    public init(descriptors: [PresentationPreviewRendererDescriptor]? = nil) {
        self.descriptors = descriptors ?? Self.defaultDescriptors
    }

    public func descriptor(for stableID: String) -> PresentationPreviewRendererDescriptor? {
        descriptors.first { $0.stableID == stableID }
    }

    public func hasRenderer(for stableID: String) -> Bool {
        descriptor(for: stableID) != nil
    }

    public func signature(for stableID: String) -> String? {
        descriptor(for: stableID)?.signature
    }

    private static let defaultDescriptors: [PresentationPreviewRendererDescriptor] = [
        descriptor("mainWindow.lyricsFocus.v1", .mainWindow, "main.lyricsFocus", "main.lyricsFocus.v1.lyrics-first"),
        descriptor("mainWindow.immersiveSplit.v2", .mainWindow, "main.immersiveSplit", "main.immersiveSplit.v2.split-columns"),
        descriptor("mainWindow.appleMusicImmersiveV3.v3", .mainWindow, "main.appleMusicImmersiveV3", "main.appleMusicImmersiveV3.v3.cover-lyrics"),
        descriptor("mainWindow.directionD.v4", .mainWindow, "main.directionD", "mainWindow.directionD.v4.live-projection"),

        descriptor("fullscreen.borderlessPanel.v1", .fullscreen, "fullscreen.borderlessPanel", "fullscreen.borderlessPanel.v1.canvas"),

        descriptor("capsule.legacy.v1", .capsule, "capsule.legacy", "capsule.legacy.v1.material-panel"),
        descriptor("capsule.controlFocused.v2", .capsule, "capsule.controlFocused", "capsule.controlFocused.v2.control-strip"),
        descriptor("capsule.dynamicIslandDark.v4", .capsule, "capsule.dynamicIslandDark", "capsule.dynamicIslandDark.v4.island"),

        descriptor("floatingLyrics.legacyPanel.v1", .floatingLyrics, "floating.legacyPanel", "floating.legacyPanel.v1.panel"),
        descriptor("floatingLyrics.transparent.v2", .floatingLyrics, "floating.transparent", "floating.transparent.v2.text-layer"),

        descriptor("backdrop.legacyV3.v1", .backdrop, "backdrop.legacyV3", "backdrop.legacyV3.v1.compat"),
        descriptor("backdrop.default.v1", .backdrop, "backdrop.default", "backdrop.default.v1.balanced"),
        descriptor("backdrop.clear.v1", .backdrop, "backdrop.clear", "backdrop.clear.v1.quiet"),
        descriptor("backdrop.immersive.v1", .backdrop, "backdrop.immersive", "backdrop.immersive.v1.texture-glow"),
        descriptor("backdrop.highContrast.v1", .backdrop, "backdrop.highContrast", "backdrop.highContrast.v1.veil"),

        descriptor("lyricsTransition.system.v1", .lyricsTransition, "lyricsTransition.system", "lyricsTransition.system.v1.system"),
        descriptor("lyricsTransition.smoothRelayout.v1", .lyricsTransition, "lyricsTransition.smoothRelayout", "lyricsTransition.smoothRelayout.v1.relayout"),
        descriptor("lyricsTransition.none.v1", .lyricsTransition, "lyricsTransition.none", "lyricsTransition.none.v1.direct"),

        descriptor("lyricsStatePresentation.system.v1", .lyricsState, "lyricsState.system", "lyricsStatePresentation.system.v1.system"),
        descriptor("lyricsStatePresentation.contentFirst.v1", .lyricsState, "lyricsState.contentFirst", "lyricsStatePresentation.contentFirst.v1.content"),

        descriptor("progress.standard.v1", .progress, "progress.standard", "progress.standard.v1.full"),
        descriptor("progress.compact.v1", .progress, "progress.compact", "progress.compact.v1.compact"),
        descriptor("progress.focus.v1", .progress, "progress.focus", "progress.focus.v1.lyrics"),

        descriptor("responsiveLayout.wide.v1", .responsiveLayout, "layout.wide", "responsiveLayout.wide.v1.wide"),
        descriptor("responsiveLayout.medium.v1", .responsiveLayout, "layout.medium", "responsiveLayout.medium.v1.medium"),
        descriptor("responsiveLayout.small.v1", .responsiveLayout, "layout.small", "responsiveLayout.small.v1.small"),
        descriptor("responsiveLayout.lyricsFocus.v1", .responsiveLayout, "layout.lyricsFocus", "responsiveLayout.lyricsFocus.v1.focus")
    ]

    private static func descriptor(
        _ stableID: String,
        _ category: PresentationCategory,
        _ kind: String,
        _ signature: String
    ) -> PresentationPreviewRendererDescriptor {
        PresentationPreviewRendererDescriptor(
            stableID: stableID,
            category: category,
            kind: kind,
            signature: signature
        )
    }
}
