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
                if preferences.kanaDisplayMode == .kanaReplacement,
                   let kana = line.kanaText,
                   !kana.isEmpty {
                    KanaReplacementLineView(
                        originalText: line.originalText,
                        kanaText: kana,
                        tokens: line.rubyTokens,
                        showsOriginalAnnotation: preferences.showOriginal && !line.originalText.isEmpty,
                        baseFont: .system(
                            size: emphasis.primaryFontSize,
                            weight: fontWeight,
                            design: .rounded
                        ),
                        annotationFont: .system(
                            size: rubyFontSize,
                            weight: fontWeight,
                            design: .rounded
                        ),
                        baseColor: LyricsDesignTokens.primaryText.opacity(emphasis.opacity),
                        annotationColor: LyricsDesignTokens.secondaryText.opacity(rubyOpacity)
                    )
                } else if preferences.showOriginal, !line.originalText.isEmpty {
                    if preferences.kanaDisplayMode == .independentLine {
                        Text(line.originalText)
                            .font(.system(size: emphasis.primaryFontSize, weight: fontWeight, design: .rounded))
                            .foregroundStyle(LyricsDesignTokens.primaryText.opacity(emphasis.opacity))
                            .lineSpacing(isActive ? 3 : 2)

                        if let kana = line.kanaText, !kana.isEmpty {
                            Text(kana)
                                .font(.system(size: emphasis.secondaryFontSize, weight: fontWeight, design: .rounded))
                                .foregroundStyle(LyricsDesignTokens.secondaryText.opacity(rubyOpacity))
                                .lineSpacing(2)
                                .padding(.top, 2)
                        }
                    } else if preferences.kanaDisplayMode == .inlineRuby,
                              let kana = line.kanaText,
                              !kana.isEmpty {
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
                } else if preferences.kanaDisplayMode != .hidden,
                          let kana = line.kanaText,
                          !kana.isEmpty {
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

/// Renders the kana as the primary line and keeps the original Kanji as a
/// small annotation above the corresponding kana span. This is a third,
/// independent presentation mode: it does not enable or disable either of
/// the other two modes, and it never mutates the stored lyric layers.
struct KanaReplacementLineView: View {
    let originalText: String
    let kanaText: String
    let tokens: [LyricRubyToken]?
    let showsOriginalAnnotation: Bool
    let baseFont: Font
    let annotationFont: Font
    let baseColor: Color
    let annotationColor: Color

    private var displayTokens: [LyricRubyToken] {
        guard let tokens, !tokens.isEmpty else {
            return [
                LyricRubyToken(
                    id: 0,
                    surface: originalText,
                    // Without a token-level confirmation there is no safe
                    // Han span to annotate. Keep the confirmed kana as the
                    // base text and fail closed on the original annotation.
                    ruby: nil,
                    kanaSurface: kanaText
                )
            ]
        }
        return tokens
    }

    private var displayTokenGroups: [[LyricRubyToken]] {
        rubyTokenGroups(displayTokens)
    }

    var body: some View {
        RubyTokenFlowLayout(horizontalSpacing: 0, verticalSpacing: 5) {
            ForEach(Array(displayTokenGroups.enumerated()), id: \.offset) { _, group in
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    ForEach(group) { token in
                        KanaReplacementTokenBlock(
                            token: token,
                            showsOriginalAnnotation: showsOriginalAnnotation,
                            baseFont: baseFont,
                            annotationFont: annotationFont,
                            baseColor: baseColor,
                            annotationColor: annotationColor
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(originalText)
    }
}

private struct KanaReplacementTokenBlock: View {
    let token: LyricRubyToken
    let showsOriginalAnnotation: Bool
    let baseFont: Font
    let annotationFont: Font
    let baseColor: Color
    let annotationColor: Color

    private var annotation: String? {
        guard showsOriginalAnnotation, token.hasRuby else { return nil }
        return token.surface
    }

    var body: some View {
        KanaReplacementTokenBlockLayout(annotationSpacing: 2) {
            if let annotation {
                Text(annotation)
                    .font(annotationFont)
                    .foregroundStyle(annotationColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Text(token.kanaReplacementText)
                .font(baseFont)
                .foregroundStyle(baseColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// Keeps the kana width authoritative and lets the smaller original Kanji
/// annotation overhang it horizontally above the kana. The base last baseline
/// is exported so kana-only and annotated blocks remain on one stable line.
private struct KanaReplacementTokenBlockLayout: Layout {
    let annotationSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let base = subviews.last else { return .zero }
        let baseSize = base.sizeThatFits(.unspecified)
        let annotationHeight = subviews.dropLast().first.map {
            $0.sizeThatFits(.unspecified).height
        } ?? 0
        let height = annotationHeight > 0
            ? baseSize.height + annotationSpacing + annotationHeight
            : baseSize.height
        return CGSize(width: baseSize.width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let base = subviews.last else { return }
        let baseSize = base.sizeThatFits(.unspecified)
        let annotation = subviews.dropLast().first
        let annotationSize = annotation?.sizeThatFits(.unspecified) ?? .zero
        let baseY = annotation == nil
            ? bounds.minY
            : bounds.minY + annotationSize.height + annotationSpacing

        if let annotation {
            annotation.place(
                at: CGPoint(
                    x: bounds.midX - annotationSize.width / 2,
                    y: bounds.minY
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: annotationSize.width, height: annotationSize.height)
            )
        }

        base.place(
            at: CGPoint(x: bounds.minX, y: baseY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: baseSize.width, height: baseSize.height)
        )
    }

    func explicitAlignment(
        of alignment: VerticalAlignment,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGFloat? {
        guard alignment == .lastTextBaseline, let base = subviews.last else {
            return nil
        }
        let baseSize = base.sizeThatFits(.unspecified)
        let dimensions = base.dimensions(
            in: ProposedViewSize(width: baseSize.width, height: baseSize.height)
        )
        let annotationHeight = subviews.dropLast().first.map {
            $0.sizeThatFits(.unspecified).height
        } ?? 0
        let baseOffset = annotationHeight > 0 ? annotationHeight + annotationSpacing : 0
        return baseOffset + dimensions[.lastTextBaseline]
    }
}

/// A line-level ruby fallback that keeps the confirmed kana together with
/// the whole original line when no per-token mapping is available.
struct RubyLineView: View {
    let originalText: String
    let kanaText: String
    let tokens: [LyricRubyToken]?
    let baseFont: Font
    let rubyFont: Font
    let baseColor: Color
    let rubyColor: Color
    /// Kept configurable so V3 can tighten the ruby cluster without
    /// changing the established V2/focus presentation defaults.
    var rubySpacing: CGFloat = 2
    var tokenVerticalSpacing: CGFloat = 5

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

    private var displayTokenGroups: [[LyricRubyToken]] {
        rubyTokenGroups(displayTokens)
    }

    var body: some View {
        RubyTokenFlowLayout(horizontalSpacing: 0, verticalSpacing: tokenVerticalSpacing) {
            ForEach(Array(displayTokenGroups.enumerated()), id: \.offset) { _, group in
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    ForEach(group) { token in
                        RubyTokenBlock(
                            token: token,
                            baseFont: baseFont,
                            rubyFont: rubyFont,
                            baseColor: baseColor,
                            rubyColor: rubyColor,
                            rubySpacing: rubySpacing
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(originalText)
    }
}

/// Builder IDs reserve the high digits for the morphology token and the low
/// digits for its surface runs. Grouping by that stable prefix prevents
/// `言`/`われ` or `思`/`い` from being wrapped onto different rows while
/// retaining the corrected per-span ruby mapping.
private func rubyTokenGroups(_ tokens: [LyricRubyToken]) -> [[LyricRubyToken]] {
    var groups: [[LyricRubyToken]] = []
    var currentKey: Int?

    for token in tokens {
        let key = token.id / 10_000
        if currentKey == key, !groups.isEmpty {
            groups[groups.count - 1].append(token)
        } else {
            groups.append([token])
            currentKey = key
        }
    }
    return groups
}

private struct RubyTokenBlock: View {
    let token: LyricRubyToken
    let baseFont: Font
    let rubyFont: Font
    let baseColor: Color
    let rubyColor: Color
    let rubySpacing: CGFloat

    var body: some View {
        RubyTokenBlockLayout(rubySpacing: rubySpacing) {
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

/// Places ruby above the base text while keeping the base width authoritative.
///
/// A normal `VStack` takes the widest child as its width. That makes a reading
/// such as `こころ` widen the layout box for the one-character base `心`, which
/// breaks the baseline rhythm of the surrounding kana. This layout lets ruby
/// overhang the base horizontally without pushing adjacent base characters
/// apart, and explicitly exports the base's last text baseline to its parent.
private struct RubyTokenBlockLayout: Layout {
    let rubySpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let base = subviews.last else { return .zero }
        let baseSize = baseSize(for: base)
        let rubyHeight = subviews.dropLast().first.map { readingSize(for: $0).height } ?? 0
        let height = rubyHeight > 0
            ? rubyHeight + rubySpacing + baseSize.height
            : baseSize.height
        return CGSize(width: baseSize.width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let base = subviews.last else { return }
        let baseSize = baseSize(for: base)
        let ruby = subviews.dropLast().first
        let rubyDimensions: CGSize = ruby.map { readingSize(for: $0) } ?? CGSize.zero
        let baseY = ruby == nil ? bounds.minY : bounds.minY + rubyDimensions.height + rubySpacing

        if let ruby {
            ruby.place(
                at: CGPoint(
                    x: bounds.midX - rubyDimensions.width / 2,
                    y: bounds.minY
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: rubyDimensions.width, height: rubyDimensions.height)
            )
        }

        base.place(
            at: CGPoint(x: bounds.minX, y: baseY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: baseSize.width, height: baseSize.height)
        )
    }

    func explicitAlignment(
        of alignment: VerticalAlignment,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGFloat? {
        guard alignment == .lastTextBaseline, let base = subviews.last else {
            return nil
        }

        let baseSize = baseSize(for: base)
        let baseDimensions = base.dimensions(
            in: ProposedViewSize(width: baseSize.width, height: baseSize.height)
        )
        let rubyHeight = subviews.dropLast().first.map { readingSize(for: $0).height } ?? 0
        let baseOffset = rubyHeight > 0 ? rubyHeight + rubySpacing : 0
        return baseOffset + baseDimensions[.lastTextBaseline]
    }

    private func baseSize(for subview: LayoutSubview) -> CGSize {
        subview.sizeThatFits(.unspecified)
    }

    private func readingSize(for subview: LayoutSubview) -> CGSize {
        subview.sizeThatFits(.unspecified)
    }
}

/// Wraps complete ruby/base word blocks without splitting a word in half.
/// Each block exports the base baseline, so kana-only tokens and ruby tokens
/// share one bottom reading line within a row.
private struct RubyTokenFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    private struct Item {
        let index: Int
        let size: CGSize
        let baseline: CGFloat
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0

        var baseline: CGFloat {
            items.map(\.baseline).max() ?? 0
        }

        var height: CGFloat {
            items.map { baseline - $0.baseline + $0.size.height }.max() ?? 0
        }
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
            for item in row.items {
                let subview = subviews[item.index]
                subview.place(
                    at: CGPoint(x: x, y: y + row.baseline - item.baseline),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + horizontalSpacing
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
            let item = measuredItem(index: index, subview: subviews[index])
            let nextWidth = current.items.isEmpty
                ? item.size.width
                : current.width + horizontalSpacing + item.size.width

            if !current.items.isEmpty, nextWidth > maxWidth {
                rows.append(current)
                current = Row()
            }

            current.items.append(item)
            current.width = current.items.count == 1
                ? item.size.width
                : current.width + horizontalSpacing + item.size.width
        }

        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }

    private func measuredItem(index: Int, subview: LayoutSubview) -> Item {
        let size = subview.sizeThatFits(.unspecified)
        let dimensions = subview.dimensions(in: .unspecified)
        let baseline = dimensions[.lastTextBaseline]
        return Item(
            index: index,
            size: size,
            baseline: baseline.isFinite && baseline >= 0 ? baseline : size.height
        )
    }
}
