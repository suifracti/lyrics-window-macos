import Foundation

/// Match-view normalization only. Never overwrites display/source lyrics.
public enum TranscriptNormalizer {
    public struct Operation: Equatable, Sendable, Codable {
        public let kind: String
        public let detail: String
    }

    public struct NormalizedSegment: Equatable, Sendable {
        public let sourceIndex: Int
        public let originalText: String
        public let matchText: String
        public let startTime: TimeInterval
        public let endTime: TimeInterval
        public let asrConfidence: Double?
        public let operations: [Operation]
    }

    public struct Result: Equatable, Sendable {
        public let language: String
        public let engineID: String
        public let segments: [NormalizedSegment]
        public let operations: [Operation]
    }

    /// Build a language-aware match view. Original text is preserved separately.
    public static func normalize(
        engineResult: SpeechEngineResult,
        languageHint: String?
    ) -> Result {
        let language = primaryLanguage(
            languageHint ?? engineResult.language
        )
        var ops: [Operation] = []
        var segs: [NormalizedSegment] = []
        for seg in engineResult.segments {
            let original = seg.text
            let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                ops.append(Operation(kind: "drop_empty", detail: "index=\(seg.index)"))
                continue
            }
            var localOps: [Operation] = []
            let match = matchView(trimmed, language: language, operations: &localOps)
            segs.append(
                NormalizedSegment(
                    sourceIndex: seg.index,
                    originalText: original,
                    matchText: match,
                    startTime: seg.startTime,
                    endTime: seg.endTime,
                    asrConfidence: seg.confidence,
                    operations: localOps
                )
            )
        }
        ops.append(Operation(kind: "language", detail: language))
        return Result(
            language: language,
            engineID: engineResult.engineID.rawValue,
            segments: segs,
            operations: ops
        )
    }

    public static func matchView(_ text: String, language: String) -> String {
        var ops: [Operation] = []
        return matchView(text, language: language, operations: &ops)
    }

    public static func primaryLanguage(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasPrefix("zh") || t.contains("chinese") || t == "cmn" { return "zh" }
        if t.hasPrefix("en") || t.contains("english") { return "en" }
        if t.hasPrefix("ja") || t.contains("japan") { return "ja" }
        // Heuristic from script
        let hasKana = textHasKana(t)
        let hasHan = textHasHan(t)
        let hasLatin = t.unicodeScalars.contains { CharacterSet.letters.contains($0) && $0.value < 0x80 }
        if hasKana { return "ja" }
        if hasHan && !hasKana { return "zh" }
        if hasLatin { return "en" }
        return "ja"
    }

    private static func matchView(
        _ text: String,
        language: String,
        operations: inout [Operation]
    ) -> String {
        var s = text
        let before = s
        // Fullwidth → halfwidth ASCII digits/letters/punct where applicable
        s = s.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? s
        if s != before { operations.append(Operation(kind: "fullwidth_to_halfwidth", detail: "")) }

        switch language {
        case "ja":
            // Katakana → hiragana for match view (via existing romanizer path)
            let kana = JapaneseRomanizer.toHiraganaPreservingLatin(s)
            if kana != s {
                operations.append(Operation(kind: "kana_match_view", detail: "katakana_to_hiragana"))
            }
            s = kana.lowercased()
            s = stripMatchPunctuation(s, language: "ja")
            s = collapseWhitespace(s)
            // Drop spaces entirely for Japanese match (lyrics often space-free)
            s = s.replacingOccurrences(of: " ", with: "")
        case "zh":
            s = s.lowercased()
            s = stripMatchPunctuation(s, language: "zh")
            s = collapseWhitespace(s)
            s = s.replacingOccurrences(of: " ", with: "")
            // Note: traditional/simplified folding is best-effort identity here
            // (no bundled conversion table). Match still benefits from punct strip.
            operations.append(Operation(kind: "zh_match_view", detail: "punct_space_fold"))
        default: // en
            s = s.lowercased()
            s = expandEnglishContractions(s, operations: &operations)
            s = stripMatchPunctuation(s, language: "en")
            s = collapseWhitespace(s)
        }
        return s
    }

    private static func stripMatchPunctuation(_ text: String, language: String) -> String {
        let punct: CharacterSet = {
            var set = CharacterSet.punctuationCharacters
            set.formUnion(.symbols)
            // Keep apostrophe handling for English separately
            return set
        }()
        return String(text.unicodeScalars.filter { !punct.contains($0) })
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func expandEnglishContractions(_ text: String, operations: inout [Operation]) -> String {
        var s = text
        let pairs = [
            ("won't", "will not"), ("can't", "cannot"), ("n't", " not"),
            ("'re", " are"), ("'ve", " have"), ("'ll", " will"),
            ("'d", " would"), ("'m", " am")
        ]
        for (a, b) in pairs {
            if s.contains(a) {
                s = s.replacingOccurrences(of: a, with: b)
                operations.append(Operation(kind: "en_contraction", detail: a))
            }
        }
        return s
    }

    private static func textHasKana(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x3040...0x30FF).contains($0.value) || (0x31F0...0x31FF).contains($0.value)
        }
    }

    private static func textHasHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }
}
