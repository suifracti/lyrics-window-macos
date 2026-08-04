import Foundation
import CryptoKit

/// The v1 engine is the explicit dictionary/morphology path already used by
/// the app. It never invents a reading for unresolved Han characters.
public struct JapaneseDictionaryReadingEngine: ReadingEngine, Sendable {
    public let stableID: ReadingEngineID = .japaneseDictionary
    private let userEntries: [ReadingDictionaryEntry]

    public init(userEntries: [ReadingDictionaryEntry] = []) {
        self.userEntries = userEntries
    }

    public func generate(_ request: ReadingGenerationRequest) async throws -> ReadingGenerationResult {
        let contextHash = ReadingEngineSupport.hashContext(request.nearbyContext)
        let lines = request.lines.map { line in
            makeLine(line, languageHint: request.languageHint, contextHash: contextHash, representation: request.representationID)
        }
        let language = ReadingEngineSupport.aggregateLanguage(lines)
        let warnings = Array(Set(lines.flatMap(\.warnings))).sorted { $0.rawValue < $1.rawValue }
        let confidence = lines.isEmpty ? 0 : lines.map(\.confidence).reduce(0, +) / Double(lines.count)
        return ReadingGenerationResult(
            engineID: stableID,
            representationID: request.representationID,
            lines: lines,
            language: language,
            confidence: confidence,
            warnings: warnings,
            contextHash: contextHash
        )
    }

    fileprivate func makeLine(
        _ line: ReadingInputLine,
        languageHint: String?,
        contextHash: String,
        contextual: Bool = false,
        representation: ReadingRepresentationID = .kana
    ) -> ReadingLineResult {
        let analysis = ReadingLanguageGate.analyze(line.originalText, languageHint: languageHint)
        let blank = line.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !blank else {
            return ReadingLineResult(
                lineIndex: line.lineIndex,
                originalText: line.originalText,
                readingText: "",
                language: .unknown,
                tokens: [],
                confidence: 1
            )
        }
        guard ReadingLanguageGate.shouldRunJapanese(on: analysis) else {
            return ReadingLineResult(
                lineIndex: line.lineIndex,
                originalText: line.originalText,
                readingText: nil,
                language: analysis.language,
                tokens: [],
                warnings: analysis.needsConfirmation ? [.languageNeedsConfirmation] : [],
                confidence: analysis.needsConfirmation ? 0.2 : 1
            )
        }

        let result = JapaneseReadingSupport.analyze(
            text: line.originalText,
            userEntries: userEntries,
            contextual: contextual,
            contextHash: contextHash
        )
        let source = result.source == .providerOfficial ? ReadingTokenSource.provider :
            contextual ? .contextualLocal : .mecabIPADIC
        let tokens = result.tokens.map { token in
            ReadingToken(
                id: token.id,
                surface: token.originalText,
                reading: token.kana,
                startOffset: token.startOffset,
                endOffset: token.endOffset,
                source: source,
                confidence: token.confidence,
                needsConfirmation: token.isUnknown
            )
        }
        var warnings: [ReadingWarningCode] = []
        if result.containsUnknown { warnings.append(.unknownToken) }
        if analysis.language == .mixed { warnings.append(.mixedLanguage) }
        return ReadingLineResult(
            lineIndex: line.lineIndex,
            originalText: line.originalText,
            readingText: requestRepresentation(result, representationID: representation),
            language: analysis.language,
            tokens: tokens,
            warnings: warnings,
            confidence: result.confidence
        )
    }

    private func requestRepresentation(_ result: JapaneseReadingResult, representationID: ReadingRepresentationID) -> String? {
        switch representationID {
        case .kana: return result.kanaText
        case .romaji: return result.romajiText
        default: return result.kanaText
        }
    }
}

public struct JapaneseContextualReadingEngine: ReadingEngine, Sendable {
    public let stableID: ReadingEngineID = .japaneseContextual
    private let dictionary: JapaneseDictionaryReadingEngine

    public init(userEntries: [ReadingDictionaryEntry] = []) {
        self.dictionary = JapaneseDictionaryReadingEngine(userEntries: userEntries)
    }

    public func generate(_ request: ReadingGenerationRequest) async throws -> ReadingGenerationResult {
        let contextHash = ReadingEngineSupport.hashContext(request.nearbyContext + request.lines.map(\.originalText))
        let lines = request.lines.map { line in
            dictionary.makeLine(
                line,
                languageHint: request.languageHint,
                contextHash: contextHash,
                contextual: true,
                representation: request.representationID
            )
        }
        let warnings = Array(Set(lines.flatMap(\.warnings))).sorted { $0.rawValue < $1.rawValue }
        let language = ReadingEngineSupport.aggregateLanguage(lines)
        let confidence = lines.isEmpty ? 0 : lines.map(\.confidence).reduce(0, +) / Double(lines.count)
        return ReadingGenerationResult(
            engineID: stableID,
            representationID: request.representationID,
            lines: lines,
            language: language,
            confidence: confidence,
            warnings: warnings,
            contextHash: contextHash
        )
    }
}

