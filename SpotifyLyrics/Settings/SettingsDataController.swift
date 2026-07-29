import AppKit
import Combine
import Foundation

@MainActor
public final class SettingsDataController: ObservableObject {
    @Published public private(set) var statistics: LyricsDatabaseStats?
    @Published public private(set) var statusMessage = ""
    @Published public private(set) var isBusy = false

    private let repository: any LyricsRepository
    private let localIndex: LocalLyricsIndex

    public init(
        repository: any LyricsRepository = SQLiteLyricsRepository(),
        localIndex: LocalLyricsIndex = .shared
    ) {
        self.repository = repository
        self.localIndex = localIndex
    }

    public func refreshStatistics() {
        run("正在读取数据库统计…") { repository in
            try await repository.statistics()
        } onSuccess: { [weak self] stats in
            self?.statistics = stats
            self?.statusMessage = "数据库统计已更新"
        }
    }

    public func createBackup() {
        run("正在创建数据库备份…") { repository in
            try await repository.createBackup()
        } onSuccess: { [weak self] url in
            self?.statusMessage = "备份已创建：\(url.lastPathComponent)"
        }
    }

    public func clearLyricsCache() {
        run("正在清除歌词缓存…") { repository in
            try await repository.clearLyricsCache()
            return ()
        } onSuccess: { [weak self] _ in
            self?.statusMessage = "歌词缓存已清除，歌曲元数据仍保留"
            self?.refreshStatistics()
        }
    }

    /// Creates the safety backup and clears the cache as one serialized operation.
    /// Keeping both SQL operations in one task avoids the UI triggering the second
    /// operation while the repository controller is still busy with the backup.
    public func backupAndClearLyricsCache() {
        guard !isBusy else { return }
        isBusy = true
        statusMessage = "正在创建备份并清除歌词缓存…"
        let repository = self.repository
        Task { @MainActor [weak self] in
            defer { self?.isBusy = false }
            do {
                let backupURL = try await repository.createBackup()
                try await repository.clearLyricsCache()
                self?.statusMessage = "备份已创建并清除歌词缓存：\(backupURL.lastPathComponent)"
                self?.refreshStatistics()
            } catch {
                self?.statusMessage = error.localizedDescription
            }
        }
    }

    public func rebuildLocalIndex() {
        let count = localIndex.rebuild()
        statusMessage = "本地歌词索引已重建（\(count) 个文件）"
    }

    public func revealDatabase() {
        let url = statistics?.databaseURL ?? SQLiteLyricsRepository.defaultDatabaseURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            statusMessage = "数据库文件尚未创建"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func exportDiagnostics() {
        let stats = statistics
        let lines = [
            "SpotifyLyrics 脱敏诊断摘要",
            "生成时间：\(ISO8601DateFormatter().string(from: Date()))",
            "数据库路径：\(stats?.databaseURL.path ?? SQLiteLyricsRepository.defaultDatabaseURL.path)",
            "Schema：v\(stats?.schemaVersion ?? DatabaseMigrator.currentVersion)",
            "Track 数量：\(stats?.trackCount ?? 0)",
            "LyricsVersion 数量：\(stats?.lyricsVersionCount ?? 0)",
            "LyricLine 数量：\(stats?.lyricLineCount ?? 0)",
            "数据库大小：\(stats.map { Self.formatBytes($0.fileSize) } ?? "未知")",
            "最近更新时间：\(stats.flatMap(\.lastUpdated).map { ISO8601DateFormatter().string(from: $0) } ?? "未知")",
            "注意：此摘要不包含 Client Secret、Access Token、Refresh Token 或完整授权响应。"
        ]
        let directory = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let url = directory.appendingPathComponent("SpotifyLyrics-Diagnostics-\(Self.fileTimestamp()).txt")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "诊断摘要已导出：\(url.lastPathComponent)"
        } catch {
            statusMessage = "诊断摘要导出失败：\(error.localizedDescription)"
        }
    }

    private func run<T: Sendable>(
        _ message: String,
        operation: @escaping @Sendable (any LyricsRepository) async throws -> T,
        onSuccess: @escaping @MainActor (T) -> Void
    ) {
        guard !isBusy else { return }
        isBusy = true
        statusMessage = message
        let repository = self.repository
        Task { @MainActor [weak self] in
            defer { self?.isBusy = false }
            do {
                let value = try await operation(repository)
                onSuccess(value)
            } catch {
                self?.statusMessage = error.localizedDescription
            }
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
