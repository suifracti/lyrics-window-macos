import SwiftUI

struct LyricLineView: View {
    let line: LyricLine
    let isActive: Bool
    let distance: Int
    let isSynchronized: Bool
    let preferences: DisplayPreferences

    private var emphasis: LyricEmphasis {
        LyricsDesignTokens.lyricEmphasis(
            isActive: isActive,
            distance: distance,
            isSynchronized: isSynchronized
        )
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
                        .font(.system(size: emphasis.primaryFontSize, weight: isActive ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(LyricsDesignTokens.primaryText.opacity(emphasis.opacity))
                        .lineSpacing(isActive ? 4 : 2)
                }

                if preferences.showTranslation, let translation = line.translationText, !translation.isEmpty {
                    Text(translation)
                        .font(.system(size: emphasis.secondaryFontSize + 1, weight: .regular, design: .rounded))
                        .foregroundStyle(LyricsDesignTokens.secondaryText.opacity(emphasis.opacity * 0.92))
                        .lineSpacing(2)
                }

                if preferences.showRomaji, let romaji = line.romajiText, !romaji.isEmpty {
                    Text(romaji)
                        .font(.system(size: emphasis.secondaryFontSize, weight: .regular, design: .rounded))
                        .foregroundStyle(LyricsDesignTokens.mutedText.opacity(emphasis.opacity))
                        .lineSpacing(2)
                }

                if preferences.showKana, let kana = line.kanaText, !kana.isEmpty {
                    Text(kana)
                        .font(.system(size: emphasis.secondaryFontSize, weight: .regular, design: .rounded))
                        .foregroundStyle(LyricsDesignTokens.mutedText.opacity(emphasis.opacity * 0.9))
                        .lineSpacing(2)
                }
            }
            .padding(.vertical, emphasis.verticalPadding)
            .blur(radius: emphasis.blurRadius)
            .animation(.easeInOut(duration: 0.22), value: isActive)
        }
    }
}
