import Foundation
import SQLite3

/// SQLite-backed lyrics cache. The actor is deliberately not MainActor:
/// sqlite3 calls, migrations, and transactions are serialized here without
/// blocking SwiftUI or Spotify playback state.
public actor SQLiteLyricsRepository: LyricsRepository {
    public nonisolated let databaseURL: URL

    private var database: OpaquePointer?
    private var prepared = false

    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3")
    }

    public init(databaseURL: URL = SQLiteLyricsRepository.defaultDatabaseURL) {
        self.databaseURL = databaseURL
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    public func prepare() throws {
        guard !prepared else { return }

        do {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw LyricsRepositoryError.databaseOpenFailed(error.localizedDescription)
        }

        var handle: OpaquePointer?
        let openFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(databaseURL.path, &handle, openFlags, nil)
        guard openResult == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite open error \(openResult)"
            if let handle { sqlite3_close(handle) }
            throw LyricsRepositoryError.databaseOpenFailed(message)
        }

        database = handle
        sqlite3_busy_timeout(handle, 3_000)
        do {
            try execute("PRAGMA foreign_keys = ON;")
            guard try scalarInt("PRAGMA foreign_keys;") == 1 else {
                throw LyricsRepositoryError.sqlite("foreign_keys 未启用")
            }
            try DatabaseMigrator.migrate(handle)
            prepared = true
        } catch let error as LyricsRepositoryError {
            sqlite3_close(handle)
            database = nil
            throw error
        } catch {
            sqlite3_close(handle)
            database = nil
            throw LyricsRepositoryError.unavailable(error.localizedDescription)
        }
    }

    public func loadBest(track: Track, identity: TrackIdentity) throws -> LyricsDocument? {
        try ensurePrepared()
        _ = track

        guard let trackRecord = try fetchTrack(stableKey: identity.stableKey) else {
            return nil
        }
        guard let version = try fetchBestVersion(stableKey: identity.stableKey) else {
            return nil
        }
        let lines = try fetchLines(versionID: version.id)
        guard !lines.isEmpty else {
            // Empty rows are invalid cache state; do not expose them as lyrics.
            return nil
        }
        return LyricsPersistenceMapper.document(
            identity: identity,
            track: trackRecord,
            version: version,
            lines: lines
        )
    }

    public func save(
        track: Track,
        identity: TrackIdentity,
        document: LyricsDocument
    ) throws -> LyricsPersistenceSaveResult {
        try ensurePrepared()

        guard document.identity == identity else {
            return LyricsPersistenceSaveResult(
                versionID: nil,
                disposition: .rejected("歌词身份与当前 TrackIdentity 不一致")
            )
        }
        guard !document.lines.isEmpty else {
            return LyricsPersistenceSaveResult(versionID: nil, disposition: .rejected("空歌词不写入"))
        }
        guard document.source != .mock else {
            return LyricsPersistenceSaveResult(versionID: nil, disposition: .rejected("Mock 歌词不写入"))
        }
        guard LyricsMatcher.isHighConfidence(document.confidence) else {
            return LyricsPersistenceSaveResult(
                versionID: nil,
                disposition: .rejected("低置信度歌词不写入")
            )
        }

        let now = Date()
        let trackRecord = LyricsPersistenceMapper.trackRecord(track: track, identity: identity, now: now)
        let versionID = UUID()
        let versionRecord = LyricsPersistenceMapper.versionRecord(
            document: document,
            identity: identity,
            versionID: versionID,
            now: now
        )
        let aliases = LyricsPersistenceMapper.aliasRecords(
            track: track,
            identity: identity,
            document: document,
            now: now
        )
        let lines = LyricsPersistenceMapper.lineRecords(document: document, versionID: versionID)

        return try withTransaction {
            try upsertTrack(trackRecord)
            for alias in aliases {
                try insertAlias(alias)
            }

            if let duplicateID = try findVersionID(
                stableKey: identity.stableKey,
                source: versionRecord.source,
                providerSourceID: versionRecord.providerSourceID,
                contentHash: versionRecord.contentHash
            ) {
                return LyricsPersistenceSaveResult(versionID: duplicateID, disposition: .duplicate)
            }

            if try hasLockedVersion(stableKey: identity.stableKey) {
                return LyricsPersistenceSaveResult(versionID: nil, disposition: .skippedLocked)
            }

            try insertVersion(versionRecord)
            for line in lines {
                try insertLine(line)
            }
            return LyricsPersistenceSaveResult(versionID: versionID, disposition: .inserted)
        }
    }

    public func markLocked(versionID: UUID, locked: Bool) throws {
        try ensurePrepared()
        let statement = try prepare("UPDATE lyrics_versions SET is_locked = ?, updated_at = ? WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        try bindInt(locked ? 1 : 0, at: 1, to: statement)
        try bindDouble(Date().timeIntervalSince1970, at: 2, to: statement)
        try bindText(versionID.uuidString, at: 3, to: statement)
        try stepDone(statement)
        guard sqlite3_changes(database) > 0 else {
            throw LyricsRepositoryError.invalidData("找不到歌词版本 \(versionID.uuidString)")
        }
    }

    // Contract/audit helpers. They remain storage-only and do not form part
    // of the playback/UI API.
    public func schemaVersion() throws -> Int {
        try ensurePrepared()
        return try scalarInt("PRAGMA user_version;")
    }

    public func foreignKeysEnabled() throws -> Bool {
        try ensurePrepared()
        return try scalarInt("PRAGMA foreign_keys;") == 1
    }

    public func versionCount(trackStableKey: String) throws -> Int {
        try ensurePrepared()
        let statement = try prepare("SELECT COUNT(*) FROM lyrics_versions WHERE track_stable_key = ?;")
        defer { sqlite3_finalize(statement) }
        try bindText(trackStableKey, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw lastError() }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func ensurePrepared() throws {
        guard prepared, database != nil else {
            throw LyricsRepositoryError.unavailable("数据库尚未准备")
        }
    }

    private func withTransaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let value = try body()
            try execute("COMMIT;")
            return value
        } catch {
            _ = try? execute("ROLLBACK;")
            throw error
        }
    }

    private func upsertTrack(_ record: DatabaseTrackRecord) throws {
        let statement = try prepare("""
            INSERT INTO tracks(
                stable_key, spotify_id, spotify_uri, isrc, title, artist_display,
                album, duration, artwork_url, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(stable_key) DO UPDATE SET
                spotify_id = excluded.spotify_id,
                spotify_uri = excluded.spotify_uri,
                isrc = excluded.isrc,
                title = excluded.title,
                artist_display = excluded.artist_display,
                album = excluded.album,
                duration = excluded.duration,
                artwork_url = excluded.artwork_url,
                updated_at = excluded.updated_at;
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(record.stableKey, at: 1, to: statement)
        try bindText(record.spotifyID, at: 2, to: statement)
        try bindText(record.spotifyURI, at: 3, to: statement)
        try bindText(record.isrc, at: 4, to: statement)
        try bindText(record.title, at: 5, to: statement)
        try bindText(record.artistDisplay, at: 6, to: statement)
        try bindText(record.album, at: 7, to: statement)
        try bindDouble(record.duration, at: 8, to: statement)
        try bindText(record.artworkURL, at: 9, to: statement)
        try bindDouble(record.createdAt.timeIntervalSince1970, at: 10, to: statement)
        try bindDouble(record.updatedAt.timeIntervalSince1970, at: 11, to: statement)
        try stepDone(statement)
    }

    private func insertAlias(_ record: DatabaseTrackAliasRecord) throws {
        let statement = try prepare("""
            INSERT OR IGNORE INTO track_aliases(
                track_stable_key, field, kind, value, language, script,
                source, confidence, is_official
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(record.trackStableKey, at: 1, to: statement)
        try bindText(record.field, at: 2, to: statement)
        try bindText(record.kind, at: 3, to: statement)
        try bindText(record.value, at: 4, to: statement)
        try bindText(record.language, at: 5, to: statement)
        try bindText(record.script, at: 6, to: statement)
        try bindText(record.source, at: 7, to: statement)
        try bindDouble(record.confidence, at: 8, to: statement)
        try bindInt(record.isOfficial ? 1 : 0, at: 9, to: statement)
        try stepDone(statement)
    }

    private func insertVersion(_ record: DatabaseLyricsVersionRecord) throws {
        let statement = try prepare("""
            INSERT INTO lyrics_versions(
                id, track_stable_key, source, provider_source_id, language,
                is_synced, raw_text, content_hash, created_at, updated_at,
                is_machine_generated, is_manually_edited, is_locked, confidence
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(record.id.uuidString, at: 1, to: statement)
        try bindText(record.trackStableKey, at: 2, to: statement)
        try bindText(record.source, at: 3, to: statement)
        try bindText(record.providerSourceID, at: 4, to: statement)
        try bindText(record.language, at: 5, to: statement)
        try bindInt(record.isSynced ? 1 : 0, at: 6, to: statement)
        try bindText(record.rawText, at: 7, to: statement)
        try bindText(record.contentHash, at: 8, to: statement)
        try bindDouble(record.createdAt.timeIntervalSince1970, at: 9, to: statement)
        try bindDouble(record.updatedAt.timeIntervalSince1970, at: 10, to: statement)
        try bindInt(record.isMachineGenerated ? 1 : 0, at: 11, to: statement)
        try bindInt(record.isManuallyEdited ? 1 : 0, at: 12, to: statement)
        try bindInt(record.isLocked ? 1 : 0, at: 13, to: statement)
        try bindDouble(record.confidence, at: 14, to: statement)
        try stepDone(statement)
    }

    private func insertLine(_ record: DatabaseLyricLineRecord) throws {
        let statement = try prepare("""
            INSERT INTO lyric_lines(
                lyrics_version_id, line_index, start_time, end_time,
                original_text, kana_text, romaji_text, translation_text
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(record.lyricsVersionID.uuidString, at: 1, to: statement)
        try bindInt(record.lineIndex, at: 2, to: statement)
        try bindDouble(record.startTime, at: 3, to: statement)
        try bindDouble(record.endTime, at: 4, to: statement)
        try bindText(record.originalText, at: 5, to: statement)
        try bindText(record.kanaText, at: 6, to: statement)
        try bindText(record.romajiText, at: 7, to: statement)
        try bindText(record.translationText, at: 8, to: statement)
        try stepDone(statement)
    }

    private func findVersionID(
        stableKey: String,
        source: String,
        providerSourceID: String,
        contentHash: String
    ) throws -> UUID? {
        let statement = try prepare("""
            SELECT id FROM lyrics_versions
            WHERE track_stable_key = ? AND source = ?
              AND provider_source_id = ? AND content_hash = ?
            LIMIT 1;
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(stableKey, at: 1, to: statement)
        try bindText(source, at: 2, to: statement)
        try bindText(providerSourceID, at: 3, to: statement)
        try bindText(contentHash, at: 4, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let value = columnText(statement, index: 0), let id = UUID(uuidString: value) else {
            throw LyricsRepositoryError.invalidData("歌词版本 UUID 无效")
        }
        return id
    }

    private func hasLockedVersion(stableKey: String) throws -> Bool {
        let statement = try prepare("SELECT 1 FROM lyrics_versions WHERE track_stable_key = ? AND is_locked = 1 LIMIT 1;")
        defer { sqlite3_finalize(statement) }
        try bindText(stableKey, at: 1, to: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func fetchTrack(stableKey: String) throws -> DatabaseTrackRecord? {
        let statement = try prepare("""
            SELECT stable_key, spotify_id, spotify_uri, isrc, title, artist_display,
                   album, duration, artwork_url, created_at, updated_at
            FROM tracks WHERE stable_key = ? LIMIT 1;
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(stableKey, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let key = columnText(statement, index: 0),
              let title = columnText(statement, index: 4),
              let artist = columnText(statement, index: 5),
              let album = columnText(statement, index: 6) else {
            throw LyricsRepositoryError.invalidData("TrackRecord 字段缺失")
        }
        return DatabaseTrackRecord(
            stableKey: key,
            spotifyID: columnText(statement, index: 1),
            spotifyURI: columnText(statement, index: 2),
            isrc: columnText(statement, index: 3),
            title: title,
            artistDisplay: artist,
            album: album,
            duration: sqlite3_column_double(statement, 7),
            artworkURL: columnText(statement, index: 8),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10))
        )
    }

    private func fetchBestVersion(stableKey: String) throws -> DatabaseLyricsVersionRecord? {
        let statement = try prepare("""
            SELECT id, track_stable_key, source, provider_source_id, language,
                   is_synced, raw_text, content_hash, created_at, updated_at,
                   is_machine_generated, is_manually_edited, is_locked, confidence
            FROM lyrics_versions
            WHERE track_stable_key = ? AND (is_locked = 1 OR confidence >= ?)
            ORDER BY is_locked DESC, confidence DESC, updated_at DESC
            LIMIT 1;
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(stableKey, at: 1, to: statement)
        try bindDouble(LyricsMatcher.highConfidenceThreshold, at: 2, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let idText = columnText(statement, index: 0),
              let id = UUID(uuidString: idText),
              let key = columnText(statement, index: 1),
              let source = columnText(statement, index: 2),
              let provider = columnText(statement, index: 3),
              let language = columnText(statement, index: 4),
              let rawText = columnText(statement, index: 6),
              let contentHash = columnText(statement, index: 7) else {
            throw LyricsRepositoryError.invalidData("LyricsVersionRecord 字段缺失")
        }
        return DatabaseLyricsVersionRecord(
            id: id,
            trackStableKey: key,
            source: source,
            providerSourceID: provider,
            language: language,
            isSynced: sqlite3_column_int(statement, 5) != 0,
            rawText: rawText,
            contentHash: contentHash,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
            isMachineGenerated: sqlite3_column_int(statement, 10) != 0,
            isManuallyEdited: sqlite3_column_int(statement, 11) != 0,
            isLocked: sqlite3_column_int(statement, 12) != 0,
            confidence: sqlite3_column_double(statement, 13)
        )
    }

    private func fetchLines(versionID: UUID) throws -> [DatabaseLyricLineRecord] {
        let statement = try prepare("""
            SELECT lyrics_version_id, line_index, start_time, end_time,
                   original_text, kana_text, romaji_text, translation_text
            FROM lyric_lines WHERE lyrics_version_id = ? ORDER BY line_index ASC;
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(versionID.uuidString, at: 1, to: statement)

        var result: [DatabaseLyricLineRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = columnText(statement, index: 0),
                  let id = UUID(uuidString: idText),
                  let original = columnText(statement, index: 4) else {
                throw LyricsRepositoryError.invalidData("LyricLineRecord 字段缺失")
            }
            result.append(
                DatabaseLyricLineRecord(
                    lyricsVersionID: id,
                    lineIndex: Int(sqlite3_column_int(statement, 1)),
                    startTime: columnDouble(statement, index: 2),
                    endTime: columnDouble(statement, index: 3),
                    originalText: original,
                    kanaText: columnText(statement, index: 5),
                    romajiText: columnText(statement, index: 6),
                    translationText: columnText(statement, index: 7)
                )
            )
        }
        return result
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw LyricsRepositoryError.unavailable("SQLite handle 已关闭") }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw LyricsRepositoryError.sqlite(message)
        }
    }

    private func scalarInt(_ sql: String) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw lastError() }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else { throw LyricsRepositoryError.unavailable("SQLite handle 已关闭") }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw lastError(result)
        }
        return statement
    }

    private func bindText(_ value: String?, at index: Int32, to statement: OpaquePointer) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_text(statement, index, value, -1, Self.transientDestructor)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else { throw lastError(result) }
    }

    private func bindInt(_ value: Int, at index: Int32, to statement: OpaquePointer) throws {
        guard sqlite3_bind_int(statement, index, Int32(value)) == SQLITE_OK else { throw lastError() }
    }

    private func bindDouble(_ value: TimeInterval?, at index: Int32, to statement: OpaquePointer) throws {
        let result: Int32
        if let value {
            result = sqlite3_bind_double(statement, index, value)
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else { throw lastError(result) }
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    private func columnText(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func columnDouble(_ statement: OpaquePointer, index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }

    private func lastError(_ result: Int32? = nil) -> LyricsRepositoryError {
        if let result, result != SQLITE_OK {
            return .sqlite("SQLite error (result)")
        }
        guard let database else { return .unavailable("SQLite handle 已关闭") }
        return .sqlite(String(cString: sqlite3_errmsg(database)))
    }
}
