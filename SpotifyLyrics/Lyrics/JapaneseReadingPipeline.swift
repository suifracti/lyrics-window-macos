import Foundation

/// Where a per-token reading came from.
public enum JapaneseReadingSource: String, Codable, Sendable, Equatable {
    case providerOfficial
    case userCorrection
    case mecabIPADIC
    case literalPreserved
    case unknown
    case mixed
}

/// One morphology token emitted by the local Japanese analyzer.
public struct JapaneseMorphologyToken: Equatable, Sendable {
    public let originalText: String
    public let readingKatakana: String?
    public let lemma: String?
    public let partOfSpeech: String?
    public let conjugationType: String?
    public let conjugationForm: String?

    public init(
        originalText: String,
        readingKatakana: String?,
        lemma: String?,
        partOfSpeech: String?,
        conjugationType: String? = nil,
        conjugationForm: String? = nil
    ) {
        self.originalText = originalText
        self.readingKatakana = readingKatakana
        self.lemma = lemma
        self.partOfSpeech = partOfSpeech
        self.conjugationType = conjugationType
        self.conjugationForm = conjugationForm
    }
}

public enum JapaneseMorphologyError: Error, LocalizedError, Sendable, Equatable {
    case executableUnavailable
    case processFailed(String)
    case timedOut
    case malformedOutput

    public var errorDescription: String? {
        switch self {
        case .executableUnavailable:
            return "MeCab executable unavailable"
        case .processFailed(let message):
            return "MeCab failed: \(message)"
        case .timedOut:
            return "MeCab timed out"
        case .malformedOutput:
            return "MeCab returned malformed output"
        }
    }
}

/// Abstraction around morphology so the reading pipeline can be tested with
/// deterministic fixtures without making SwiftUI or alignment depend on a
/// concrete process implementation.
public protocol JapaneseMorphologyEngine: Sendable {
    func tokenize(_ text: String) throws -> [JapaneseMorphologyToken]
}

/// Real local Japanese morphology/dictionary reader.
///
/// The app invokes the installed MeCab binary with its configured IPADIC
/// dictionary. It does not depend on a project-root resource at runtime. If
/// MeCab cannot resolve a Han token, the pipeline returns `unknown` instead of
/// falling back to a single-character or Chinese reading.
public struct JapaneseMeCabEngine: JapaneseMorphologyEngine, Sendable {
    public let executableURL: URL?
    public let timeout: TimeInterval

    public init(executableURL: URL? = nil, timeout: TimeInterval = 2.0) {
        self.executableURL = executableURL
        self.timeout = timeout
    }

    public func tokenize(_ text: String) throws -> [JapaneseMorphologyToken] {
        guard !text.isEmpty else { return [] }
        guard let executableURL = executableURL ?? Self.resolveExecutable() else {
            throw JapaneseMorphologyError.executableUnavailable
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["-Ochasen"]

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            throw JapaneseMorphologyError.processFailed(error.localizedDescription)
        }

        guard let data = (text + "\n").data(using: .utf8) else {
            process.terminate()
            throw JapaneseMorphologyError.processFailed("input is not UTF-8")
        }
        input.fileHandleForWriting.write(data)
        input.fileHandleForWriting.closeFile()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                throw JapaneseMorphologyError.timedOut
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "status \(process.terminationStatus)"
            throw JapaneseMorphologyError.processFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let textOutput = String(data: outputData, encoding: .utf8) else {
            throw JapaneseMorphologyError.malformedOutput
        }

        let parsedTokens = Self.parseOchaSen(textOutput)
        guard !parsedTokens.isEmpty else {
            throw JapaneseMorphologyError.malformedOutput
        }
        return Self.restoreIgnoredGaps(parsedTokens, in: text)
    }