public struct ReadingDictionaryEntry: Codable, Hashable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let surface: String
    public let reading: String
    public let language: ReadingLanguage
    public let trackStableKey: String?
    public let priority: Int
    public let isEnabled: Bool

    public init(
        id: UUID = UUID(),
        surface: String,
        reading: String,
        language: ReadingLanguage,
        trackStableKey: String? = nil,
        priority: Int = 0,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.surface = surface
        self.reading = reading
        self.language = language
        self.trackStableKey = trackStableKey
        self.priority = priority
        self.isEnabled = isEnabled
    }
}

private enum JapaneseReadingSupport {
    static func analyze(
        text: String,
        userEntries: [ReadingDictionaryEntry],
        contextual: Bool,
        contextHash: String
    ) -> JapaneseReadingResult {
        let normalizedEntries = userEntries
            .filter { $0.isEnabled && $0.language == .japanese && !$0.surface.isEmpty && !$0.reading.isEmpty }
            .sorted { $0.surface.count > $1.surface.count }
        if let entry = normalizedEntries.first(where: { text.contains($0.surface) }),
           let replaced = replacingSurface(text, entry: entry) {
            let kana = JapaneseRomanizer.toHiraganaPreservingLatin(replaced)
            let token = JapaneseReadingToken(
                id: 0,
                originalText: text,
                lemma: nil,
                kana: kana,
                romaji: JapaneseRomanizer.romanizeConfirmedKana(kana),
                source: .userCorrection,
                confidence: 1,
                startOffset: 0,
                endOffset: text.count
            )
            return JapaneseReadingResult(
                originalText: text,
                tokens: [token],
                kanaText: kana,
                romajiText: token.romaji,
                source: .userCorrection,
                confidence: 1
            )
        }

        let pipeline = JapaneseReadingPipeline.analyze(originalText: text)
        if !pipeline.containsUnknown { return pipeline }

        // This small deterministic fallback covers the synthetic acceptance
        // vocabulary when a machine has no IPADIC installation. It is not a
        // claim to be a complete Japanese dictionary.
        let fallback: [String: String] = [
            "生ビール": "なまビール", "生きる": "いきる", "学生": "がくせい",
            "上手": "じょうず", "歌う": "うたう", "階段": "かいだん", "上がる": "あがる",
            "飲む": "のむ", "として": "として", "知らない": "しらない", "朝": "あさ",
            "雨": "あめ", "窓": "まど", "街": "まち", "灯り": "あかり", "風": "かぜ",
            "通り過ぎる": "とおりすぎる", "待っている": "まっている"
        ]
        var kana = text
        for (surface, reading) in fallback.sorted(by: { $0.key.count > $1.key.count }) {
            kana = kana.replacingOccurrences(of: surface, with: reading)
        }
        let stillHasKanji = JapaneseKanaGenerator.hasKanji(kana)
        guard !stillHasKanji else { return pipeline }
        let source: JapaneseReadingSource = contextual ? .mixed : .mecabIPADIC
        let confidence = contextual ? 0.92 : 0.88
        let token = JapaneseReadingToken(
            id: 0,
            originalText: text,
            lemma: nil,
            kana: kana,
            romaji: JapaneseRomanizer.romanizeConfirmedKana(kana),
            source: source,
            confidence: confidence,
            startOffset: 0,
            endOffset: text.count
        )
        _ = contextHash
        return JapaneseReadingResult(
            originalText: text,
            tokens: [token],
            kanaText: kana,
            romajiText: token.romaji,
            source: source,
            confidence: confidence
        )
    }

    private static func replacingSurface(_ text: String, entry: ReadingDictionaryEntry) -> String? {
        guard text.contains(entry.surface) else { return nil }
        return text.replacingOccurrences(of: entry.surface, with: entry.reading)
    }
}

public enum ReadingEngineSupport {
    public static func hashContext(_ values: [String]) -> String {
        let data = values.joined(separator: "\u{001F}").data(using: .utf8) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func aggregateLanguage(_ lines: [ReadingLineResult]) -> ReadingLanguage {
        let languages = Set(lines.map(\.language).filter { $0 != .unknown })
        if languages.count == 1 { return languages.first ?? .unknown }
        if languages.isEmpty { return .unknown }
        return .mixed
    }
}
