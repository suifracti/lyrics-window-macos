import SwiftUI

enum LyricsDesignTokens {
    static let defaultMainWindowSize = CGSize(width: 1040, height: 680)
    static let minimumMainWindowSize = CGSize(width: 760, height: 520)

    static let contentCornerRadius: CGFloat = 20
    static let headerSpacing: CGFloat = 16
    static let lyricRowSpacing: CGFloat = 22
    static let canvasHorizontalPadding: CGFloat = 40
    static let canvasVerticalPadding: CGFloat = 72
    static let artworkSize: CGFloat = 84
    static let backdropArtworkSize: CGFloat = 260
    static let immersiveSplitBreakpoint: CGFloat = 900
    static let immersiveArtworkSize: CGFloat = 290
    static let immersiveColumnSpacing: CGFloat = 26
    static let immersiveWindowPadding: CGFloat = 28

    static let primaryText = Color(red: 0.96, green: 0.94, blue: 0.90)
    static let secondaryText = Color(red: 0.77, green: 0.78, blue: 0.80)
    static let mutedText = Color(red: 0.58, green: 0.60, blue: 0.64)
    static let accent = Color(red: 0.86, green: 0.76, blue: 0.58)
    static let controlBackground = Color.white.opacity(0.08)
    static let controlBorder = Color.white.opacity(0.12)

    static let backdropGradient = LinearGradient(
        colors: [
            Color(red: 0.035, green: 0.045, blue: 0.075),
            Color(red: 0.085, green: 0.080, blue: 0.105),
            Color(red: 0.025, green: 0.030, blue: 0.055)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func lyricEmphasis(
        isActive: Bool,
        distance: Int,
        isSynchronized: Bool = true
    ) -> LyricEmphasis {
        if !isSynchronized {
            return LyricEmphasis(
                primaryFontSize: 24,
                secondaryFontSize: 14,
                opacity: 0.82,
                blurRadius: 0,
                verticalPadding: 7
            )
        }

        if isActive {
            return LyricEmphasis(
                primaryFontSize: 34,
                secondaryFontSize: 15,
                opacity: 1.0,
                blurRadius: 0,
                verticalPadding: 12
            )
        }

        if distance == 1 {
            return LyricEmphasis(
                primaryFontSize: 26,
                secondaryFontSize: 14,
                opacity: 0.62,
                blurRadius: 0.6,
                verticalPadding: 7
            )
        }

        return LyricEmphasis(
            primaryFontSize: 22,
            secondaryFontSize: 12,
            opacity: 0.32,
            blurRadius: 1.8,
            verticalPadding: 5
        )
    }
}

struct LyricEmphasis {
    let primaryFontSize: CGFloat
    let secondaryFontSize: CGFloat
    let opacity: Double
    let blurRadius: CGFloat
    let verticalPadding: CGFloat
}