    public static func resolveExecutable() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        if let configured = environment["SPOTIFYLYRICS_MECAB_PATH"], !configured.isEmpty {
            candidates.append(configured)
        }
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/mecab",
            "/usr/local/bin/mecab",
            "/usr/bin/mecab"
        ])

        let fileManager = FileManager.default
        for path in candidates {
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// Parses MeCab's stable `-Ochasen` tabular output.
    public static func parseOchaSen(_ output: String) -> [JapaneseMorphologyToken] {
        output.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, line != "EOS" else { return nil }
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count >= 4 else { return nil }

            func optionalColumn(_ index: Int) -> String? {
                guard columns.indices.contains(index) else { return nil }
                let value = columns[index]
                return value.isEmpty || value == "*" ? nil : value
            }

            return JapaneseMorphologyToken(
                originalText: columns[0],
                readingKatakana: optionalColumn(1),
                lemma: optionalColumn(2),
                partOfSpeech: optionalColumn(3),
                conjugationType: optionalColumn(4),
                conjugationForm: optionalColumn(5)
            )
        }
    }

    /// MeCab ignores some whitespace while tokenizing. Reinsert those spans so
    /// the reading result can prove that every original character survived.
    private static func restoreIgnoredGaps(
        _ tokens: [JapaneseMorphologyToken],
        in originalText: String
    ) -> [JapaneseMorphologyToken] {
        var result: [JapaneseMorphologyToken] = []
        var cursor = originalText.startIndex

        for token in tokens {
            guard !token.originalText.isEmpty,
                  let range = originalText.range(of: token.originalText, range: cursor..<originalText.endIndex) else {
                return tokens
            }
            if range.lowerBound > cursor {
                let gap = String(originalText[cursor..<range.lowerBound])
                result.append(JapaneseMorphologyToken(
                    originalText: gap,
                    readingKatakana: gap,
                    lemma: gap,
                    partOfSpeech: "記号-空白"
                ))
            }
            result.append(token)
            cursor = range.upperBound
        }

        if cursor < originalText.endIndex {
            let gap = String(originalText[cursor..<originalText.endIndex])
            result.append(JapaneseMorphologyToken(
                originalText: gap,
                readingKatakana: gap,
                lemma: gap,
                partOfSpeech: "記号-空白"
            ))
        }
        return result
    }
}

/// A confirmed reading for one morphology token.
public struct JapaneseReadingToken: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: Int
    public let originalText: String
    public let lemma: String?
    public let kana: String?
    public let romaji: String?
    public let source: JapaneseReadingSource
    public let confidence: Double
    public let partOfSpeech: String?
    public let startOffset: Int
    public let endOffset: Int

    public var isUnknown: Bool { source == .unknown || kana == nil }

    public init(
        id: Int,
        originalText: String,
        lemma: String?,
        kana: String?,
        romaji: String?,
        source: JapaneseReadingSource,
        confidence: Double,
        partOfSpeech: String? = nil,
        startOffset: Int = 0,
        endOffset: Int = 0
    ) {
        self.id = id
        self.originalText = originalText
        self.lemma = lemma
        self.kana = kana
        self.romaji = romaji
        self.source = source
        self.confidence = confidence
        self.partOfSpeech = partOfSpeech
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}

public struct JapaneseReadingResult: Equatable, Sendable {
    public let originalText: String
    public let tokens: [JapaneseReadingToken]
    public let kanaText: String?
    public let romajiText: String?
    public let source: JapaneseReadingSource
    public let confidence: Double

    public var containsUnknown: Bool {
        tokens.contains(where: \.isUnknown)
    }

    /// Only fully resolved readings may be handed to a future alignment gate.
    /// The current alignment feature remains experimental and does not consume
    /// this value automatically; this property prevents accidental use of a
    /// partial/guessed reading if that path is revisited.
    public var isSafeForAlignment: Bool {
        !containsUnknown && confidence >= 0.90
    }

    public init(
        originalText: String,
        tokens: [JapaneseReadingToken],
        kanaText: String?,
        romajiText: String?,
        source: JapaneseReadingSource,
        confidence: Double
    ) {
        self.originalText = originalText
        self.tokens = tokens
        self.kanaText = kanaText
        self.romajiText = romajiText
        self.source = source
        self.confidence = confidence
    }
}

/// Morphology-first Japanese reading pipeline.
public enum JapaneseReadingPipeline {
    public static func analyze(
        originalText: String,
        providerKana: String? = nil
    ) -> JapaneseReadingResult {
        analyze(
            originalText: originalText,
            providerKana: providerKana,
            engine: JapaneseMeCabEngine()
        )
    }

