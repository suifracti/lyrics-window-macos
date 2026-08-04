import Foundation

/// Per-line language classification used by all reading engines.  The value
/// is a routing decision only; it never changes the original lyric surface.
public enum ReadingLanguage: String, CaseIterable, Codable, Sendable, Equatable {
    case japanese
    case simplifiedChinese
    case traditionalChinese
    case latin
    case mixed
    case unknown

    public var displayName: String {
        switch self {
        case .japanese: return "日语"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁体中文"
        case .latin: return "英文 / 拉丁文字"
        case .mixed: return "混合语言"
        case .unknown: return "待确认"
        }
    }
}

public enum ReadingEngineID: String, CaseIterable, Codable, Sendable {
    case japaneseDictionary = "readingEngine.japaneseDictionary.v1"
    case japaneseContextual = "readingEngine.japaneseContextual.v2"
    case chinesePinyin = "readingEngine.chinesePinyin.v1"
}

public enum ReadingRepresentationID: String, CaseIterable, Codable, Sendable {
    case kana = "readingRepresentation.kana.v1"
    case romaji = "readingRepresentation.romaji.v1"
    case pinyinToneMarks = "readingRepresentation.pinyinToneMarks.v1"
    case pinyinToneNumbers = "readingRepresentation.pinyinToneNumbers.v1"
    case pinyinPlain = "readingRepresentation.pinyinPlain.v1"

    public var displayName: String {
        switch self {
        case .kana: return "假名"
        case .romaji: return "罗马音"
        case .pinyinToneMarks: return "拼音（声调符号）"
        case .pinyinToneNumbers: return "拼音（声调数字）"
        case .pinyinPlain: return "拼音（无声调）"
        }
    }
}

public enum ScriptConversionID: String, CaseIterable, Codable, Sendable {
    case traditionalToSimplified = "scriptConversion.traditionalToSimplified.v1"
    case simplifiedToTraditional = "scriptConversion.simplifiedToTraditional.v1"
    case none = "scriptConversion.none.v1"
}

public enum ReadingTokenSource: String, Codable, Sendable, Equatable {
    case provider
    case userDictionary
    case mecabIPADIC
    case contextualLocal
    case aiCandidate
    case pinyinDictionary
    case scriptConversion
    case preserved
    case unknown
}

public enum ReadingVersionSourceKind: String, Codable, Sendable, Equatable {
    case generated
    case legacyImported
    case providerEmbedded
    case manualEdit
}

public enum ReadingWarningCode: String, Codable, Sendable, Equatable {
    case languageNeedsConfirmation
    case ambiguousReading
    case unknownToken
    case aiCandidateOnly
    case sourceUnavailable
    case mixedLanguage
}

public struct ReadingSegment: Identifiable, Codable, Hashable, Sendable, Equatable {
    public let id: Int
    public let text: String
    public let language: ReadingLanguage
    public let startOffset: Int
    public let endOffset: Int

    public init(id: Int, text: String, language: ReadingLanguage, startOffset: Int, endOffset: Int) {
        self.id = id
        self.text = text
        self.language = language
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}

public struct ReadingLanguageAnalysis: Codable, Hashable, Sendable, Equatable {
    public let language: ReadingLanguage
    public let segments: [ReadingSegment]
    public let needsConfirmation: Bool

    public init(language: ReadingLanguage, segments: [ReadingSegment], needsConfirmation: Bool) {
        self.language = language
        self.segments = segments
        self.needsConfirmation = needsConfirmation
    }
}

public struct ReadingToken: Identifiable, Codable, Hashable, Sendable, Equatable {
    public let id: Int
    public let surface: String
    public let reading: String?
    public let startOffset: Int
    public let endOffset: Int
    public let source: ReadingTokenSource
    public let confidence: Double
    public let needsConfirmation: Bool

    public init(
        id: Int,
        surface: String,
        reading: String?,
        startOffset: Int,
        endOffset: Int,
        source: ReadingTokenSource,
        confidence: Double,
        needsConfirmation: Bool = false
    ) {
        self.id = id
        self.surface = surface
        self.reading = reading
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.source = source
        self.confidence = confidence
        self.needsConfirmation = needsConfirmation
    }
}

public struct ReadingLineResult: Codable, Hashable, Sendable, Equatable {
    public let lineIndex: Int
    public let originalText: String
    public let readingText: String?
    public let language: ReadingLanguage
    public let tokens: [ReadingToken]
    public let warnings: [ReadingWarningCode]
    public let confidence: Double

