import SwiftUI

struct LyricLineView: View {
    let line: LyricLine
    let isActive: Bool
    let distance: Int
    let isSynchronized: Bool
    let preferences: DisplayPreferences
    let availableWidth: CGFloat
    let visibleLayerCount: Int
    let language: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        line: LyricLine,
        isActive: Bool,
        distance: Int,
        isSynchronized: Bool,
        preferences: DisplayPreferences,
        availableWidth: CGFloat = LyricsDesignTokens.defaultMainWindowSize.width,
        visibleLayerCount: Int = 1,
        language: String? = nil
    ) {
        self.line = line
        self.isActive = isActive
        self.distance = distance
        self.isSynchronized = isSynchronized
        self.preferences = preferences
        self.availableWidth = availableWidth
        self.visibleLayerCount = visibleLayerCount
        self.language = language
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

    private var transitionStyle: LyricsTransitionStyle {
        LyricsTransitionPolicy.activeStyle
    }

    private var layoutSignature: LyricsLayoutSignature {
        LyricsTransitionPolicy.signature(
            line: line,
            preferences: preferences,
            availableWidth: availableWidth,
            visibleLayerCount: visibleLayerCount,
            isSynchronized: isSynchronized,
            distance: distance
        )
    }

    private var transitionAnimation: Animation? {
        LyricsTransitionPolicy.animation(
            style: transitionStyle,
            reduceMotion: reduceMotion
        )
    }

    private var fontWeight: Font.Weight {
        if isActive { return .bold }
        if distance == 1 { return .semibold }
        return .medium
    }

    private var rubyFontSize: CGFloat {
        // Ruby stays at 50–60% of the base size, but follows the responsive
        // base size instead of being a fixed 16/18pt value.
        max(11, emphasis.primaryFontSize * 0.55 * preferences.rubyFontSize / 10)
    }

    private var primaryFontSize: CGFloat {
        emphasis.primaryFontSize * max(0.7, preferences.fontSize / 18)
    }

    private var secondaryFontSize: CGFloat {
        emphasis.secondaryFontSize * max(0.7, preferences.assistantFontSize / 14)
    }

    private var effectiveOpacity: Double {
        guard !isActive else { return emphasis.opacity }
        return min(1, emphasis.opacity * max(0.15, preferences.opacity / 0.85))
    }

    private var rubyOpacity: Double {
        isActive ? min(0.95, effectiveOpacity * 0.90) : min(0.85, effectiveOpacity * 0.82)
    }

    private var auxiliaryTopSpacing: CGFloat { 7 }

    private var shouldShowAuxiliary: Bool {
        !isSynchronized || !preferences.hideDistantAuxiliary || distance <= 1
    }

    private var displayKanaText: String? {
        guard LyricsLanguageGate.allowsJapaneseReadings(language: language, text: line.originalText) else {
            return nil
        }
        return line.kanaText.map(JapaneseRomanizer.displayKana)
    }

    private var effectiveOriginalText: String {
        line.readingSurfaceText ?? line.originalText
    }

    private var isPinyinProjection: Bool {
        guard let representation = line.readingRepresentationID else { return false }
        return representation.hasPrefix("readingRepresentation.pinyin")
    }

    /// A few older/provider payloads accidentally put the confirmed kana in
    /// `romajiText` as well.  Rendering both layers makes the independent-line
    /// mode look duplicated, so fail closed when the two display strings are
    /// the same after katakana-to-hiragana normalization.
    private var distinctRomaji: String? {
        if isPinyinProjection {
            guard settingsShowPinyin, let pinyin = line.romajiText,
                  !pinyin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return pinyin
        }
        guard preferences.showRomaji,
              LyricsLanguageGate.allowsJapaneseReadings(language: language, text: line.originalText),
              let romaji = line.romajiText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !romaji.isEmpty else {
            return nil
        }

        if let kana = displayKanaText,
           !kana.isEmpty,
           normalizedDisplayText(romaji) == normalizedDisplayText(kana) {
            return nil
        }
        return romaji
    }

    private var hasVisibleRomaji: Bool {
        distinctRomaji != nil
    }

    private var hasVisibleContent: Bool {
        (preferences.showOriginal && !effectiveOriginalText.isEmpty)
            || (preferences.showTranslation && !(line.translationText ?? "").isEmpty)
            || distinctRomaji != nil
            || (preferences.showKana && displayKanaText != nil)
    }

    @ViewBuilder
    var body: some View {
        if hasVisibleContent {
            VStack(alignment: .leading, spacing: 0) {
                if preferences.kanaDisplayMode == .kanaReplacement,
                   LyricsLanguageGate.allowsJapaneseReadings(language: language, text: line.originalText),
                   let kana = displayKanaText,
                   !kana.isEmpty {
                    KanaReplacementLineView(
                        originalText: line.originalText,
                        kanaText: kana,
                        tokens: line.rubyTokens,
                        showsOriginalAnnotation: preferences.showOriginal
                            && !line.originalText.isEmpty
                            && shouldShowAuxiliary,
                        baseFont: .system(
                            size: primaryFontSize,
                            weight: fontWeight,
                            design: .rounded
                        ),
                        annotationFont: .system(
                            size: rubyFontSize,
                            weight: fontWeight,
                            design: .rounded
                        ),
                        baseColor: LyricsDesignTokens.primaryText.opacity(effectiveOpacity),
                        annotationColor: LyricsDesignTokens.secondaryText.opacity(rubyOpacity)
                    )
                } else if preferences.showOriginal, !line.originalText.isEmpty {
                    if preferences.kanaDisplayMode == .independentLine {
                        Text(effectiveOriginalText)
                            .font(.system(size: primaryFontSize, weight: fontWeight, design: .rounded))
                            .foregroundStyle(LyricsDesignTokens.primaryText.opacity(effectiveOpacity))
                            .lineSpacing(isActive ? 3 : 2)

                        if shouldShowAuxiliary, let kana = displayKanaText, !kana.isEmpty {
                            Text(kana)
                                .font(.system(size: secondaryFontSize, weight: fontWeight, design: .rounded))
                                .foregroundStyle(LyricsDesignTokens.secondaryText.opacity(rubyOpacity))
                                .lineSpacing(2)
                                .padding(.top, 2)
                                .transition(.opacity)
                        }
                    } else if preferences.kanaDisplayMode == .inlineRuby,
                              LyricsLanguageGate.allowsJapaneseReadings(language: language, text: line.originalText),
                              shouldShowAuxiliary,
                              let kana = displayKanaText,
                              !kana.isEmpty {
                        RubyLineView(
                            originalText: line.originalText,
                            kanaText: kana,
                            tokens: line.rubyTokens,
                            baseFont: .system(
                                size: primaryFontSize,
                                weight: fontWeight,
                                design: .rounded
                            ),
                            rubyFont: .system(
                                size: rubyFontSize,
                                weight: fontWeight,
                                design: .rounded
                            ),
                            baseColor: LyricsDesignTokens.primaryText.opacity(effectiveOpacity),
                            rubyColor: LyricsDesignTokens.secondaryText.opacity(rubyOpacity)
                        )
                    } else {
                        Text(effectiveOriginalText)
                                .font(.system(size: primaryFontSize, weight: fontWeight, design: .rounded))
                            .foregroundStyle(LyricsDesignTokens.primaryText.opacity(effectiveOpacity))
                            .lineSpacing(isActive ? 3 : 2)
                    }
                } else if preferences.kanaDisplayMode != .hidden,
                          LyricsLanguageGate.allowsJapaneseReadings(language: language, text: line.originalText),
                          let kana = displayKanaText,
                          !kana.isEmpty {
                    // If the user hides the base text, keep the kana layer
                    // useful as ordinary text rather than rendering detached
                    // ruby with no base to annotate.
                    Text(kana)
                        .font(.system(size: secondaryFontSize, weight: fontWeight, design: .rounded))
                        .foregroundStyle(LyricsDesignTokens.secondaryText.opacity(rubyOpacity))
                        .lineSpacing(2)
                        .transition(.opacity)
                }

                if let romaji = distinctRomaji {
                    Text(romaji)
                        .font(.system(size: secondaryFontSize, weight: .regular, design: .rounded))
                        .foregroundStyle(LyricsDesignTokens.mutedText.opacity(effectiveOpacity * 0.64))
                        .lineSpacing(2)
                        .padding(.top, auxiliaryTopSpacing)
                        .transition(.opacity)
                }

                if preferences.showTranslation, let translation = line.translationText, !translation.isEmpty {
                    Text(translation)
                        .font(.system(size: secondaryFontSize, weight: .regular, design: .rounded))
                        .foregroundStyle(LyricsDesignTokens.mutedText.opacity(effectiveOpacity * 0.72))
                        .lineSpacing(2)
                        .padding(.top, hasVisibleRomaji ? 3 : auxiliaryTopSpacing)
                        .transition(.opacity)
                }
            }
            .padding(.vertical, emphasis.verticalPadding)
            // Reduce Motion removes blur interpolation entirely.  The row
            // still receives the short opacity/layout transition below.
            .blur(radius: reduceMotion ? 0 : emphasis.blurRadius)
            .fixedSize(horizontal: false, vertical: true)
            .animation(transitionAnimation, value: isActive)
            .animation(transitionAnimation, value: layoutSignature)
        }
    }

    private func normalizedDisplayText(_ text: String) -> String {
        JapaneseRomanizer.displayKana(text)
            .split(whereSeparator: { $0.isWhitespace })
            .joined()
    }

    private var settingsShowPinyin: Bool {
        // Pinyin is a separate language layer, but the row remains reusable in
        // the existing display pipeline. The shared display preference is
        // intentionally optional for older fixtures.
        preferences.showPinyin
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
    /// Optional readable measure supplied by V3. Legacy callers keep the
    /// intrinsic-width behavior, while the main window can force the flow
    /// layout to reflow before a narrow resize clips the line.
    var maxWidth: CGFloat? = nil

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
        RubyTokenFlowLayout(horizontalSpacing: 0, verticalSpacing: 5, maxWidth: maxWidth) {
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
        .frame(maxWidth: maxWidth ?? .infinity, alignment: .leading)
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
        guard showsOriginalAnnotation, token.hasDisplayRuby else { return nil }
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

            Text(JapaneseRomanizer.displayKana(token.kanaReplacementText))
                .font(baseFont)
                .foregroundStyle(baseColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// Measures the replacement text and its original annotation together so a
/// long annotation cannot extend outside the token's layout box. The base is
/// centered inside that measured box and its last baseline is exported so
/// kana-only and annotated blocks remain on one stable line.
private struct KanaReplacementTokenBlockLayout: Layout {
    let annotationSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let base = subviews.last else { return .zero }
        let baseSize = base.sizeThatFits(.unspecified)
        let annotationSize = subviews.dropLast().first?.sizeThatFits(.unspecified) ?? .zero
        let contentWidth = max(baseSize.width, annotationSize.width)
        let annotationHeight = annotationSize.height
        let height = annotationHeight > 0
            ? baseSize.height + annotationSpacing + annotationHeight
            : baseSize.height
        return CGSize(width: contentWidth, height: height)
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
        let contentWidth = max(baseSize.width, annotationSize.width)
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

        let baseX = bounds.minX + max(0, (contentWidth - baseSize.width) / 2)
        base.place(
            at: CGPoint(x: baseX, y: baseY),
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
    /// Optional readable measure supplied by V3. The token flow remains
    /// intrinsic for legacy/focus callers when this is nil.
    var maxWidth: CGFloat? = nil

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
        RubyTokenFlowLayout(horizontalSpacing: 0, verticalSpacing: tokenVerticalSpacing, maxWidth: maxWidth) {
            ForEach(Array(displayTokenGroups.enumerated()), id: \.offset) { _, group in
                let groupEdgeReserve: CGFloat = group.count > 1
                    && group.filter(\.hasRuby).count == 1 ? 5 : 0
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    ForEach(group) { token in
                        RubyTokenBlock(
                            token: token,
                            baseFont: baseFont,
                            rubyFont: rubyFont,
                            baseColor: baseColor,
                            rubyColor: rubyColor,
                            rubySpacing: rubySpacing,
                            annotationOverhang: token.hasRuby ? groupEdgeReserve : 0
                        )
                    }
                }
                // The reserved outer edges exactly contain the visual
                // overhang borrowed inside a kanji + okurigana group. This
                // keeps the baseline text attached without letting ruby
                // collide with the neighbouring morphology group.
                .padding(.horizontal, groupEdgeReserve)
            }
        }
        .frame(maxWidth: maxWidth ?? .infinity, alignment: .leading)
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
    let annotationOverhang: CGFloat

    private let katakanaAnnotationTracking: CGFloat = 0.35

    private var isKatakanaAnnotation: Bool {
        !token.hasRuby && token.surface.unicodeScalars.contains { scalar in
            (0x30A1...0x30FA).contains(scalar.value)
        }
    }

    var body: some View {
        RubyTokenBlockLayout(
            rubySpacing: rubySpacing,
            annotationOverhang: annotationOverhang
        ) {
            if let ruby = token.displayRubyText {
                Text(ruby)
                    .font(rubyFont)
                    .tracking(isKatakanaAnnotation ? katakanaAnnotationTracking : 0)
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

/// Returns the reading shown above a token without changing the stored
/// original/kana layers.  Kanji uses the confirmed provider/morphology ruby;
/// full-width katakana gets a small hiragana annotation so it is readable in
/// the same inline-Ruby mode.  Plain hiragana, Latin, digits and punctuation
/// do not receive a redundant annotation.
extension LyricRubyToken {
    var displayRubyText: String? {
        if hasRuby, let ruby {
            return JapaneseRomanizer.displayKana(ruby)
        }

        guard surface.unicodeScalars.contains(where: { scalar in
            (0x30A1...0x30FA).contains(scalar.value)
        }) else {
            return nil
        }

        let reading = JapaneseRomanizer.displayKana(kanaSurface ?? surface)
        guard !reading.isEmpty, reading != surface else { return nil }
        return reading
    }

    var hasDisplayRuby: Bool {
        displayRubyText != nil
    }
}

/// Places ruby above the base text and measures the wider child as part of the
/// token box. A reading such as `こころ` therefore remains fully visible and
/// is centered over the one-character base `心`, while the base's last text
/// baseline is explicitly exported to its parent.
private struct RubyTokenBlockLayout: Layout {
    let rubySpacing: CGFloat
    /// Lets a long kanji reading extend a few points beyond its base advance.
    /// This keeps visible okurigana attached to the kanji while retaining
    /// enough width to prevent adjacent annotations from colliding.
    let annotationOverhang: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let base = subviews.last else { return .zero }
        let baseSize = baseSize(for: base)
        let rubySize = subviews.dropLast().first.map { readingSize(for: $0) } ?? .zero
        let contentWidth = max(
            baseSize.width,
            rubySize.width - max(0, annotationOverhang * 2)
        )
        let rubyHeight = rubySize.height
        let height = rubyHeight > 0
            ? rubyHeight + rubySpacing + baseSize.height
            : baseSize.height
        return CGSize(width: contentWidth, height: height)
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
        let contentWidth = max(
            baseSize.width,
            rubyDimensions.width - max(0, annotationOverhang * 2)
        )
        let baseY = ruby == nil ? bounds.minY : bounds.minY + rubyDimensions.height + rubySpacing

        if let ruby {
            ruby.place(
                at: CGPoint(
                    x: bounds.minX + contentWidth / 2 - rubyDimensions.width / 2,
                    y: bounds.minY
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: rubyDimensions.width, height: rubyDimensions.height)
            )
        }

        let baseX = bounds.minX + max(0, (contentWidth - baseSize.width) / 2)
        base.place(
            at: CGPoint(x: baseX, y: baseY),
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
    let maxWidth: CGFloat?

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
        let contentWidth = width > 0 ? width : rows.map(\.width).max() ?? 0
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
        let proposalWidth = proposal.width.flatMap { width in
            width.isFinite && width > 0 ? width : nil
        }
        let explicitWidth = maxWidth.flatMap { width in
            width.isFinite && width > 0 ? width : nil
        }
        if let proposalWidth, let explicitWidth {
            return min(proposalWidth, explicitWidth)
        }
        if let proposalWidth {
            return proposalWidth
        }
        if let explicitWidth {
            return explicitWidth
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