    public static func analyze(
        originalText: String,
        providerKana: String? = nil,
        engine: any JapaneseMorphologyEngine
    ) -> JapaneseReadingResult {
        let provider = providerKana?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let provider, !provider.isEmpty {
            let kana = JapaneseRomanizer.toHiraganaPreservingLatin(provider)
            let token = JapaneseReadingToken(
                id: 0,
                originalText: originalText,
                lemma: nil,
                kana: kana,
                romaji: JapaneseRomanizer.romanizeConfirmedKana(kana),
                source: .providerOfficial,
                confidence: 1.0,
                startOffset: 0,
                endOffset: originalText.count
            )
            return JapaneseReadingResult(
                originalText: originalText,
                tokens: [token],
                kanaText: kana,
                romajiText: token.romaji,
                source: .providerOfficial,
                confidence: 1.0
            )
        }

        guard !originalText.isEmpty else {
            return JapaneseReadingResult(
                originalText: originalText,
                tokens: [],
                kanaText: nil,
                romajiText: nil,
                source: .unknown,
                confidence: 0
            )
        }

        let morphology: [JapaneseMorphologyToken]
        do {
            morphology = try engine.tokenize(originalText)
        } catch {
            // Literal-only text is safe to preserve even when MeCab is absent;
            // kana containing ambiguous particles is not.
            if Self.isSafeLiteralOnly(originalText) {
                return Self.literalResult(originalText)
            }
            return Self.unknownResult(originalText)
        }

        guard !morphology.isEmpty,
              morphology.map(\.originalText).joined() == originalText else {
            return Self.unknownResult(originalText)
        }

        var offset = 0
        let tokens = morphology.enumerated().map { index, token in
            let start = offset
            offset += token.originalText.count
            return Self.readingToken(from: token, id: index, startOffset: start)
        }
        let kanaText = tokens.allSatisfy { $0.kana != nil }
            ? tokens.compactMap(\.kana).joined()
            : nil
        let romajiText = tokens.allSatisfy { $0.romaji != nil }
            ? Self.buildRomajiText(from: tokens)
            : nil
        let source = Self.aggregateSource(tokens)
        let confidence = tokens.map(\.confidence).min() ?? 0

        return JapaneseReadingResult(
            originalText: originalText,
            tokens: tokens,
            kanaText: kanaText,
            romajiText: romajiText,
            source: source,
            confidence: confidence
        )
    }

    private static func readingToken(
        from token: JapaneseMorphologyToken,
        id: Int,
        startOffset: Int
    ) -> JapaneseReadingToken {
        let start = startOffset
        let end = startOffset + token.originalText.count

        if isSafeLiteralToken(token.originalText) {
            return JapaneseReadingToken(
                id: id,
                originalText: token.originalText,
                lemma: token.lemma,
                kana: token.originalText,
                romaji: token.originalText,
                source: .literalPreserved,
                confidence: 1.0,
                partOfSpeech: token.partOfSpeech,
                startOffset: start,
                endOffset: end
            )
        }

        guard let rawReading = token.readingKatakana,
              rawReading != "*",
              !rawReading.isEmpty else {
            return unknownToken(from: token, id: id, start: start, end: end)
        }

        let kana = JapaneseRomanizer.toHiraganaPreservingLatin(rawReading)
        // MeCab emits the original surface for unresolved extended Han
        // characters. That is not a reading and must fail closed.
        guard !containsHan(kana) else {
            return unknownToken(from: token, id: id, start: start, end: end)
        }

        let lyricKana = applyParticleReading(
            kana,
            surface: token.originalText,
            partOfSpeech: token.partOfSpeech
        )
        let properNoun = token.partOfSpeech?.contains("固有名詞") == true
        let confidence = properNoun ? 0.72 : 0.96
        return JapaneseReadingToken(
            id: id,
            originalText: token.originalText,
            lemma: token.lemma,
            kana: lyricKana,
            romaji: JapaneseRomanizer.romanizeConfirmedKana(lyricKana),
            source: .mecabIPADIC,
            confidence: confidence,
            partOfSpeech: token.partOfSpeech,
            startOffset: start,
            endOffset: end
        )
    }

    private static func unknownToken(
        from token: JapaneseMorphologyToken,
        id: Int,
        start: Int,
        end: Int
    ) -> JapaneseReadingToken {
        JapaneseReadingToken(
            id: id,
            originalText: token.originalText,
            lemma: token.lemma,
            kana: nil,
            romaji: nil,
            source: .unknown,
            confidence: 0,
            partOfSpeech: token.partOfSpeech,
            startOffset: start,
            endOffset: end
        )
    }

    private static func applyParticleReading(
        _ kana: String,
        surface: String,
        partOfSpeech: String?
    ) -> String {
        guard partOfSpeech?.hasPrefix("助詞") == true else { return kana }
        switch surface {
        case "は": return "わ"
        case "へ": return "え"
        case "を": return "お"
        default: return kana
        }
    }

    private static func buildRomajiText(from tokens: [JapaneseReadingToken]) -> String {
        var result = ""
        var previous: JapaneseReadingToken?

        for token in tokens {
            guard let piece = token.romaji else { continue }
            let whitespace = token.originalText.unicodeScalars.allSatisfy {
                CharacterSet.whitespacesAndNewlines.contains($0)
            }
            let punctuation = token.partOfSpeech?.hasPrefix("記号") == true
                || token.originalText.unicodeScalars.allSatisfy {
                    CharacterSet.punctuationCharacters.contains($0)
                }

            if result.isEmpty || whitespace || punctuation {
                result += piece
            } else if let previous {
                if isWhitespace(previous.originalText) {
                    result += piece
                } else if shouldJoin(previous, token) || isOpeningPunctuation(previous.originalText) {
                    result += piece
                } else {
                    result += " " + piece
                }
            } else {
                result += piece
            }
            previous = token
        }
        return result
    }