    public init(
        lineIndex: Int,
        originalText: String,
        readingText: String?,
        language: ReadingLanguage,
        tokens: [ReadingToken],
        warnings: [ReadingWarningCode] = [],
        confidence: Double
    ) {
        self.lineIndex = lineIndex
        self.originalText = originalText
        self.readingText = readingText
        self.language = language
        self.tokens = tokens
        self.warnings = warnings
        self.confidence = confidence
    }
}

/// SQLite-shaped version metadata.  Reading content is intentionally kept
/// outside lyrics_versions and lyric_lines so changing a reading never
/// changes the source lyric, translation, or timing.
public struct ReadingVersionRecord: Codable, Hashable, Sendable, Equatable {
    public let id: UUID
    public let lyricsVersionID: UUID
    public let sourceContentHash: String
    public let engineID: String
    public let representationID: String
    public let sourceKind: ReadingVersionSourceKind
    public let language: ReadingLanguage
    public let createdAt: Date
    public let updatedAt: Date
    public let isMachineGenerated: Bool
    public let isManuallyEdited: Bool
    public let isCurrent: Bool
    public let isLocked: Bool
    public let isArchived: Bool
    public let parentVersionID: UUID?
    public let confidence: Double
    public let warningMetadata: [ReadingWarningCode]
    public let contextHash: String

    public init(
        id: UUID,
        lyricsVersionID: UUID,
        sourceContentHash: String,
        engineID: String,
        representationID: String,
        sourceKind: ReadingVersionSourceKind = .generated,
        language: ReadingLanguage,
        createdAt: Date,
        updatedAt: Date,
        isMachineGenerated: Bool,
        isManuallyEdited: Bool,
        isCurrent: Bool,
        isLocked: Bool,
        isArchived: Bool,
        parentVersionID: UUID?,
        confidence: Double,
        warningMetadata: [ReadingWarningCode],
        contextHash: String
    ) {
        self.id = id
        self.lyricsVersionID = lyricsVersionID
        self.sourceContentHash = sourceContentHash
        self.engineID = engineID
        self.representationID = representationID
        self.sourceKind = sourceKind
        self.language = language
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isMachineGenerated = isMachineGenerated
        self.isManuallyEdited = isManuallyEdited
        self.isCurrent = isCurrent
        self.isLocked = isLocked
        self.isArchived = isArchived
        self.parentVersionID = parentVersionID
        self.confidence = confidence
        self.warningMetadata = warningMetadata
        self.contextHash = contextHash
    }

    public func with(
        isCurrent: Bool? = nil,
        isLocked: Bool? = nil,
        isArchived: Bool? = nil,
        isManuallyEdited: Bool? = nil
    ) -> ReadingVersionRecord {
        ReadingVersionRecord(
            id: id,
            lyricsVersionID: lyricsVersionID,
            sourceContentHash: sourceContentHash,
            engineID: engineID,
            representationID: representationID,
            sourceKind: sourceKind,
            language: language,
            createdAt: createdAt,
            updatedAt: Date(),
            isMachineGenerated: isMachineGenerated,
            isManuallyEdited: isManuallyEdited ?? self.isManuallyEdited,
            isCurrent: isCurrent ?? self.isCurrent,
            isLocked: isLocked ?? self.isLocked,
            isArchived: isArchived ?? self.isArchived,
            parentVersionID: parentVersionID,
            confidence: confidence,
            warningMetadata: warningMetadata,
            contextHash: contextHash
        )
    }
}

public struct StoredReadingVersion: Codable, Hashable, Sendable, Equatable {
    public let record: ReadingVersionRecord
    public let lines: [ReadingLineResult]

    public init(record: ReadingVersionRecord, lines: [ReadingLineResult]) {
        self.record = record
        self.lines = lines.sorted { $0.lineIndex < $1.lineIndex }
    }

