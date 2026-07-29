import Foundation

public enum LyricsRepositoryError: Error, Equatable, Sendable, LocalizedError {
    case databaseOpenFailed(String)
    case migrationFailed(Int, String)
    case sqlite(String)
    case unsupportedSchema(Int)
    case invalidData(String)
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .databaseOpenFailed(let message): return "歌词数据库打开失败：\(message)"
        case .migrationFailed(let version, let message): return "歌词数据库迁移 v\(version) 失败：\(message)"
        case .sqlite(let message): return "歌词数据库错误：\(message)"
        case .unsupportedSchema(let version): return "歌词数据库版本 \(version) 高于当前 App 支持版本"
        case .invalidData(let message): return "歌词数据库数据无效：\(message)"
        case .unavailable(let message): return "歌词数据库不可用：\(message)"
        }
    }
}

public enum LyricsPersistenceSaveDisposition: Equatable, Sendable {
    case inserted
    case duplicate
    case skippedLocked
    case rejected(String)
}

public struct LyricsPersistenceSaveResult: Equatable, Sendable {
    public let versionID: UUID?
    public let disposition: LyricsPersistenceSaveDisposition

    public init(versionID: UUID?, disposition: LyricsPersistenceSaveDisposition) {
        self.versionID = versionID
        self.disposition = disposition
    }
}

public struct LyricsDatabaseStats: Equatable, Sendable {
    public let databaseURL: URL
    public let schemaVersion: Int
    public let trackCount: Int
    public let lyricsVersionCount: Int
    public let lyricLineCount: Int
    public let fileSize: Int64
    public let lastUpdated: Date?

    public init(
        databaseURL: URL,
        schemaVersion: Int,
        trackCount: Int,
        lyricsVersionCount: Int,
        lyricLineCount: Int,
        fileSize: Int64,
        lastUpdated: Date?
    ) {
        self.databaseURL = databaseURL
        self.schemaVersion = schemaVersion
        self.trackCount = trackCount
        self.lyricsVersionCount = lyricsVersionCount
        self.lyricLineCount = lyricLineCount
        self.fileSize = fileSize
        self.lastUpdated = lastUpdated
    }
}

/// Persistence boundary used by the session layer. Implementations must be
/// Sendable and perform blocking storage work away from MainActor.
public protocol LyricsRepository: Sendable {
    func prepare() async throws
    /// Stores non-lyrics catalog metadata/aliases without creating an empty
    /// LyricsVersion. Implementations may use the default no-op for tests or
    /// repositories that do not persist track metadata yet.
    func saveTrackMetadata(_ metadata: TrackMetadata) async throws
    func loadBest(track: Track, identity: TrackIdentity) async throws -> LyricsDocument?
    func save(
        track: Track,
        identity: TrackIdentity,
        document: LyricsDocument
    ) async throws -> LyricsPersistenceSaveResult
    func markLocked(versionID: UUID, locked: Bool) async throws
    func statistics() async throws -> LyricsDatabaseStats
    func createBackup() async throws -> URL
    func clearLyricsCache() async throws
}

public extension LyricsRepository {
    func saveTrackMetadata(_ metadata: TrackMetadata) async throws {
        _ = metadata
    }

    func statistics() async throws -> LyricsDatabaseStats {
        throw LyricsRepositoryError.unavailable("当前歌词仓库不支持统计")
    }

    func createBackup() async throws -> URL {
        throw LyricsRepositoryError.unavailable("当前歌词仓库不支持备份")
    }

    func clearLyricsCache() async throws {
        throw LyricsRepositoryError.unavailable("当前歌词仓库不支持清理")
    }
}
