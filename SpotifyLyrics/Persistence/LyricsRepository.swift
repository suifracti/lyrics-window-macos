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

/// Persistence boundary used by the session layer. Implementations must be
/// Sendable and perform blocking storage work away from MainActor.
public protocol LyricsRepository: Sendable {
    func prepare() async throws
    func loadBest(track: Track, identity: TrackIdentity) async throws -> LyricsDocument?
    func save(
        track: Track,
        identity: TrackIdentity,
        document: LyricsDocument
    ) async throws -> LyricsPersistenceSaveResult
    func markLocked(versionID: UUID, locked: Bool) async throws
}
