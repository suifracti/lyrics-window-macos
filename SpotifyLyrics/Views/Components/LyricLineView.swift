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

    private var rubyFontSize: CGFloat {
        // Ruby stays at 50–60% of the base size, but follows the responsive
        // base size instead of being a fixed 16/18pt value.
        max(11, emphasis.primaryFontSize * 0.55)
    }

    private var rubyOpacity: Double {
        min(0.85, emphasis.opacity * 0.82)
    }

    private var auxiliaryTopSpacing: CGFloat { 7 }

    private var hasVisibleRomaji: Bool {
        preferences.showRomaji && !(line.romajiText ?? "").isEmpty
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
            VStack(alignment: .leading, spacing: 0) {
                if preferences.showOriginal, !line.originalText.isEmpty {
                    if preferences.showKana, let kana = line.kanaText, !kana.isEmpty {
                        RubyLineView(
                            originalText: line.originalText,
                            kanaText: kana,
                            tokens: line.rubyTokens,
                            baseFont: .system(
                                size: emphasis.primaryFontSize,
                                weight: fontWeight,
                                design: .rounded
                            ),
                            rubyFont: .system(
                                size: rubyFontSize,
                                weight: fontWeight,
                                design: .rounded
                            ),
                            baseColor: LyricsDesignTokens.primaryText.opacity(emphasis.opacity),
                            rubyColor: LyricsDesignTokens.secondaryText.opacity(rubyOpacity)
                        )
                    } else {
                        Text(line.originalText)
                            .font(.system(size: emphasis.primaryFontSize, weight: fontWeight, design: .rounded))
                            .foregroundStyle(LyricsDesignTokens.primaryText.opacity(emphasis.opacity))
                            .lineSpacing(isActive ? 3 : 2)
                    }
                } else if preferences.showKana, let kana = line.kanaText, !kana.isEmpty {
                    // If the user hides the base text, keep the kana layer
                    // useful as ordinary text rather than rendering detached
                    // ruby with no base to annotate.
                    Text(kana)
                        .font(.system(size: emphasis.secondaryFontSize, weight: fontWeight, design: .rounded))
                        .foregroundStyle(LyricsDesignTokens.secondaryText.opacity(rubyOpacity))
                        .lineSpacing(2)
                }

                if preferences.showRomaji, let romaji = line.romajiText, !romaji.isEmpty {
                    Text(romaji)
                        .font(.system(size: emphasis.secondaryFontSize, weight: .regular, design: .rounded))
                        .foregroundStyle(LyricsDesignTokens.mutedText.opacity(emphasis.opacity * 0.64))
                        .lineSpacing(2)
                        .padding(.top, auxiliaryTopSpacing)
                }

                if preferences.showTranslation, let translation = line.translationText, !translation.isEmpty {
                    Text(translation)
                        .font(.system(size: emphasis.secondaryFontSize, weight: .regular, design: .rounded))
                        .foregroundStyle(LyricsDesignTokens.mutedText.opacity(emphasis.opacity * 0.72))
                        .lineSpacing(2)
                        .padding(.top, hasVisibleRomaji ? 3 : auxiliaryTopSpacing)
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

/// A line-level ruby fallback that keeps the confirmed kana together with
/// the whole original line when no per-token mapping is available.
private struct RubyLineView: View {
    let originalText: String
    let kanaText: String
    let tokens: [LyricRubyToken]?
    let baseFont: Font
    let rubyFont: Font
    let baseColor: Color
    let rubyColor: Color

    private var displayTokens: [LyricRubyToken] {
        guard let tokens, !tokens.isEmpty else {
            return [
                LyricRubyToken(
                    id: 0,
                    surface: originalText,
                    ruby: kanaText
                )
            ]
        }
        return tokens
    }

    var body: some View {
        RubyTokenFlowLayout(horizontalSpacing: 0, verticalSpacing: 5) {
            ForEach(displayTokens) { token in
                RubyTokenBlock(
                    token: token,
                    baseFont: baseFont,
                    rubyFont: rubyFont,
                    baseColor: baseColor,
                    rubyColor: rubyColor
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(originalText)
    }
}

private struct RubyTokenBlock: View {
    let token: LyricRubyToken
    let baseFont: Font
    let rubyFont: Font
    let baseColor: Color
    let rubyColor: Color

    var body: some View {
        VStack(alignment: .center, spacing: 3) {
            if token.hasRuby, let ruby = token.ruby {
                Text(ruby)
                    .font(rubyFont)
                    .foregroundStyle(rubyColor)
                    .lineLimit(1)
                    // A long reading must overhang its base, not be squeezed.
                    .fixedSize(horizontal: true, vertical: false)
            }

            Text(token.surface)
                .font(baseFont)
                .foregroundStyle(baseColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// Wraps complete ruby/base word blocks without splitting a word in half.
/// The individual block is still a VStack (ruby above base); this layout only
/// adds a new row when the available width cannot fit the next block.
private struct RubyTokenFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposedWidth(proposal, subviews: subviews)
        let rows = makeRows(width: width, subviews: subviews)
        let contentWidth = proposal.width ?? rows.map(\.width).max() ?? 0
        let contentHeight = rows.reduce(0) { partial, row in
            partial + row.height
        } + CGFloat(max(0, rows.count - 1)) * verticalSpacing
        return CGSize(width: contentWidth, height: contentHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = makeRows(width: max(1, bounds.width), subviews: subviews)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let subview = subviews[index]
                let size = subview.sizeThatFits(.unspecified)
                subview.place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func proposedWidth(_ proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        if let width = proposal.width, width.isFinite, width > 0 {
            return width
        }
        return subviews.reduce(0) { partial, subview in
            partial + subview.sizeThatFits(.unspecified).width
        }
    }

    private func makeRows(width: CGFloat, subviews: Subviews) -> [Row] {
        guard !subviews.isEmpty else { return [] }
        let maxWidth = max(1, width)
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = current.indices.isEmpty
                ? size.width
                : current.width + horizontalSpacing + size.width

            if !current.indices.isEmpty, nextWidth > maxWidth {
                rows.append(current)
                current = Row()
            }

            current.indices.append(index)
            current.width = current.indices.count == 1
                ? size.width
                : current.width + horizontalSpacing + size.width
            current.height = max(current.height, size.height)
        }

        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
