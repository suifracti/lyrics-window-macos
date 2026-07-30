import Foundation

public struct StoredEditableLyricsVersion: Equatable, Sendable {
    public let record: DatabaseLyricsVersionRecord
    public let lines: [DatabaseLyricLineRecord]
    public let document: LyricsDocument
    public let lockedReadingLayers: [DatabaseReadingLayerRecord]

    public init(
        record: DatabaseLyricsVersionRecord,
        lines: [DatabaseLyricLineRecord],
        document: LyricsDocument,
        lockedReadingLayers: [DatabaseReadingLayerRecord] = []
    ) {
        self.record = record
        self.lines = lines
        self.document = document
        self.lockedReadingLayers = lockedReadingLayers
    }
}

public struct LyricsReadingLayerDraft: Equatable, Sendable {
    public let lineIndex: Int
    public let kanaText: String?
    public let romajiText: String?
    public let source: String
    public let isLocked: Bool

    public init(lineIndex: Int, kanaText: String?, romajiText: String?, source: String = "manualEdit", isLocked: Bool) {
        self.lineIndex = lineIndex
        self.kanaText = kanaText
        self.romajiText = romajiText
        self.source = source
        self.isLocked = isLocked
    }
}

public struct ManualTranslationEdit: Equatable, Sendable {
    public let targetLanguage: String
    public let model: String
    public let baseURLHost: String
    public let promptHash: String
    public let lines: [String]
    public let parentVersionID: UUID?
    public let isLocked: Bool

    public init(
        targetLanguage: String,
        model: String = "",
        baseURLHost: String = "",
        promptHash: String = "",
        lines: [String],
        parentVersionID: UUID? = nil,
        isLocked: Bool = false
    ) {
        self.targetLanguage = targetLanguage
        self.model = model
        self.baseURLHost = baseURLHost
        self.promptHash = promptHash
        self.lines = lines
        self.parentVersionID = parentVersionID
        self.isLocked = isLocked
    }
}

public struct LyricsEditSaveRequest: Equatable, Sendable {
    public let track: Track
    public let identity: TrackIdentity
    public let sourceVersionID: UUID
    public let sourceContentHash: String
    public let document: LyricsDocument
    public let createLyricsVersion: Bool
    public let lockLyricsVersion: Bool
    public let targetSource: LyricsSource
    public let translation: ManualTranslationEdit?
    public let readingLayers: [LyricsReadingLayerDraft]

    public init(
        track: Track,
        identity: TrackIdentity,
        sourceVersionID: UUID,
        sourceContentHash: String,
        document: LyricsDocument,
        createLyricsVersion: Bool,
        lockLyricsVersion: Bool = false,
        targetSource: LyricsSource = .manualEdit,
        translation: ManualTranslationEdit? = nil,
        readingLayers: [LyricsReadingLayerDraft] = []
    ) {
        self.track = track
        self.identity = identity
        self.sourceVersionID = sourceVersionID
        self.sourceContentHash = sourceContentHash
        self.document = document
        self.createLyricsVersion = createLyricsVersion
        self.lockLyricsVersion = lockLyricsVersion
        self.targetSource = targetSource
        self.translation = translation
        self.readingLayers = readingLayers
    }
}

public struct LyricsEditSaveResult: Equatable, Sendable {
    public let lyricsVersion: StoredEditableLyricsVersion?
    public let translationVersion: StoredTranslationVersion?

    public init(lyricsVersion: StoredEditableLyricsVersion?, translationVersion: StoredTranslationVersion?) {
        self.lyricsVersion = lyricsVersion
        self.translationVersion = translationVersion
    }
}

public enum LyricsEditingRepositoryError: Error, Equatable, Sendable, LocalizedError {
    case sourceNotFound
    case sourceContentMismatch
    case identityMismatch
    case invalidDocument(String)
    case invalidTimeline(String)
    case invalidTranslation(String)
    case noChanges
    case lockedVersion

    public var errorDescription: String? {
        switch self {
        case .sourceNotFound: return "找不到编辑来源歌词版本"
        case .sourceContentMismatch: return "编辑来源内容已经变化"
        case .identityMismatch: return "编辑内容不属于当前歌曲"
        case .invalidTimeline(let message): return "时间轴校验失败：\(message)"
        case .invalidTranslation(let message): return "翻译校验失败：\(message)"
        case .invalidDocument(let message): return "歌词文档无效：\(message)"
        case .noChanges: return "没有需要保存的编辑"
        case .lockedVersion: return "锁定版本不能被直接覆盖"
        }
    }
}

public protocol LyricsEditingRepository: Sendable {
    func loadEditableVersions(track: Track, identity: TrackIdentity) async throws -> [StoredEditableLyricsVersion]
    func loadEditableVersion(versionID: UUID, track: Track, identity: TrackIdentity) async throws -> StoredEditableLyricsVersion?
    /// Translation versions are loaded through the same repository boundary
    /// when the editor switches lyric source versions. The editor must never
    /// reach into SQLite or construct a second translation state source.
    func loadTranslationVersions(
        lyricsVersionID: UUID,
        targetLanguage: String,
        sourceContentHash: String
    ) async throws -> [StoredTranslationVersion]
    func saveManualEdit(_ request: LyricsEditSaveRequest) async throws -> LyricsEditSaveResult
    func markLyricsVersionLocked(versionID: UUID, locked: Bool) async throws
}