    public var isComplete: Bool {
        !lines.isEmpty && lines.allSatisfy { line in
            line.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !(line.readingText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }
}

public struct ReadingInputLine: Codable, Hashable, Sendable, Equatable {
    public let lineIndex: Int
    public let originalText: String

    public init(lineIndex: Int, originalText: String) {
        self.lineIndex = lineIndex
        self.originalText = originalText
    }
}

public struct ReadingGenerationRequest: Sendable, Equatable {
    public let lyricsVersionID: UUID
    public let sourceContentHash: String
    public let lines: [ReadingInputLine]
    public let languageHint: String?
    public let nearbyContext: [String]
    public let representationID: ReadingRepresentationID

    public init(
        lyricsVersionID: UUID,
        sourceContentHash: String,
        lines: [ReadingInputLine],
        languageHint: String?,
        nearbyContext: [String] = [],
        representationID: ReadingRepresentationID
    ) {
        self.lyricsVersionID = lyricsVersionID
        self.sourceContentHash = sourceContentHash
        self.lines = lines
        self.languageHint = languageHint
        self.nearbyContext = nearbyContext
        self.representationID = representationID
    }
}

public struct ReadingGenerationResult: Sendable, Equatable {
    public let engineID: ReadingEngineID
    public let representationID: ReadingRepresentationID
    public let lines: [ReadingLineResult]
    public let language: ReadingLanguage
    public let confidence: Double
    public let warnings: [ReadingWarningCode]
    public let contextHash: String

    public init(
        engineID: ReadingEngineID,
        representationID: ReadingRepresentationID,
        lines: [ReadingLineResult],
        language: ReadingLanguage,
        confidence: Double,
        warnings: [ReadingWarningCode] = [],
        contextHash: String
    ) {
        self.engineID = engineID
        self.representationID = representationID
        self.lines = lines
        self.language = language
        self.confidence = confidence
        self.warnings = warnings
        self.contextHash = contextHash
    }
}

public protocol ReadingEngine: Sendable {
    var stableID: ReadingEngineID { get }
    func generate(_ request: ReadingGenerationRequest) async throws -> ReadingGenerationResult
}

public struct ReadingVersionSaveRequest: Sendable, Equatable {
    public let record: ReadingVersionRecord
    public let lines: [ReadingLineResult]

    public init(record: ReadingVersionRecord, lines: [ReadingLineResult]) {
        self.record = record
        self.lines = lines.sorted { $0.lineIndex < $1.lineIndex }
    }
}

public enum ReadingRepositoryError: Error, Equatable, Sendable, LocalizedError {
    case sourceLyricsNotFound
    case sourceContentMismatch
    case invalidLines(String)
    case versionNotFound
    case lockedVersion
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .sourceLyricsNotFound: return "找不到读音对应的歌词版本"
        case .sourceContentMismatch: return "读音对应的歌词内容已变化"
        case .invalidLines(let message): return "读音行校验失败：\(message)"
        case .versionNotFound: return "找不到读音版本"
        case .lockedVersion: return "读音版本已锁定"
        case .database(let message): return "读音数据库错误：\(message)"
        }
    }
}

public protocol ReadingRepository: Sendable {
    func loadReadingVersions(
        lyricsVersionID: UUID,
        representationID: String?,
        sourceContentHash: String
    ) async throws -> [StoredReadingVersion]
    func saveReadingVersion(_ request: ReadingVersionSaveRequest) async throws -> StoredReadingVersion
    func adoptReadingVersion(versionID: UUID) async throws
    func markReadingLocked(versionID: UUID, locked: Bool) async throws
    func archiveReadingVersion(versionID: UUID, archived: Bool) async throws
    func deleteReadingVersion(versionID: UUID) async throws
}

public actor UnavailableReadingRepository: ReadingRepository {
    public init() {}

    public func loadReadingVersions(
        lyricsVersionID: UUID,
        representationID: String?,
        sourceContentHash: String
    ) async throws -> [StoredReadingVersion] {
        _ = lyricsVersionID; _ = representationID; _ = sourceContentHash
        throw ReadingRepositoryError.database("当前仓库不支持读音版本")
    }

    public func saveReadingVersion(_ request: ReadingVersionSaveRequest) async throws -> StoredReadingVersion {
        _ = request
        throw ReadingRepositoryError.database("当前仓库不支持读音版本")
    }

    public func adoptReadingVersion(versionID: UUID) async throws { _ = versionID; throw ReadingRepositoryError.database("当前仓库不支持读音版本") }
    public func markReadingLocked(versionID: UUID, locked: Bool) async throws { _ = versionID; _ = locked; throw ReadingRepositoryError.database("当前仓库不支持读音版本") }
    public func archiveReadingVersion(versionID: UUID, archived: Bool) async throws { _ = versionID; _ = archived; throw ReadingRepositoryError.database("当前仓库不支持读音版本") }
    public func deleteReadingVersion(versionID: UUID) async throws { _ = versionID; throw ReadingRepositoryError.database("当前仓库不支持读音版本") }
}
