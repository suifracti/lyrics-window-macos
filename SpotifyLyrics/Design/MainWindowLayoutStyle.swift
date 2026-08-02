import Foundation

enum MainWindowLayoutStyle: String, CaseIterable, Identifiable {
    case lyricsFocus
    case immersiveSplit
    case appleMusicImmersiveV3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lyricsFocus:
            return "歌词专注"
        case .immersiveSplit:
            return "沉浸分栏"
        case .appleMusicImmersiveV3:
            return "Apple Music 沉浸 V3"
        }
    }

    var systemImage: String {
        switch self {
        case .lyricsFocus:
            return "text.alignleft"
        case .immersiveSplit:
            return "rectangle.split.2x1"
        case .appleMusicImmersiveV3:
            return "music.note.house"
        }
    }
}

/// Pure size projection for the Apple Music V3 canvas. This describes the
/// temporary presentation chosen by the available window geometry; it does
/// not replace the user's persisted layout family.
enum MainWindowResponsiveMode: String, Equatable, Sendable {
    case wide
    case medium
    case small
    case lyricsFocus

    static func resolve(
        width: CGFloat,
        height: CGFloat,
        automaticLyricsFocus: Bool,
        wideBreakpoint: CGFloat = 1_080,
        comfortableSize: CGSize = LyricsDesignTokens.comfortableMainWindowSize,
        compactFocusWidth: CGFloat = 900,
        compactFocusHeight: CGFloat = 640
    ) -> MainWindowResponsiveMode {
        if automaticLyricsFocus,
           width <= compactFocusWidth || height <= compactFocusHeight {
            return .lyricsFocus
        }

        if width >= wideBreakpoint {
            return .wide
        }

        if width >= comfortableSize.width,
           height >= comfortableSize.height {
            return .medium
        }

        return .small
    }
}
