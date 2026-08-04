import Foundation

public struct StoredTranslationVersion: Equatable, Sendable {
    public let record: DatabaseTranslationVersionRecord
    public let lines: [DatabaseTranslationLineRecord]

    public init(record: DatabaseTranslationVersionRecord, lines: [DatabaseTranslationLineRecord]) {
        self.record = record
        self.lines = lines
    }

    public var isComplete: Bool {
        record.status == .complete
    }

    public var isDraft: Bool { record.isDraft }
    public var isArchived: Bool { record.isArchived }

    public func with(record: DatabaseTranslationVersionRecord) -> StoredTranslationVersion {
        StoredTranslationVersion(record: record, lines: lines)
    }
}

public enum TranslationRepositoryError: Error, Equatable, Sendable, LocalizedError {
    case sourceLyricsNotFound
    case sourceContentMismatch
    case invalidLines(String)
    case versionNotFound
    case lockedVersion
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .sourceLyricsNotFound: return "找不到翻译对应的歌词版本"
        case .sourceContentMismatch: return "翻译对应的歌词内容已变化"
        case .invalidLines(let message): return "翻译行校验失败：\(message)"
        case .versionNotFound: return "找不到翻译版本"
        case .lockedVersion: return "翻译版本已锁定"
        case .database(let message): return "翻译数据库错误：\(message)"
        }
    }
}

/// Translation storage remains separate from the legacy lyric_lines column.
/// Implementations must write only complete, validated versions in one
/// transaction and must never persist an in-flight or failed request.
public protocol TranslationRepository: Sendable {
    func loadTranslationVersions(
        lyricsVersionID: UUID,
        targetLanguage: String,
        sourceContentHash: String
    ) async throws -> [StoredTranslationVersion]

    func saveTranslation(
        lyricsVersionID: UUID,
        sourceContentHash: String,
        originalLines: [String],
        draft: AITranslationDraft,
        forceNewVersion: Bool
    ) async throws -> StoredTranslationVersion

    func markTranslationLocked(versionID: UUID, locked: Bool) async throws
    func deleteTranslation(versionID: UUID) async throws
    func adoptTranslation(versionID: UUID) async throws
    func archiveTranslation(versionID: UUID, archived: Bool) async throws
}

public extension TranslationRepository {
    /// Compatibility defaults keep lightweight contract repositories source
    /// compatible; SQLite provides the real state transition.
    func adoptTranslation(versionID: UUID) async throws { _ = versionID }
    func archiveTranslation(versionID: UUID, archived: Bool) async throws { _ = versionID; _ = archived }
}

public actor UnavailableTranslationRepository: TranslationRepository {
    public init() {}

    public func loadTranslationVersions(
        lyricsVersionID: UUID,
        targetLanguage: String,
        sourceContentHash: String
    ) async throws -> [StoredTranslationVersion] {
        _ = lyricsVersionID; _ = targetLanguage; _ = sourceContentHash
        throw TranslationRepositoryError.database("当前仓库不支持翻译持久化")
    }

    public func saveTranslation(
        lyricsVersionID: UUID,
        sourceContentHash: String,
        originalLines: [String],
        draft: AITranslationDraft,
        forceNewVersion: Bool
    ) async throws -> StoredTranslationVersion {
        _ = lyricsVersionID; _ = sourceContentHash; _ = originalLines; _ = draft; _ = forceNewVersion
        throw TranslationRepositoryError.database("当前仓库不支持翻译持久化")
    }

    public func markTranslationLocked(versionID: UUID, locked: Bool) async throws {
        _ = versionID; _ = locked
        throw TranslationRepositoryError.database("当前仓库不支持翻译持久化")
    }

    public func deleteTranslation(versionID: UUID) async throws {
        _ = versionID
        throw TranslationRepositoryError.database("当前仓库不支持翻译持久化")
    }

    public func adoptTranslation(versionID: UUID) async throws {
        _ = versionID
        throw TranslationRepositoryError.database("当前仓库不支持翻译持久化")
    }

    public func archiveTranslation(versionID: UUID, archived: Bool) async throws {
        _ = versionID; _ = archived
        throw TranslationRepositoryError.database("当前仓库不支持翻译持久化")
    }
}