    private static func shouldJoin(_ previous: JapaneseReadingToken, _ current: JapaneseReadingToken) -> Bool {
        guard !isWhitespace(previous.originalText), !isWhitespace(current.originalText) else { return false }
        if previous.source == .literalPreserved,
           current.source == .literalPreserved,
           isLatinOrDigit(previous.originalText),
           isLatinOrDigit(current.originalText) {
            return true
        }
        let previousPOS = previous.partOfSpeech ?? ""
        let currentPOS = current.partOfSpeech ?? ""
        if previousPOS.contains("動詞") && (currentPOS.contains("動詞") || currentPOS.contains("助動詞") || currentPOS.contains("接続助詞")) {
            return true
        }
        if previousPOS.contains("形容詞") && currentPOS.contains("助動詞") {
            return true
        }
        if previousPOS.contains("接続助詞") && currentPOS.contains("動詞-非自立") {
            return true
        }
        return false
    }

    private static func aggregateSource(_ tokens: [JapaneseReadingToken]) -> JapaneseReadingSource {
        let sources = Set(tokens.map(\.source))
        if sources.count == 1 { return sources.first ?? .unknown }
        return .mixed
    }

    private static func unknownResult(_ originalText: String) -> JapaneseReadingResult {
        let token = JapaneseReadingToken(
            id: 0,
            originalText: originalText,
            lemma: nil,
            kana: nil,
            romaji: nil,
            source: .unknown,
            confidence: 0,
            startOffset: 0,
            endOffset: originalText.count
        )
        return JapaneseReadingResult(
            originalText: originalText,
            tokens: [token],
            kanaText: nil,
            romajiText: nil,
            source: .unknown,
            confidence: 0
        )
    }

    private static func literalResult(_ originalText: String) -> JapaneseReadingResult {
        let token = JapaneseReadingToken(
            id: 0,
            originalText: originalText,
            lemma: originalText,
            kana: JapaneseRomanizer.toHiraganaPreservingLatin(originalText),
            romaji: JapaneseRomanizer.romanizeConfirmedKana(originalText),
            source: .literalPreserved,
            confidence: 1.0,
            startOffset: 0,
            endOffset: originalText.count
        )
        return JapaneseReadingResult(
            originalText: originalText,
            tokens: [token],
            kanaText: token.kana,
            romajiText: token.romaji,
            source: .literalPreserved,
            confidence: 1.0
        )
    }

    private static func isSafeLiteralOnly(_ text: String) -> Bool {
        guard !containsHan(text) else { return false }
        // Without morphology we cannot safely disambiguate lyric particles.
        return !text.contains("は") && !text.contains("へ") && !text.contains("を")
    }

    private static func isSafeLiteralToken(_ text: String) -> Bool {
        guard !containsHan(text) else { return false }
        let hasKana = text.unicodeScalars.contains { isKana($0) }
        if hasKana { return false }
        return true
    }

    private static func isLatinOrDigit(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (0x30...0x39).contains(value)
                || (0x41...0x5A).contains(value)
                || (0x61...0x7A).contains(value)
                || (0xFF10...0xFF19).contains(value)
                || (0xFF21...0xFF3A).contains(value)
                || (0xFF41...0xFF5A).contains(value)
        }
    }

    private static func isWhitespace(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy {
            CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }

    private static func isOpeningPunctuation(_ text: String) -> Bool {
        ["「", "『", "（", "(", "[", "【", "〈", "《"].contains(text)
    }

    private static func isKana(_ scalar: UnicodeScalar) -> Bool {
        (0x3040...0x30FF).contains(scalar.value)
    }

    private static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let value = scalar.value
            return (0x3400...0x4DBF).contains(value)
                || (0x4E00...0x9FFF).contains(value)
                || (0xF900...0xFAFF).contains(value)
                || (0x20000...0x2FA1F).contains(value)
        }
    }
}

public extension LyricRubyToken {
    /// Converts one confirmed morphology token into a display token.
    /// Kana-only, Latin, numeric and punctuation tokens remain base text only;
    /// they do not receive a redundant ruby line above them.
    init(readingToken: JapaneseReadingToken) {
        let ruby = Self.containsHan(readingToken.originalText)
            ? readingToken.kana
            : nil
        self.init(
            id: readingToken.id,
            surface: readingToken.originalText,
            ruby: ruby,
            romaji: readingToken.romaji,
            confidence: readingToken.confidence
        )
    }

    private static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let value = scalar.value
            return (0x3400...0x4DBF).contains(value)
                || (0x4E00...0x9FFF).contains(value)
                || (0xF900...0xFAFF).contains(value)
                || (0x20000...0x2FA1F).contains(value)
        }
    }
}
