import SwiftUI

struct LyricLineView: View {
    let line: LyricLine
    let isActive: Bool
    let distance: Int
    let isSynchronized: Bool
    let preferences: DisplayPreferences
    let availableWidth: CGFloat
    let visibleLayerCount: Int

    init(
        line: LyricLine,
        isActive: Bool,
        distance: Int,
        isSynchronized: Bool,
        preferences: DisplayPreferences,
        availableWidth: CGFloat = LyricsDesignTokens.defaultMainWindowSize.width,
        visibleLayerCount: Int = 1
    ) {
        self.line = line
        self.isActive = isActive
        self.distance = distance
        self.isSynchronized = isSynchronized
        self.preferences = preferences
        self.availableWidth = availableWidth
        self.visibleLayerCount = visibleLayerCount
    }

    private var emphasis: LyricEmphasis {
        LyricsDesignTokens.lyricEmphasis(
            isActive: isActive,
            distance: distance,
            isSynchronized: isSynchronized,
            availableWidth: availableWidth,
            visibleLayerCount: visibleLayerCount
        )
    }

    private var fontWeight: Font.Weight {
        if isActive { return .semibold }
        if distance == 1 { return .medium }
        return .regular
    }

    private var hasVisibleContent: Bool {
        (preferences.showOriginal && !line.originalText.isEmpty)
            || (preferences.showTranslation && !(line.translationText ?? "").isEmpty)
            || (preferences.showRomaji && !(line.romajiText ?? "").isEmpty)
            || (preferences.showKana && !(line.kanaText ?? "").isEmpty)
    }

    @ViewBuilder
    var body: some View {
        if hasVisibleContent {
            VStack(alignment: .leading, spacing: 5) {
                if preferences.showOriginal, !line.originalText.isEmpty {
                    Text(line.originalText)
                        .font(.system(size: emphasis.primaryFontSize, weight: fontWeight, design: .rounded))
                        .foregroundStyle(LyricsDesignTokens.primaryText.opacity(emphasis.opacity))
                        .lineSpacing(isActive ? 3 : 2)
                }

                if preferences.showKana, let kana = line.kanaText, !kana.isEmpty {
                    Text(kana)
                        .font(.system(size: emphasis.secondaryFontSize, weight: fontWeight == .semibold ? .medium : .regular, design: .rounded))
                        .foregroundStyle(LyricsDesignTokens.secondaryText.opacity(emphasis.opacity * 0.96))
                        .lineSpacing(2)
                }

                if preferences.showRomaji, let romaji = line.romajiText, !romaji.isEmpty {
                    Text(romaji)
                        .font(.system(size: emphasis.secondaryFontSize, weight: .regular, design: .rounded))
                        .foregroundStyle(LyricsDesignTokens.mutedText.opacity(emphasis.opacity))
                        .lineSpacing(2)
                }

                if preferences.showTranslation, let translation = line.translationText, !translation.isEmpty {
                    Text(translation)
                        .font(.system(size: emphasis.secondaryFontSize, weight: .regular, design: .rounded))
                        .foregroundStyle(LyricsDesignTokens.mutedText.opacity(emphasis.opacity * 0.92))
                        .lineSpacing(2)
                }
            }
            .padding(.vertical, emphasis.verticalPadding)
            .blur(radius: emphasis.blurRadius)
            .fixedSize(horizontal: false, vertical: true)
            .animation(.easeInOut(duration: 0.24), value: isActive)
            .animation(.easeInOut(duration: 0.24), value: visibleLayerCount)
        }
    }
}
