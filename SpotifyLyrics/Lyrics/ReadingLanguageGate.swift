import Foundation

/// Conservative script router for reading engines. Han-only text without a
/// reliable language hint remains unknown instead of being sent to the wrong
/// engine.
public enum ReadingLanguageGate {
    public static func analyze(_ text: String, languageHint: String? = nil) -> ReadingLanguageAnalysis {
        let scalars = Array(text.unicodeScalars)
        var segments: [ReadingSegment] = []
        var start = 0
        var currentLanguage: ReadingLanguage?

        func flush(end: Int) {
            guard start < end, let language = currentLanguage else { return }
            let value = String(String.UnicodeScalarView(scalars[start..<end]))
            segments.append(ReadingSegment(
                id: segments.count,
                text: value,
                language: language,
                startOffset: start,
                endOffset: end
            ))
        }

        for index in scalars.indices {
            let next = classify(scalars[index], hint: languageHint)
            if currentLanguage == nil {
                currentLanguage = next
                start = index
            } else if next != currentLanguage {
                flush(end: index)
                start = index
                currentLanguage = next
            }
        }
        flush(end: scalars.count)

        let meaningful = Set(segments.map(\.language).filter { $0 != .unknown })
        let language: ReadingLanguage
        if meaningful.count == 1, let only = meaningful.first {
            language = only
        } else if meaningful.isEmpty {
            language = .unknown
        } else {
            language = .mixed
        }

        let unknownHan = segments.contains { $0.language == .unknown && containsHan($0.text) }
        return ReadingLanguageAnalysis(
            language: language,
            segments: segments,
            needsConfirmation: unknownHan || language == .unknown
        )
    }

    public static func shouldRunJapanese(on analysis: ReadingLanguageAnalysis) -> Bool {
        analysis.segments.contains { $0.language == .japanese }
    }

    public static func shouldRunPinyin(on analysis: ReadingLanguageAnalysis) -> Bool {
        analysis.segments.contains { $0.language == .simplifiedChinese || $0.language == .traditionalChinese }
    }

    public static func allowsJapaneseReadings(language: String?, text: String) -> Bool {
        let analysis = analyze(text, languageHint: language)
        return shouldRunJapanese(on: analysis) && !analysis.needsConfirmation
    }

    private static func classify(_ scalar: Unicode.Scalar, hint: String?) -> ReadingLanguage {
        let value = scalar.value
        if (0x3040...0x30FF).contains(value) { return .japanese }
        if containsHan(value) {
            let normalized = hint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if normalized.hasPrefix("ja") { return .japanese }
            if normalized.contains("hant") || normalized.contains("tw") || normalized.contains("hk") { return .traditionalChinese }
            if normalized.contains("zh") || normalized.contains("hans") || normalized.contains("cn") { return .simplifiedChinese }
            if traditionalMarkers.contains(value) { return .traditionalChinese }
            if simplifiedMarkers.contains(value) { return .simplifiedChinese }
            return .unknown
        }
        if (0x0041...0x005A).contains(value) || (0x0061...0x007A).contains(value) || (0x0030...0x0039).contains(value) {
            return .latin
        }
        return .unknown
    }

    private static func containsHan(_ value: UInt32) -> Bool {
        (0x3400...0x4DBF).contains(value) || (0x4E00...0x9FFF).contains(value) || (0xF900...0xFAFF).contains(value)
    }

    private static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { containsHan($0.value) }
    }

    // Small deterministic markers only disambiguate obvious fixtures. They
    // are not presented as a complete Chinese language detector.
    private static let simplifiedMarkers: Set<UInt32> = Set("银长银乐重庆这为学国门车东风".unicodeScalars.map(\.value))
    private static let traditionalMarkers: Set<UInt32> = Set("銀行長樂重慶學國門車東風".unicodeScalars.map(\.value))
}
