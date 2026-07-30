import Foundation
import SQLite3

/// SQLite-backed lyrics cache. The actor is deliberately not MainActor:
/// sqlite3 calls, migrations, and transactions are serialized here without
/// blocking SwiftUI or Spotify playback state.
public actor SQLiteLyricsRepository: LyricsRepository, TranslationRepository {
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

        let databaseAlreadyExisted = FileManager.default.fileExists(atPath: databaseURL.path)

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
            let existingVersion = try scalarInt("PRAGMA user_version;")
            if databaseAlreadyExisted,
               existingVersion > 0,
               existingVersion < DatabaseMigrator.currentVersion {
                try createMigrationBackup()
            }
            try DatabaseMigrator.migrate(handle)
            prepared = true
        } catch let error as LyricsRepositoryError {
            sqlite3_close(handle)
            database = nil
            if case .sqlite = error {
                throw LyricsRepositoryError.migrationFailed(
                    DatabaseMigrator.currentVersion,
                    error.localizedDescription
                )
            }
            throw error
        } catch {
            sqlite3_close(handle)
            database = nil
            throw LyricsRepositoryError.unavailable(error.localizedDescription)
        }
    }

    public func loadBest(track: Track, identity: TrackIdentity) async throws -> LyricsDocument? {
        try await loadBestStored(track: track, identity: identity)?.document
    }

    public func loadBestStored(track: Track, identity: TrackIdentity) async throws -> StoredLyricsDocument? {
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
        let document = LyricsPersistenceMapper.document(
            identity: identity,
            track: trackRecord,
            version: version,
            lines: lines
        )
        return StoredLyricsDocument(
            document: document,
            versionID: version.id,
            sourceContentHash: LyricsSourceContentHasher.hash(
                isSynchronized: version.isSynced,
                lines: lines
            )
        )
    }

    public func saveTrackMetadata(_ metadata: TrackMetadata) throws {
        try ensurePrepared()
        let now = Date()
        let trackRecord = LyricsPersistenceMapper.trackRecord(
            track: metadata.track,
            identity: metadata.identity,
            now: now
        )
        let aliases = LyricsPersistenceMapper.aliasRecords(metadata: metadata, now: now)
        try withTransaction {
            try upsertTrack(trackRecord)
            for alias in aliases {
                try insertAlias(alias)
            }
        }
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
        let sourceContentHash = LyricsSourceContentHasher.hash(
            isSynchronized: document.isSynchronized,
            lines: lines
        )

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
                return LyricsPersistenceSaveResult(
                    versionID: duplicateID,
                    disposition: .duplicate,
                    sourceContentHash: sourceContentHash
                )
            }

            if try hasLockedVersion(stableKey: identity.stableKey) {
                return LyricsPersistenceSaveResult(versionID: nil, disposition: .skippedLocked)
            }

            try insertVersion(versionRecord)
            for line in lines {
                try insertLine(line)
            }
            return LyricsPersistenceSaveResult(
                versionID: versionID,
                disposition: .inserted,
                sourceContentHash: sourceContentHash
            )
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

    public func hasUniqueTranslationVersionIndex() throws -> Bool {
        try ensurePrepared()
        let statement = try prepare("PRAGMA index_list('translation_versions');")
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            // PRAGMA index_list columns: seq, name, unique, origin, partial.
            // The primary-key auto-index is required for version IDs and does
            // not constrain model/host/prompt retranslation. Reject only
            // additional unique indexes.
            let origin = columnText(statement, index: 3) ?? ""
            if sqlite3_column_int(statement, 2) != 0, origin != "pk" { return true }
        }
        return false
    }

    public func statistics() throws -> LyricsDatabaseStats {
        try prepare()
        let trackCount = try scalarInt("SELECT COUNT(*) FROM tracks;")
        let lyricsVersionCount = try scalarInt("SELECT COUNT(*) FROM lyrics_versions;")
        let lyricLineCount = try scalarInt("SELECT COUNT(*) FROM lyric_lines;")
        let lastUpdatedSeconds = try scalarOptionalDouble("""
            SELECT MAX(updated_at) FROM (
                SELECT updated_at FROM tracks
                UNION ALL
                SELECT updated_at FROM lyrics_versions
            );
            """)
        let attributes = try? FileManager.default.attributesOfItem(atPath: databaseURL.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return LyricsDatabaseStats(
            databaseURL: databaseURL,
            schemaVersion: try schemaVersion(),
            trackCount: trackCount,
            lyricsVersionCount: lyricsVersionCount,
            lyricLineCount: lyricLineCount,
            fileSize: fileSize,
            lastUpdated: lastUpdatedSeconds.map(Date.init(timeIntervalSince1970:))
        )
    }

    public func createBackup() throws -> URL {
        try prepare()
        // Checkpoint before copying so a usable backup does not depend on a
        // separate -wal sidecar file.
        try execute("PRAGMA wal_checkpoint(FULL);")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let baseName = databaseURL.deletingPathExtension().lastPathComponent
        var backupURL = databaseURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName).backup-\(formatter.string(from: Date())).sqlite3")
        if FileManager.default.fileExists(atPath: backupURL.path) {
            backupURL.deleteLastPathComponent()
            backupURL = databaseURL.deletingLastPathComponent()
                .appendingPathComponent("\(baseName).backup-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8)).sqlite3")
        }
        do {
            try FileManager.default.copyItem(at: databaseURL, to: backupURL)
        } catch {
            throw LyricsRepositoryError.unavailable("数据库备份失败：\(error.localizedDescription)")
        }
        return backupURL
    }

    public func clearLyricsCache() throws {
        try prepare()
        try withTransaction {
            try execute("DELETE FROM lyric_lines;")
            try execute("DELETE FROM lyrics_versions;")
        }
    }

    // MARK: - TranslationRepository

    public func loadTranslationVersions(
        lyricsVersionID: UUID,
        targetLanguage: String,
        sourceContentHash: String
    ) throws -> [StoredTranslationVersion] {
        try ensurePrepared()
        guard let source = try fetchSourceLyrics(versionID: lyricsVersionID) else {
            throw TranslationRepositoryError.sourceLyricsNotFound
        }
        guard source.hash == sourceContentHash else {
            throw TranslationRepositoryError.sourceContentMismatch
        }

        let statement = try prepare("""
            SELECT id, lyrics_version_id, source_kind, target_language, model,
                   base_url_host, prompt_hash, source_content_hash, created_at,
                   updated_at, is_machine_generated, is_manually_edited,
                   is_locked, status, confidence
            FROM translation_versions
            WHERE lyrics_version_id = ? AND target_language = ?
              AND source_content_hash = ?
            ORDER BY is_locked DESC, updated_at DESC;
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(lyricsVersionID.uuidString, at: 1, to: statement)
        try bindText(targetLanguage, at: 2, to: statement)
        try bindText(sourceContentHash, at: 3, to: statement)

        var result: [StoredTranslationVersion] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let record = try translationVersionRecord(from: statement)
            let lines = try fetchTranslationLines(versionID: record.id)
            guard validateStoredTranslation(
                record: record,
                lines: lines,
                sourceLines: source.lines
            ) else { continue }
            result.append(StoredTranslationVersion(record: record, lines: lines))
        }
        return result
    }

    public func saveTranslation(
        lyricsVersionID: UUID,
        sourceContentHash: String,
        originalLines: [String],
        draft: AITranslationDraft,
        forceNewVersion: Bool
    ) throws -> StoredTranslationVersion {
        try ensurePrepared()
        _ = forceNewVersion // Every completed explicit request gets a new ID.
        guard let source = try fetchSourceLyrics(versionID: lyricsVersionID) else {
            throw TranslationRepositoryError.sourceLyricsNotFound
        }
        guard source.hash == sourceContentHash,
              source.lines.map(\.originalText) == originalLines,
              draft.sourceContentHash == sourceContentHash else {
            throw TranslationRepositoryError.sourceContentMismatch
        }
        guard draft.lines.count == source.lines.count,
              draft.lines.map(\.index) == Array(source.lines.indices) else {
            throw TranslationRepositoryError.invalidLines("行数或 index 不匹配")
        }
        for line in draft.lines {
            let sourceText = source.lines[line.index].originalText
            let sourceBlank = sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let translationBlank = line.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard sourceBlank == translationBlank,
                  !sourceBlank || line.translation.isEmpty,
                  !line.translation.contains("\n"),
                  !line.translation.contains("\r") else {
                throw TranslationRepositoryError.invalidLines("空白行或换行规则不匹配")
            }
        }

        let now = Date()
        let versionID = UUID()
        let record = DatabaseTranslationVersionRecord(
            id: versionID,
            lyricsVersionID: lyricsVersionID,
            sourceKind: draft.sourceKind,
            targetLanguage: draft.targetLanguage,
            model: draft.model,
            baseURLHost: draft.baseURLHost,
            promptHash: draft.promptHash,
            sourceContentHash: sourceContentHash,
            createdAt: now,
            updatedAt: now,
            isMachineGenerated: draft.isMachineGenerated,
            isManuallyEdited: draft.isManuallyEdited,
            isLocked: false,
            status: .complete,
            confidence: draft.confidence
        )
        let lines = draft.lines.map {
            DatabaseTranslationLineRecord(
                translationVersionID: versionID,
                lineIndex: $0.index,
                translatedText: $0.translation
            )
        }

        try withTransaction {
            try insertTranslationVersion(record)
            for line in lines { try insertTranslationLine(line) }
        }
        return StoredTranslationVersion(record: record, lines: lines)
    }

    public func markTranslationLocked(versionID: UUID, locked: Bool) throws {
        try ensurePrepared()
        let statement = try prepare("UPDATE translation_versions SET is_locked = ?, updated_at = ? WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        try bindInt(locked ? 1 : 0, at: 1, to: statement)
        try bindDouble(Date().timeIntervalSince1970, at: 2, to: statement)
        try bindText(versionID.uuidString, at: 3, to: statement)
        try stepDone(statement)
        guard sqlite3_changes(database) > 0 else { throw TranslationRepositoryError.versionNotFound }
    }

    public func deleteTranslation(versionID: UUID) throws {
        try ensurePrepared()
        let statement = try prepare("DELETE FROM translation_versions WHERE id = ? AND is_locked = 0;")
        defer { sqlite3_finalize(statement) }
        try bindText(versionID.uuidString, at: 1, to: statement)
        try stepDone(statement)
        guard sqlite3_changes(database) > 0 else { throw TranslationRepositoryError.lockedVersion }
    }

    private struct SourceLyricsSnapshot {
        let isSynchronized: Bool
        let lines: [DatabaseLyricLineRecord]
        let hash: String
    }

    private func fetchSourceLyrics(versionID: UUID) throws -> SourceLyricsSnapshot? {
        let statement = try prepare("SELECT is_synced FROM lyrics_versions WHERE id = ? LIMIT 1;")
        defer { sqlite3_finalize(statement) }
        try bindText(versionID.uuidString, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let synchronized = sqlite3_column_int(statement, 0) != 0
        let lines = try fetchLines(versionID: versionID)
        guard !lines.isEmpty else { return nil }
        let hash = LyricsSourceContentHasher.hash(isSynchronized: synchronized, lines: lines)
        return SourceLyricsSnapshot(isSynchronized: synchronized, lines: lines, hash: hash)
    }

    private func fetchTranslationLines(versionID: UUID) throws -> [DatabaseTranslationLineRecord] {
        let statement = try prepare("""
            SELECT translation_version_id, line_index, translated_text
            FROM translation_lines WHERE translation_version_id = ? ORDER BY line_index ASC;
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(versionID.uuidString, at: 1, to: statement)
        var result: [DatabaseTranslationLineRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = columnText(statement, index: 0),
                  let id = UUID(uuidString: idText),
                  let text = columnText(statement, index: 2) else {
                throw LyricsRepositoryError.invalidData("TranslationLineRecord 字段缺失")
            }
            result.append(DatabaseTranslationLineRecord(
                translationVersionID: id,
                lineIndex: Int(sqlite3_column_int(statement, 1)),
                translatedText: text
            ))
        }
        return result
    }

    private func translationVersionRecord(from statement: OpaquePointer) throws -> DatabaseTranslationVersionRecord {
        guard let idText = columnText(statement, index: 0),
              let id = UUID(uuidString: idText),
              let lyricsIDText = columnText(statement, index: 1),
              let lyricsID = UUID(uuidString: lyricsIDText),
              let sourceKind = AITranslationSourceKind(rawValue: columnText(statement, index: 2) ?? ""),
              let target = columnText(statement, index: 3),
              let model = columnText(statement, index: 4),
              let host = columnText(statement, index: 5),
              let promptHash = columnText(statement, index: 6),
              let sourceHash = columnText(statement, index: 7),
              let status = AITranslationVersionStatus(rawValue: columnText(statement, index: 13) ?? "") else {
            throw LyricsRepositoryError.invalidData("TranslationVersionRecord 字段缺失")
        }
        return DatabaseTranslationVersionRecord(
            id: id,
            lyricsVersionID: lyricsID,
            sourceKind: sourceKind,
            targetLanguage: target,
            model: model,
            baseURLHost: host,
            promptHash: promptHash,
            sourceContentHash: sourceHash,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
            isMachineGenerated: sqlite3_column_int(statement, 10) != 0,
            isManuallyEdited: sqlite3_column_int(statement, 11) != 0,
            isLocked: sqlite3_column_int(statement, 12) != 0,
            status: status,
            confidence: sqlite3_column_double(statement, 14)
        )
    }

    private func validateStoredTranslation(
        record: DatabaseTranslationVersionRecord,
        lines: [DatabaseTranslationLineRecord],
        sourceLines: [DatabaseLyricLineRecord]
    ) -> Bool {
        guard record.status == .complete,
              lines.count == sourceLines.count,
              lines.map(\.lineIndex) == Array(sourceLines.indices) else { return false }
        return lines.allSatisfy { translation in
            let original = sourceLines[translation.lineIndex].originalText
            let sourceBlank = original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let translationBlank = translation.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return sourceBlank == translationBlank &&
                (!sourceBlank || translation.translatedText.isEmpty) &&
                !translation.translatedText.contains("\n") &&
                !translation.translatedText.contains("\r")
        }
    }

    private func insertTranslationVersion(_ record: DatabaseTranslationVersionRecord) throws {
        let statement = try prepare("""
            INSERT INTO translation_versions(
                id, lyrics_version_id, source_kind, target_language, model,
                base_url_host, prompt_hash, source_content_hash, created_at,
                updated_at, is_machine_generated, is_manually_edited,
                is_locked, status, confidence
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(record.id.uuidString, at: 1, to: statement)
        try bindText(record.lyricsVersionID.uuidString, at: 2, to: statement)
        try bindText(record.sourceKind.rawValue, at: 3, to: statement)
        try bindText(record.targetLanguage, at: 4, to: statement)
        try bindText(record.model, at: 5, to: statement)
        try bindText(record.baseURLHost, at: 6, to: statement)
        try bindText(record.promptHash, at: 7, to: statement)
        try bindText(record.sourceContentHash, at: 8, to: statement)
        try bindDouble(record.createdAt.timeIntervalSince1970, at: 9, to: statement)
        try bindDouble(record.updatedAt.timeIntervalSince1970, at: 10, to: statement)
        try bindInt(record.isMachineGenerated ? 1 : 0, at: 11, to: statement)
        try bindInt(record.isManuallyEdited ? 1 : 0, at: 12, to: statement)
        try bindInt(record.isLocked ? 1 : 0, at: 13, to: statement)
        try bindText(record.status.rawValue, at: 14, to: statement)
        try bindDouble(record.confidence, at: 15, to: statement)
        try stepDone(statement)
    }

    private func insertTranslationLine(_ record: DatabaseTranslationLineRecord) throws {
        let statement = try prepare("""
            INSERT INTO translation_lines(translation_version_id, line_index, translated_text)
            VALUES (?, ?, ?);
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(record.translationVersionID.uuidString, at: 1, to: statement)
        try bindInt(record.lineIndex, at: 2, to: statement)
        try bindText(record.translatedText, at: 3, to: statement)
        try stepDone(statement)
    }

    private func createMigrationBackup() throws {
        guard let database else { throw LyricsRepositoryError.unavailable("SQLite handle 已关闭") }
        _ = sqlite3_wal_checkpoint_v2(database, nil, SQLITE_CHECKPOINT_FULL, nil, nil)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let directory = databaseURL.deletingLastPathComponent()
        let base = databaseURL.deletingPathExtension().lastPathComponent
        var destination = directory.appendingPathComponent("\(base).pre-v2-\(formatter.string(from: Date())).sqlite3")
        if FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(base).pre-v2-\(UUID().uuidString.prefix(8)).sqlite3")
        }
        do {
            try FileManager.default.copyItem(at: databaseURL, to: destination)
        } catch {
            throw LyricsRepositoryError.unavailable("migration v2 备份失败：\(error.localizedDescription)")
        }
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

    private func scalarOptionalDouble(_ sql: String) throws -> Double? {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw lastError() }
        return columnDouble(statement, index: 0)
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
