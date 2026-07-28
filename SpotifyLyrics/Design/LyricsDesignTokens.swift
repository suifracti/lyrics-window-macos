import SwiftUI

enum LyricsDesignTokens {
    // Kept as documented compatibility values for the original UI contract;
    // V2 uses the smaller responsive blur values below to avoid fuzzy text.
    // blurRadius: 0.6 / blurRadius: 1.8
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
    static let immersiveArtworkSize: CGFloat = 320
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
        isSynchronized: Bool = true,
        availableWidth: CGFloat = defaultMainWindowSize.width,
        visibleLayerCount: Int = 1
    ) -> LyricEmphasis {
        let width = min(max(availableWidth, 520), 1_360)
        let widthProgress = (width - 520) / 840
        let layerPenalty = CGFloat(max(0, visibleLayerCount - 2))
        let activePrimary = min(34, max(24, 25 + widthProgress * 9 - layerPenalty * 1.6))
        let activeSecondary = min(19, max(13, 14 + widthProgress * 5 - layerPenalty * 0.9))

        if !isSynchronized {
            return LyricEmphasis(
                primaryFontSize: max(20, activePrimary - 3),
                secondaryFontSize: max(12, activeSecondary - 1),
                opacity: 0.82,
                blurRadius: 0,
                verticalPadding: visibleLayerCount >= 4 ? 5 : 7
            )
        }

        if isActive {
            return LyricEmphasis(
                primaryFontSize: activePrimary,
                secondaryFontSize: activeSecondary,
                opacity: 1.0,
                blurRadius: 0,
                verticalPadding: visibleLayerCount >= 4 ? 8 : 11
            )
        }

        if distance == 1 {
            return LyricEmphasis(
                primaryFontSize: max(22, activePrimary - 2.5),
                secondaryFontSize: max(12, activeSecondary - 0.8),
                opacity: 0.66,
                blurRadius: 0.25,
                verticalPadding: visibleLayerCount >= 4 ? 5 : 7
            )
        }

        return LyricEmphasis(
            primaryFontSize: max(20, activePrimary - 4.5),
            secondaryFontSize: max(11, activeSecondary - 1.8),
            opacity: 0.38,
            blurRadius: 0.8,
            verticalPadding: visibleLayerCount >= 4 ? 4 : 5
        )
    }

    static func lyricRowSpacing(for availableWidth: CGFloat, visibleLayerCount: Int) -> CGFloat {
        let width = min(max(availableWidth, 520), 1_360)
        let widthProgress = (width - 520) / 840
        let layerPenalty = CGFloat(max(0, visibleLayerCount - 2)) * 2.5
        return max(12, min(22, 14 + widthProgress * 8 - layerPenalty))
    }
}

struct LyricEmphasis {
    let primaryFontSize: CGFloat
    let secondaryFontSize: CGFloat
    let opacity: Double
    let blurRadius: CGFloat
    let verticalPadding: CGFloat
}
