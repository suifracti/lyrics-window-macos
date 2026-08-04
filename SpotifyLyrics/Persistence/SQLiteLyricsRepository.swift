import Foundation
import SQLite3

/// SQLite-backed lyrics cache. The actor is deliberately not MainActor:
/// sqlite3 calls, migrations, and transactions are serialized here without
/// blocking SwiftUI or Spotify playback state.
public actor SQLiteLyricsRepository: LyricsRepository, TranslationRepository, LyricsEditingRepository, ReadingRepository {
    public nonisolated let databaseURL: URL

    private var database: OpaquePointer?
    private var prepared = false
    private var redirectResolver: TrackIdentityRedirectResolver?
    private let alignmentProvenanceStore: AlignmentProvenanceStore

    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public static var defaultDatabaseURL: URL {
#if DEBUG
        // Test-only isolation for signed Debug acceptance runs. Release builds
        // always use the user Application Support database below.
        if let override = ProcessInfo.processInfo.environment["SPOTIFYLYRICS_DATABASE_PATH"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: override)
        }
#endif
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3")
    }

    public init(
        databaseURL: URL = SQLiteLyricsRepository.defaultDatabaseURL,
        alignmentProvenanceDirectory: URL = AlignmentProvenanceStore.defaultDirectory
    ) {
        self.databaseURL = databaseURL
        self.alignmentProvenanceStore = AlignmentProvenanceStore(directory: alignmentProvenanceDirectory)
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
#if DEBUG
        DebugDatabaseSafety.logRepositoryOpen(databaseURL: databaseURL)
#endif
        sqlite3_busy_timeout(handle, 3_000)
        do {
            try execute("PRAGMA foreign_keys = ON;")
            guard try scalarInt("PRAGMA foreign_keys;") == 1 else {
                throw LyricsRepositoryError.sqlite("foreign_keys 未启用")
            }
            let existingVersion = try scalarInt("PRAGMA user_version;")
            let allowV4Migration = permitsV4Migration(databaseAlreadyExisted: databaseAlreadyExisted)
            let allowV6Migration = allowV4Migration && permitsReadingSchemaMigration()
            if databaseAlreadyExisted, existingVersion > 0, existingVersion < 3 {
                try createMigrationBackup(label: "pre-v3")
            }
            if databaseAlreadyExisted,
               existingVersion >= 3,
               existingVersion < DatabaseMigrator.currentVersion,
               allowV4Migration {
                try createMigrationBackup(label: "pre-v4")
            }
            try DatabaseMigrator.migrate(
                handle,
                allowV4Migration: allowV4Migration,
                allowV6Migration: allowV6Migration
            )
            try reloadRedirectResolver()
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

        let canonicalKey = try resolvedCanonicalStableKey(identity.stableKey)
        guard let trackRecord = try fetchTrack(stableKey: canonicalKey) else {
            return nil
        }
        guard let version = try fetchBestVersion(stableKey: canonicalKey) else {
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
            ),
            alignmentProvenanceAvailability: version.source == DatabaseSourceIdentifier.identifier(for: .automaticAlignment)
                ? alignmentProvenanceStore.availability(for: version.id)
                : .unavailable
        )
    }

    public func loadAliases(stableKey: String) async throws -> [TrackAlias] {
        try loadTrackAliases(stableKey: stableKey).compactMap { record in
            guard let field = TrackAliasField(rawValue: record.field),
                  let kind = TrackAliasKind(rawValue: record.kind),
                  let script = TrackAliasScript(rawValue: record.script),
                  let source = TrackAliasSource(rawValue: record.source) else {
                return nil
            }
            let id = "db-alias:\(record.trackStableKey):\(record.field):\(record.kind):\(record.value)"
            return TrackAlias(
                id: id,
                field: field,
                kind: kind,
                value: record.value,
                language: record.language,
                script: script,
                source: source,
                confidence: record.confidence,
                isOfficial: record.isOfficial
            )
        }
    }

    public func alignmentProvenanceAvailability(versionID: UUID) async -> AlignmentProvenanceAvailability {
        alignmentProvenanceStore.availability(for: versionID)
    }

    public func saveTrackMetadata(_ metadata: TrackMetadata) throws {
        try ensurePrepared()
        let canonicalKey = try resolvedCanonicalStableKey(metadata.identity.stableKey)
        let now = Date()
        let rawTrackRecord = LyricsPersistenceMapper.trackRecord(
            track: metadata.track,
            identity: metadata.identity,
            now: now
        )
        let trackRecord = canonicalTrackRecord(rawTrackRecord, stableKey: canonicalKey)
        let aliases = LyricsPersistenceMapper.aliasRecords(metadata: metadata, now: now)
            .map { canonicalAliasRecord($0, stableKey: canonicalKey) }
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
        guard !document.lines.isEmpty,
              document.lines.contains(where: {
                  !$0.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else {
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

        let canonicalKey = try resolvedCanonicalStableKey(identity.stableKey)
        let now = Date()
        let rawTrackRecord = LyricsPersistenceMapper.trackRecord(track: track, identity: identity, now: now)
        let trackRecord = canonicalTrackRecord(rawTrackRecord, stableKey: canonicalKey)
        let versionID = UUID()
        let rawVersionRecord = LyricsPersistenceMapper.versionRecord(
            document: document,
            identity: identity,
            versionID: versionID,
            now: now
        )
        let versionRecord = canonicalVersionRecord(rawVersionRecord, stableKey: canonicalKey)
        let aliases = LyricsPersistenceMapper.aliasRecords(
            track: track,
            identity: identity,
            document: document,
            now: now
        ).map { canonicalAliasRecord($0, stableKey: canonicalKey) }
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
                stableKey: canonicalKey,
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

            if try hasLockedVersion(stableKey: canonicalKey) {
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

    public func saveAlignedVersion(_ request: AlignmentPersistenceRequest) async throws -> LyricsPersistenceSaveResult {
        try ensurePrepared()
        let canonicalKey = try resolvedCanonicalStableKey(request.identity.stableKey)
        guard request.document.identity == request.identity,
              request.report.identity == request.identity,
              TrackIdentity(track: request.track) == request.identity else {
            return LyricsPersistenceSaveResult(
                versionID: nil,
                disposition: .rejected("排轴身份与当前歌曲不一致")
            )
        }
        guard request.document.isSynchronized else {
            return LyricsPersistenceSaveResult(versionID: nil, disposition: .rejected("排轴结果必须包含有效时间轴"))
        }
        guard request.report.sourceVersionID == request.parentVersionID,
              request.report.sourceContentHash == request.parentSourceContentHash,
              !request.parentSourceContentHash.isEmpty else {
            return LyricsPersistenceSaveResult(versionID: nil, disposition: .rejected("排轴来源版本指纹不一致"))
        }
        let hasUnresolvedReportLine = request.report.lines.contains {
            $0.startTime < 0 || $0.evidence.kind == .noEvidence
        }
        guard request.report.lines.count == request.document.lines.count,
              request.report.lines.count > 0,
              !hasUnresolvedReportLine else {
            return LyricsPersistenceSaveResult(versionID: nil, disposition: .rejected("排轴结果不完整，未写入"))
        }
        if request.lockResult, request.report.lowConfidenceCount > 0 {
            return LyricsPersistenceSaveResult(versionID: nil, disposition: .rejected("低置信度排轴必须先人工修正，不能直接锁定"))
        }

        guard let parent = try fetchLyricsVersion(versionID: request.parentVersionID),
              try resolvedCanonicalStableKey(parent.trackStableKey) == canonicalKey,
              !parent.isSynced else {
            return LyricsPersistenceSaveResult(versionID: nil, disposition: .rejected("排轴父版本不存在或已经有时间轴"))
        }
        let parentLines = try fetchLines(versionID: request.parentVersionID)
        guard !parentLines.isEmpty,
              parentLines.count == request.document.lines.count else {
            return LyricsPersistenceSaveResult(versionID: nil, disposition: .rejected("排轴父版本行集合不一致"))
        }
        let parentHash = LyricsSourceContentHasher.hash(isSynchronized: false, lines: parentLines)
        guard parentHash == request.parentSourceContentHash else {
            return LyricsPersistenceSaveResult(versionID: nil, disposition: .rejected("排轴父歌词内容已经变化"))
        }

        for index in request.document.lines.indices {
            let source = parentLines[index]
            let aligned = request.document.lines[index]
            guard source.lineIndex == index,
                  source.originalText == aligned.originalText,
                  source.kanaText == aligned.kanaText,
                  source.romajiText == aligned.romajiText,
                  aligned.timestamp.isFinite,
                  aligned.timestamp >= 0,
                  aligned.timestamp <= request.report.audioDuration,
                  aligned.endTime.map({ $0.isFinite && $0 >= aligned.timestamp && $0 <= request.report.audioDuration }) ?? true else {
                return LyricsPersistenceSaveResult(versionID: nil, disposition: .rejected("排轴行内容或时间无效"))
            }
            if index > 0, aligned.timestamp < request.document.lines[index - 1].timestamp {
                return LyricsPersistenceSaveResult(versionID: nil, disposition: .rejected("排轴时间必须单调不减"))
            }
        }

        let now = Date()
        let versionID = UUID()
        let lines = LyricsPersistenceMapper.lineRecords(document: request.document, versionID: versionID)
        let sourceContentHash = LyricsSourceContentHasher.hash(isSynchronized: true, lines: lines)
        let providerSourceID = [
            "alignment", request.report.modelID, request.report.parameters.algorithmVersion,
            request.report.audioSHA256, request.parentSourceContentHash
        ].joined(separator: ":")
        let versionRecord = DatabaseLyricsVersionRecord(
            id: versionID,
            trackStableKey: canonicalKey,
            parentVersionID: request.parentVersionID,
            source: DatabaseSourceIdentifier.identifier(for: .automaticAlignment),
            providerSourceID: providerSourceID,
            language: "und",
            isSynced: true,
            rawText: request.document.lines.map(\.originalText).joined(separator: "\n"),
            contentHash: sourceContentHash,
            createdAt: now,
            updatedAt: now,
            isMachineGenerated: true,
            isManuallyEdited: true,
            isLocked: request.lockResult,
            confidence: request.report.overallConfidence
        )
        let rawTrackRecord = LyricsPersistenceMapper.trackRecord(track: request.track, identity: request.identity, now: now)
        let trackRecord = canonicalTrackRecord(rawTrackRecord, stableKey: canonicalKey)
        let aliases = LyricsPersistenceMapper.aliasRecords(
            track: request.track,
            identity: request.identity,
            document: request.document,
            now: now
        ).map { canonicalAliasRecord($0, stableKey: canonicalKey) }

        let disposition = try withTransaction {
            try upsertTrack(trackRecord)
            for alias in aliases { try insertAlias(alias) }
            if let duplicate = try findVersionID(
                stableKey: canonicalKey,
                source: versionRecord.source,
                providerSourceID: versionRecord.providerSourceID,
                contentHash: versionRecord.contentHash
            ) {
                return LyricsPersistenceSaveResult(
                    versionID: duplicate,
                    disposition: .duplicate,
                    sourceContentHash: sourceContentHash
                )
            }
            try insertVersion(versionRecord)
            for line in lines { try insertLine(line) }
            return LyricsPersistenceSaveResult(
                versionID: versionID,
                disposition: .inserted,
                sourceContentHash: sourceContentHash
            )
        }

        guard disposition.disposition == .inserted else { return disposition }
        do {
            _ = try alignmentProvenanceStore.write(
                versionID: versionID,
                parentVersionID: request.parentVersionID,
                report: request.report
            )
        } catch {
            try? deleteVersionRows(versionID: versionID)
            try? alignmentProvenanceStore.remove(versionID: versionID)
            throw LyricsRepositoryError.unavailable("排轴 provenance 保存失败：\(error.localizedDescription)")
        }
        return disposition
    }

    public func deleteLyricsVersion(versionID: UUID) async throws {
        try ensurePrepared()
        try withTransaction { try deleteVersionRows(versionID: versionID) }
        try alignmentProvenanceStore.remove(versionID: versionID)
    }

    public func markLocked(versionID: UUID, locked: Bool) throws {
        try ensurePrepared()
        if locked,
           let record = try fetchLyricsVersion(versionID: versionID),
           record.source == DatabaseSourceIdentifier.identifier(for: .automaticAlignment),
           !alignmentProvenanceStore.isLockable(versionID: versionID) {
            throw LyricsRepositoryError.invalidData("排轴 provenance 不可用或存在低置信行，不能锁定")
        }
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
        let family = try resolvedIdentityFamily(stableKey: trackStableKey)
        let statement = try prepare("SELECT COUNT(*) FROM lyrics_versions WHERE track_stable_key IN (\(placeholders(count: family.count)));")
        defer { sqlite3_finalize(statement) }
        for (index, key) in family.enumerated() {
            try bindText(key, at: Int32(index + 1), to: statement)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw lastError() }
        return Int(sqlite3_column_int(statement, 0))
    }

    /// Storage-only identity helpers used by migration and black-box
    /// acceptance tests. They intentionally expose no SQL handles.
    public func resolveStableKey(_ stableKey: String) throws -> String {
        try ensurePrepared()
        return try resolvedCanonicalStableKey(stableKey)
    }

    public func identityFamily(stableKey: String) throws -> [String] {
        try ensurePrepared()
        return try resolvedIdentityFamily(stableKey: stableKey)
    }

    public func redirectCount() throws -> Int {
        try ensurePrepared()
        guard try hasTable("track_identity_redirects") else { return 0 }
        return try scalarInt("SELECT COUNT(*) FROM track_identity_redirects;")
    }

    public func loadTrackAliases(stableKey: String) throws -> [DatabaseTrackAliasRecord] {
        try ensurePrepared()
        let family = try resolvedIdentityFamily(stableKey: stableKey)
        let statement = try prepare("""
            SELECT track_stable_key, field, kind, value, language, script,
                   source, confidence, is_official
            FROM track_aliases
            WHERE track_stable_key IN (\(placeholders(count: family.count)))
            ORDER BY CASE WHEN track_stable_key = ? THEN 0 ELSE 1 END,
                     track_stable_key, field, kind, value;
            """)
        defer { sqlite3_finalize(statement) }
        for (index, key) in family.enumerated() {
            try bindText(key, at: Int32(index + 1), to: statement)
        }
        try bindText(family[0], at: Int32(family.count + 1), to: statement)

        var result: [DatabaseTrackAliasRecord] = []
        var seen = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let key = columnText(statement, index: 0),
                  let field = columnText(statement, index: 1),
                  let kind = columnText(statement, index: 2),
                  let value = columnText(statement, index: 3),
                  let script = columnText(statement, index: 5),
                  let source = columnText(statement, index: 6) else {
                throw LyricsRepositoryError.invalidData("TrackAliasRecord 字段缺失")
            }
            let dedupeKey = [field, kind, value].joined(separator: "\u{1f}")
            guard seen.insert(dedupeKey).inserted else { continue }
            result.append(DatabaseTrackAliasRecord(
                trackStableKey: key,
                field: field,
                kind: kind,
                value: value,
                language: columnText(statement, index: 4),
                script: script,
                source: source,
                confidence: sqlite3_column_double(statement, 7),
                isOfficial: sqlite3_column_int(statement, 8) != 0
            ))
        }
        return result
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
        let versionIDs = try fetchAllVersionIDs()
        try withTransaction {
            try execute("DELETE FROM lyric_lines;")
            try execute("DELETE FROM lyrics_versions;")
        }
        for versionID in versionIDs {
            try? alignmentProvenanceStore.remove(versionID: versionID)
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
            SELECT id, lyrics_version_id, parent_version_id, source_kind, target_language, model,
                   base_url_host, prompt_hash, source_content_hash, created_at,
                   updated_at, is_machine_generated, is_manually_edited,
                   is_locked, status, confidence, engine_id, prompt_preset_id,
                   profile_id, profile_snapshot, temperature, workflow_id,
                   fallback_strategy, is_draft, is_archived
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
            confidence: draft.confidence,
            engineID: draft.engineID,
            promptPresetID: draft.promptPresetID,
            profileID: draft.profileID,
            profileSnapshot: draft.profileSnapshot,
            temperature: draft.temperature,
            workflowID: draft.workflowID,
            fallbackStrategy: draft.fallbackStrategy,
            isDraft: draft.isDraft,
            isArchived: draft.isArchived
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

    public func adoptTranslation(versionID: UUID) throws {
        try ensurePrepared()
        let statement = try prepare("UPDATE translation_versions SET is_draft = 0, is_archived = 0, updated_at = ? WHERE id = ? AND status = 'complete' AND is_locked = 0;")
        defer { sqlite3_finalize(statement) }
        try bindDouble(Date().timeIntervalSince1970, at: 1, to: statement)
        try bindText(versionID.uuidString, at: 2, to: statement)
        try stepDone(statement)
        guard sqlite3_changes(database) > 0 else { throw TranslationRepositoryError.versionNotFound }
    }

    public func archiveTranslation(versionID: UUID, archived: Bool) throws {
        try ensurePrepared()
        let statement = try prepare("UPDATE translation_versions SET is_archived = ?, updated_at = ? WHERE id = ? AND is_locked = 0;")
        defer { sqlite3_finalize(statement) }
        try bindInt(archived ? 1 : 0, at: 1, to: statement)
        try bindDouble(Date().timeIntervalSince1970, at: 2, to: statement)
        try bindText(versionID.uuidString, at: 3, to: statement)
        try stepDone(statement)
        guard sqlite3_changes(database) > 0 else { throw TranslationRepositoryError.versionNotFound }
    }

    // MARK: - ReadingRepository

    public func loadReadingVersions(
        lyricsVersionID: UUID,
        representationID: String?,
        sourceContentHash: String
    ) async throws -> [StoredReadingVersion] {
        try ensurePrepared()
        guard let source = try fetchSourceLyrics(versionID: lyricsVersionID) else {
            throw ReadingRepositoryError.sourceLyricsNotFound
        }
        guard source.hash == sourceContentHash else {
            throw ReadingRepositoryError.sourceContentMismatch
        }

        let statement = try prepare("""
            SELECT id, lyrics_version_id, source_content_hash, engine_id,
                   representation_id, source_kind, language, created_at, updated_at,
                   is_machine_generated, is_manually_edited, is_current, is_locked,
                   is_archived, parent_version_id, confidence, warning_metadata,
                   context_hash
            FROM reading_versions
            WHERE lyrics_version_id = ? AND source_content_hash = ?
              AND (? IS NULL OR representation_id = ?)
            ORDER BY is_locked DESC, is_current DESC, updated_at DESC;
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(lyricsVersionID.uuidString, at: 1, to: statement)
        try bindText(sourceContentHash, at: 2, to: statement)
        try bindText(representationID, at: 3, to: statement)
        try bindText(representationID, at: 4, to: statement)

        var result: [StoredReadingVersion] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let record = try readingVersionRecord(from: statement)
            let lines = try fetchReadingLines(versionID: record.id)
            guard validateStoredReading(record: record, lines: lines, sourceLines: source.lines) else { continue }
            result.append(StoredReadingVersion(record: record, lines: lines))
        }
        return result
    }

    public func saveReadingVersion(_ request: ReadingVersionSaveRequest) async throws -> StoredReadingVersion {
        try ensurePrepared()
        guard let source = try fetchSourceLyrics(versionID: request.record.lyricsVersionID) else {
            throw ReadingRepositoryError.sourceLyricsNotFound
        }
        guard source.hash == request.record.sourceContentHash else {
            throw ReadingRepositoryError.sourceContentMismatch
        }
        guard request.record.sourceContentHash == source.hash,
              request.lines.count == source.lines.count,
              request.lines.map(\.lineIndex) == Array(source.lines.indices) else {
            throw ReadingRepositoryError.invalidLines("行数或 index 不匹配")
        }
        for line in request.lines {
            let sourceLine = source.lines[line.lineIndex]
            let originalMatches = line.originalText == sourceLine.originalText
            let sourceBlank = sourceLine.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let readingBlank = line.readingText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            guard originalMatches,
                  sourceBlank == readingBlank,
                  !(line.readingText ?? "").contains("\n"),
                  !(line.readingText ?? "").contains("\r") else {
                throw ReadingRepositoryError.invalidLines("原文映射或空白行规则不匹配")
            }
        }
        if let existing = try fetchReadingVersion(versionID: request.record.id) {
            if existing.isLocked { throw ReadingRepositoryError.lockedVersion }
            throw ReadingRepositoryError.database("读音版本 ID 已存在；显式保存必须创建新版本")
        }

        let record = request.record
        try withTransaction {
            try insertReadingVersion(record)
            for line in request.lines {
                try insertReadingLine(line, versionID: record.id)
            }
        }
        return StoredReadingVersion(record: record, lines: request.lines)
    }

    public func adoptReadingVersion(versionID: UUID) async throws {
        try ensurePrepared()
        guard let record = try fetchReadingVersion(versionID: versionID),
              let source = try fetchSourceLyrics(versionID: record.lyricsVersionID) else {
            throw ReadingRepositoryError.versionNotFound
        }
        guard source.hash == record.sourceContentHash else { throw ReadingRepositoryError.sourceContentMismatch }
        guard !record.isArchived else { throw ReadingRepositoryError.versionNotFound }
        try withTransaction {
            let clear = try prepare("""
                UPDATE reading_versions SET is_current = 0, updated_at = ?
                WHERE lyrics_version_id = ? AND representation_id = ?;
                """)
            defer { sqlite3_finalize(clear) }
            try bindDouble(Date().timeIntervalSince1970, at: 1, to: clear)
            try bindText(record.lyricsVersionID.uuidString, at: 2, to: clear)
            try bindText(record.representationID, at: 3, to: clear)
            try stepDone(clear)

            let adopt = try prepare("""
                UPDATE reading_versions SET is_current = 1, is_archived = 0, updated_at = ?
                WHERE id = ?;
                """)
            defer { sqlite3_finalize(adopt) }
            try bindDouble(Date().timeIntervalSince1970, at: 1, to: adopt)
            try bindText(versionID.uuidString, at: 2, to: adopt)
            try stepDone(adopt)
        }
    }

    public func markReadingLocked(versionID: UUID, locked: Bool) async throws {
        try ensurePrepared()
        guard let record = try fetchReadingVersion(versionID: versionID) else {
            throw ReadingRepositoryError.versionNotFound
        }
        if !locked && record.sourceKind == .legacyImported {
            // Legacy imports may be unlocked for an explicit replacement, but
            // they remain immutable rows; the replacement gets a new ID.
        }
        let statement = try prepare("UPDATE reading_versions SET is_locked = ?, updated_at = ? WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        try bindInt(locked ? 1 : 0, at: 1, to: statement)
        try bindDouble(Date().timeIntervalSince1970, at: 2, to: statement)
        try bindText(versionID.uuidString, at: 3, to: statement)
        try stepDone(statement)
        guard sqlite3_changes(database) > 0 else { throw ReadingRepositoryError.versionNotFound }
    }

    public func archiveReadingVersion(versionID: UUID, archived: Bool) async throws {
        try ensurePrepared()
        guard let record = try fetchReadingVersion(versionID: versionID) else {
            throw ReadingRepositoryError.versionNotFound
        }
        guard !record.isLocked else { throw ReadingRepositoryError.lockedVersion }
        let statement = try prepare("""
            UPDATE reading_versions SET is_archived = ?, is_current = CASE WHEN ? = 1 THEN 0 ELSE is_current END,
                   updated_at = ? WHERE id = ?;
            """)
        defer { sqlite3_finalize(statement) }
        try bindInt(archived ? 1 : 0, at: 1, to: statement)
        try bindInt(archived ? 1 : 0, at: 2, to: statement)
        try bindDouble(Date().timeIntervalSince1970, at: 3, to: statement)
        try bindText(versionID.uuidString, at: 4, to: statement)
        try stepDone(statement)
        guard sqlite3_changes(database) > 0 else { throw ReadingRepositoryError.versionNotFound }
    }

    public func deleteReadingVersion(versionID: UUID) async throws {
        try ensurePrepared()
        guard let record = try fetchReadingVersion(versionID: versionID) else {
            throw ReadingRepositoryError.versionNotFound
        }
        guard !record.isLocked else { throw ReadingRepositoryError.lockedVersion }
        let statement = try prepare("DELETE FROM reading_versions WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        try bindText(versionID.uuidString, at: 1, to: statement)
        try stepDone(statement)
        guard sqlite3_changes(database) > 0 else { throw ReadingRepositoryError.versionNotFound }
    }

    // MARK: - LyricsEditingRepository

    public func loadEditableVersions(track: Track, identity: TrackIdentity) throws -> [StoredEditableLyricsVersion] {
        try ensurePrepared()
        let canonicalKey = try resolvedCanonicalStableKey(identity.stableKey)
        guard let trackRecord = try fetchTrack(stableKey: canonicalKey) else { return [] }
        let records = try fetchVersionRecords(stableKey: canonicalKey)
        return try records.compactMap { record in
            let lines = try fetchLines(versionID: record.id)
            guard !lines.isEmpty else { return nil }
            let readings = try fetchReadingLayers(versionID: record.id).filter(\.isLocked)
            let document = applyingLockedReadings(
                to: LyricsPersistenceMapper.document(identity: identity, track: trackRecord, version: record, lines: lines),
                readings: readings
            )
            _ = track
            return StoredEditableLyricsVersion(record: record, lines: lines, document: document, lockedReadingLayers: readings)
        }
        .sorted {
            if $0.record.isLocked != $1.record.isLocked { return $0.record.isLocked }
            return $0.record.updatedAt > $1.record.updatedAt
        }
    }

    public func loadEditableVersion(versionID: UUID, track: Track, identity: TrackIdentity) throws -> StoredEditableLyricsVersion? {
        try ensurePrepared()
        let canonicalKey = try resolvedCanonicalStableKey(identity.stableKey)
        guard let trackRecord = try fetchTrack(stableKey: canonicalKey),
              let record = try fetchLyricsVersion(versionID: versionID),
              try resolvedCanonicalStableKey(record.trackStableKey) == canonicalKey else { return nil }
        let lines = try fetchLines(versionID: versionID)
        guard !lines.isEmpty else { return nil }
        let readings = try fetchReadingLayers(versionID: versionID).filter(\.isLocked)
        let document = applyingLockedReadings(
            to: LyricsPersistenceMapper.document(identity: identity, track: trackRecord, version: record, lines: lines),
            readings: readings
        )
        _ = track
        return StoredEditableLyricsVersion(record: record, lines: lines, document: document, lockedReadingLayers: readings)
    }

    public func saveManualEdit(_ request: LyricsEditSaveRequest) throws -> LyricsEditSaveResult {
        try ensurePrepared()
        guard request.document.identity == request.identity else {
            throw LyricsEditingRepositoryError.identityMismatch
        }
        guard TrackIdentity(track: request.track) == request.identity else {
            // The editor session normally catches a track change on the
            // MainActor. Keep the repository boundary defensive as well so a
            // stale request cannot attach A's text to B's metadata.
            throw LyricsEditingRepositoryError.identityMismatch
        }
        guard !request.document.lines.isEmpty,
              request.document.lines.contains(where: {
                  !$0.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else {
            throw LyricsEditingRepositoryError.invalidDocument("不能保存空歌词")
        }
        guard !request.isNewSource || request.createLyricsVersion else {
            throw LyricsEditingRepositoryError.invalidDocument("新的人工歌词必须创建独立版本")
        }

        let canonicalKey = try resolvedCanonicalStableKey(request.identity.stableKey)

        let sourceLines: [DatabaseLyricLineRecord]
        if request.isNewSource {
            sourceLines = []
        } else {
            guard let existing = try fetchLyricsVersion(versionID: request.sourceVersionID),
                  try resolvedCanonicalStableKey(existing.trackStableKey) == canonicalKey else {
                throw LyricsEditingRepositoryError.sourceNotFound
            }
            sourceLines = try fetchLines(versionID: request.sourceVersionID)
            let sourceHash = LyricsSourceContentHasher.hash(
                isSynchronized: existing.isSynced,
                lines: sourceLines
            )
            guard sourceHash == request.sourceContentHash else {
                throw LyricsEditingRepositoryError.sourceContentMismatch
            }
        }

        let draftLines = request.document.lines.enumerated().map { index, line in
            LyricsEditorLineDraft(
                line: line,
                startTimeIsMeaningful: request.document.lineHasExplicitTiming(index)
            )
        }
        let timeline = LyricsTimelineValidator.validate(lines: draftLines, duration: request.document.duration)
        guard timeline.isSaveAllowed else {
            throw LyricsEditingRepositoryError.invalidTimeline(timeline.errors.map(\.message).joined(separator: "；"))
        }
        guard request.createLyricsVersion || request.translation != nil else {
            throw LyricsEditingRepositoryError.noChanges
        }

        let now = Date()
        let newLyricsID = request.createLyricsVersion ? UUID() : nil
        let targetDocument = request.createLyricsVersion
            ? request.document
            : LyricsDocument(
                identity: request.document.identity,
                title: request.document.title,
                artist: request.document.artist,
                album: request.document.album,
                duration: request.document.duration,
                lines: request.document.lines,
                isSynchronized: timeline.isSynchronized,
                source: request.document.source,
                confidence: request.document.confidence,
                providerSourceID: request.document.providerSourceID,
                explicitlyTimedLineIndices: request.document.explicitlyTimedLineIndices
            )
        // Translation versions are the canonical home for translations after
        // v2. Keep lyric_lines.translation_text as a read-only compatibility
        // field instead of duplicating a new manual translation there.
        let storageDocument = request.createLyricsVersion
            ? Self.documentWithoutTranslations(targetDocument)
            : targetDocument
        let targetRecords = newLyricsID.map {
            LyricsPersistenceMapper.lineRecords(document: storageDocument, versionID: $0)
        } ?? sourceLines
        let targetHash = LyricsSourceContentHasher.hash(isSynchronized: timeline.isSynchronized, lines: targetRecords)
        let rawTrackRecord = LyricsPersistenceMapper.trackRecord(
            track: request.track,
            identity: request.identity,
            now: now
        )
        let trackRecord = canonicalTrackRecord(rawTrackRecord, stableKey: canonicalKey)
        let aliases = LyricsPersistenceMapper.aliasRecords(
            track: request.track,
            identity: request.identity,
            document: request.document,
            now: now
        ).map { canonicalAliasRecord($0, stableKey: canonicalKey) }
        let parentVersionID = request.isNewSource ? nil : request.sourceVersionID

        guard let translation = request.translation else {
            try withTransaction {
                try upsertTrack(trackRecord)
                for alias in aliases { try insertAlias(alias) }
                if let newLyricsID {
                    let record = try manualLyricsVersionRecord(
                        document: storageDocument,
                        identity: request.identity,
                        versionID: newLyricsID,
                        parentVersionID: parentVersionID,
                        source: request.targetSource,
                        now: now,
                        isLocked: request.lockLyricsVersion
                    )
                    try insertVersion(canonicalVersionRecord(record, stableKey: canonicalKey))
                    for line in targetRecords { try insertLine(line) }
                    try insertReadingLayers(request.readingLayers, versionID: newLyricsID, now: now)
                }
                return ()
            }
            return LyricsEditSaveResult(
                lyricsVersion: newLyricsID.flatMap { try? loadEditableVersion(versionID: $0, track: request.track, identity: request.identity) } ?? nil,
                translationVersion: nil
            )
        }

        guard translation.lines.count == targetDocument.lines.count else {
            throw LyricsEditingRepositoryError.invalidTranslation("翻译行数与歌词不一致")
        }
        for index in targetDocument.lines.indices {
            let originalBlank = targetDocument.lines[index].originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let translationText = translation.lines[index]
            let translationBlank = translationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard originalBlank == translationBlank,
                  (!originalBlank || translationText.isEmpty),
                  !translationText.contains("\n"), !translationText.contains("\r") else {
                throw LyricsEditingRepositoryError.invalidTranslation("第 \(index + 1) 行为空白或包含换行")
            }
        }

        let translationID = UUID()
        let lyricsID = newLyricsID ?? request.sourceVersionID
        let translationRecord = DatabaseTranslationVersionRecord(
            id: translationID,
            lyricsVersionID: lyricsID,
            parentVersionID: translation.parentVersionID,
            sourceKind: .manualEdit,
            targetLanguage: translation.targetLanguage,
            model: translation.model,
            baseURLHost: translation.baseURLHost,
            promptHash: translation.promptHash,
            sourceContentHash: targetHash,
            createdAt: now,
            updatedAt: now,
            isMachineGenerated: false,
            isManuallyEdited: true,
            isLocked: translation.isLocked,
            status: .complete,
            confidence: 1
        )

        try withTransaction {
            try upsertTrack(trackRecord)
            for alias in aliases { try insertAlias(alias) }
            if let newLyricsID {
                let record = try manualLyricsVersionRecord(
                    document: storageDocument,
                    identity: request.identity,
                    versionID: newLyricsID,
                    parentVersionID: parentVersionID,
                    source: request.targetSource,
                    now: now,
                    isLocked: request.lockLyricsVersion
                )
                try insertVersion(canonicalVersionRecord(record, stableKey: canonicalKey))
                for line in targetRecords { try insertLine(line) }
                try insertReadingLayers(request.readingLayers, versionID: newLyricsID, now: now)
            }
            try insertTranslationVersion(translationRecord)
            for (index, text) in translation.lines.enumerated() {
                try insertTranslationLine(DatabaseTranslationLineRecord(
                    translationVersionID: translationID,
                    lineIndex: index,
                    translatedText: text
                ))
            }
        }

        let storedLyrics = newLyricsID.flatMap {
            try? loadEditableVersion(versionID: $0, track: request.track, identity: request.identity)
        } ?? nil
        let storedTranslation = StoredTranslationVersion(
            record: translationRecord,
            lines: translation.lines.enumerated().map {
                DatabaseTranslationLineRecord(translationVersionID: translationID, lineIndex: $0.offset, translatedText: $0.element)
            }
        )
        return LyricsEditSaveResult(lyricsVersion: storedLyrics, translationVersion: storedTranslation)
    }

    public func markLyricsVersionLocked(versionID: UUID, locked: Bool) throws {
        try markLocked(versionID: versionID, locked: locked)
    }

    private func manualLyricsVersionRecord(
        document: LyricsDocument,
        identity: TrackIdentity,
        versionID: UUID,
        parentVersionID: UUID?,
        source: LyricsSource,
        now: Date,
        isLocked: Bool
    ) throws -> DatabaseLyricsVersionRecord {
        let base = LyricsPersistenceMapper.versionRecord(
            document: document,
            identity: identity,
            versionID: versionID,
            now: now
        )
        let lines = LyricsPersistenceMapper.lineRecords(document: document, versionID: versionID)
        return DatabaseLyricsVersionRecord(
            id: base.id,
            trackStableKey: base.trackStableKey,
            parentVersionID: parentVersionID,
            source: DatabaseSourceIdentifier.identifier(for: source),
            // Every explicit manual save is a new version.  The provider/source
            // discriminator must not collide with the v1 content uniqueness key.
            providerSourceID: "\(DatabaseSourceIdentifier.identifier(for: source)):\(versionID.uuidString)",
            language: base.language,
            isSynced: document.isSynchronized,
            rawText: document.lines.map(\.originalText).joined(separator: "\n"),
            contentHash: LyricsSourceContentHasher.hash(isSynchronized: document.isSynchronized, lines: lines),
            createdAt: now,
            updatedAt: now,
            isMachineGenerated: false,
            isManuallyEdited: source == .manualEdit || source == .manualImport || source == .manualCreate,
            isLocked: isLocked,
            confidence: 1
        )
    }

    private static func documentWithoutTranslations(_ document: LyricsDocument) -> LyricsDocument {
        let lines = document.lines.map { line in
            LyricLine(
                id: line.id,
                timestamp: line.timestamp,
                originalText: line.originalText,
                endTime: line.endTime,
                translationText: nil,
                romajiText: line.romajiText,
                kanaText: line.kanaText,
                rubyTokens: line.rubyTokens
            )
        }
        return LyricsDocument(
            identity: document.identity,
            title: document.title,
            artist: document.artist,
            album: document.album,
            duration: document.duration,
            lines: lines,
            isSynchronized: document.isSynchronized,
            source: document.source,
            confidence: document.confidence,
            providerSourceID: document.providerSourceID,
            // Preserve Assist partial-timeline mask; dropping it zeroed all
            // start_time values on manual save of partially timed drafts.
            explicitlyTimedLineIndices: document.explicitlyTimedLineIndices
        )
    }

    private func fetchVersionRecords(stableKey: String) throws -> [DatabaseLyricsVersionRecord] {
        let family = try resolvedIdentityFamily(stableKey: stableKey)
        let statement = try prepare("""
            SELECT id, track_stable_key, parent_version_id, source, provider_source_id, language,
                   is_synced, raw_text, content_hash, created_at, updated_at,
                   is_machine_generated, is_manually_edited, is_locked, confidence
            FROM lyrics_versions WHERE track_stable_key IN (\(placeholders(count: family.count)))
            ORDER BY is_locked DESC, updated_at DESC;
            """)
        defer { sqlite3_finalize(statement) }
        for (index, key) in family.enumerated() {
            try bindText(key, at: Int32(index + 1), to: statement)
        }
        var result: [DatabaseLyricsVersionRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(try lyricsVersionRecord(from: statement))
        }
        return result
    }

    private func fetchReadingVersion(versionID: UUID) throws -> ReadingVersionRecord? {
        let statement = try prepare("""
            SELECT id, lyrics_version_id, source_content_hash, engine_id,
                   representation_id, source_kind, language, created_at, updated_at,
                   is_machine_generated, is_manually_edited, is_current, is_locked,
                   is_archived, parent_version_id, confidence, warning_metadata,
                   context_hash
            FROM reading_versions WHERE id = ? LIMIT 1;
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(versionID.uuidString, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try readingVersionRecord(from: statement)
    }

    private func readingVersionRecord(from statement: OpaquePointer) throws -> ReadingVersionRecord {
        guard let id = columnText(statement, index: 0).flatMap(UUID.init(uuidString:)),
              let lyricsVersionID = columnText(statement, index: 1).flatMap(UUID.init(uuidString:)),
              let sourceHash = columnText(statement, index: 2),
              let engineID = columnText(statement, index: 3),
              let representationID = columnText(statement, index: 4),
              let languageRaw = columnText(statement, index: 6) else {
            throw LyricsRepositoryError.invalidData("ReadingVersionRecord 字段缺失")
        }
        return ReadingVersionRecord(
            id: id,
            lyricsVersionID: lyricsVersionID,
            sourceContentHash: sourceHash,
            engineID: engineID,
            representationID: representationID,
            sourceKind: ReadingVersionSourceKind(rawValue: columnText(statement, index: 5) ?? "generated") ?? .generated,
            language: ReadingLanguage(rawValue: languageRaw) ?? .unknown,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8)),
            isMachineGenerated: sqlite3_column_int(statement, 9) != 0,
            isManuallyEdited: sqlite3_column_int(statement, 10) != 0,
            isCurrent: sqlite3_column_int(statement, 11) != 0,
            isLocked: sqlite3_column_int(statement, 12) != 0,
            isArchived: sqlite3_column_int(statement, 13) != 0,
            parentVersionID: columnText(statement, index: 14).flatMap(UUID.init(uuidString:)),
            confidence: sqlite3_column_double(statement, 15),
            warningMetadata: decodeWarnings(columnText(statement, index: 16)),
            contextHash: columnText(statement, index: 17) ?? ""
        )
    }

    private func fetchReadingLines(versionID: UUID) throws -> [ReadingLineResult] {
        let statement = try prepare("""
            SELECT line_index, original_text, reading_text, tokens_json, language,
                   source, confidence, warning_metadata
            FROM reading_lines WHERE reading_version_id = ? ORDER BY line_index ASC;
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(versionID.uuidString, at: 1, to: statement)
        var result: [ReadingLineResult] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let original = columnText(statement, index: 1) else {
                throw LyricsRepositoryError.invalidData("ReadingLineRecord 原文缺失")
            }
            result.append(ReadingLineResult(
                lineIndex: Int(sqlite3_column_int(statement, 0)),
                originalText: original,
                readingText: columnText(statement, index: 2),
                language: ReadingLanguage(rawValue: columnText(statement, index: 4) ?? "unknown") ?? .unknown,
                tokens: decodeTokens(columnText(statement, index: 3)),
                warnings: decodeWarnings(columnText(statement, index: 7)),
                confidence: sqlite3_column_double(statement, 6)
            ))
        }
        return result
    }

    private func validateStoredReading(
        record: ReadingVersionRecord,
        lines: [ReadingLineResult],
        sourceLines: [DatabaseLyricLineRecord]
    ) -> Bool {
        guard lines.count == sourceLines.count,
              lines.map(\.lineIndex) == Array(sourceLines.indices) else { return false }
        return lines.enumerated().allSatisfy { index, line in
            let source = sourceLines[index].originalText
            let sourceBlank = source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let readingBlank = line.readingText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            return line.originalText == source && sourceBlank == readingBlank
        }
    }

    private func insertReadingVersion(_ record: ReadingVersionRecord) throws {
        let statement = try prepare("""
            INSERT INTO reading_versions(
                id, lyrics_version_id, source_content_hash, engine_id,
                representation_id, source_kind, language, created_at, updated_at,
                is_machine_generated, is_manually_edited, is_current, is_locked,
                is_archived, parent_version_id, confidence, warning_metadata, context_hash
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(record.id.uuidString, at: 1, to: statement)
        try bindText(record.lyricsVersionID.uuidString, at: 2, to: statement)
        try bindText(record.sourceContentHash, at: 3, to: statement)
        try bindText(record.engineID, at: 4, to: statement)
        try bindText(record.representationID, at: 5, to: statement)
        try bindText(record.sourceKind.rawValue, at: 6, to: statement)
        try bindText(record.language.rawValue, at: 7, to: statement)
        try bindDouble(record.createdAt.timeIntervalSince1970, at: 8, to: statement)
        try bindDouble(record.updatedAt.timeIntervalSince1970, at: 9, to: statement)
        try bindInt(record.isMachineGenerated ? 1 : 0, at: 10, to: statement)
        try bindInt(record.isManuallyEdited ? 1 : 0, at: 11, to: statement)
        try bindInt(record.isCurrent ? 1 : 0, at: 12, to: statement)
        try bindInt(record.isLocked ? 1 : 0, at: 13, to: statement)
        try bindInt(record.isArchived ? 1 : 0, at: 14, to: statement)
        try bindText(record.parentVersionID?.uuidString, at: 15, to: statement)
        try bindDouble(record.confidence, at: 16, to: statement)
        try bindText(encodeWarnings(record.warningMetadata), at: 17, to: statement)
        try bindText(record.contextHash, at: 18, to: statement)
        try stepDone(statement)
    }

    private func insertReadingLine(_ line: ReadingLineResult, versionID: UUID) throws {
        let statement = try prepare("""
            INSERT INTO reading_lines(
                reading_version_id, line_index, original_text, reading_text,
                tokens_json, language, source, confidence, warning_metadata
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(versionID.uuidString, at: 1, to: statement)
        try bindInt(line.lineIndex, at: 2, to: statement)
        try bindText(line.originalText, at: 3, to: statement)
        try bindText(line.readingText, at: 4, to: statement)
        try bindText(encodeTokens(line.tokens), at: 5, to: statement)
        try bindText(line.language.rawValue, at: 6, to: statement)
        try bindText(line.tokens.first?.source.rawValue ?? "unknown", at: 7, to: statement)
        try bindDouble(line.confidence, at: 8, to: statement)
        try bindText(encodeWarnings(line.warnings), at: 9, to: statement)
        try stepDone(statement)
    }

    private func encodeTokens(_ tokens: [ReadingToken]) -> String {
        guard let data = try? JSONEncoder().encode(tokens) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func decodeTokens(_ value: String?) -> [ReadingToken] {
        guard let value, let data = value.data(using: .utf8),
              let tokens = try? JSONDecoder().decode([ReadingToken].self, from: data) else { return [] }
        return tokens
    }

    private func encodeWarnings(_ warnings: [ReadingWarningCode]) -> String {
        guard let data = try? JSONEncoder().encode(warnings) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func decodeWarnings(_ value: String?) -> [ReadingWarningCode] {
        guard let value, let data = value.data(using: .utf8),
              let warnings = try? JSONDecoder().decode([ReadingWarningCode].self, from: data) else { return [] }
        return warnings
    }

    private func fetchLyricsVersion(versionID: UUID) throws -> DatabaseLyricsVersionRecord? {
        let statement = try prepare("""
            SELECT id, track_stable_key, parent_version_id, source, provider_source_id, language,
                   is_synced, raw_text, content_hash, created_at, updated_at,
                   is_machine_generated, is_manually_edited, is_locked, confidence
            FROM lyrics_versions WHERE id = ? LIMIT 1;
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(versionID.uuidString, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try lyricsVersionRecord(from: statement)
    }

    private func lyricsVersionRecord(from statement: OpaquePointer) throws -> DatabaseLyricsVersionRecord {
        guard let idText = columnText(statement, index: 0),
              let id = UUID(uuidString: idText),
              let key = columnText(statement, index: 1),
              let source = columnText(statement, index: 3),
              let provider = columnText(statement, index: 4),
              let language = columnText(statement, index: 5),
              let rawText = columnText(statement, index: 7),
              let contentHash = columnText(statement, index: 8) else {
            throw LyricsRepositoryError.invalidData("LyricsVersionRecord 字段缺失")
        }
        return DatabaseLyricsVersionRecord(
            id: id,
            trackStableKey: key,
            parentVersionID: columnText(statement, index: 2).flatMap(UUID.init(uuidString:)),
            source: source,
            providerSourceID: provider,
            language: language,
            isSynced: sqlite3_column_int(statement, 6) != 0,
            rawText: rawText,
            contentHash: contentHash,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10)),
            isMachineGenerated: sqlite3_column_int(statement, 11) != 0,
            isManuallyEdited: sqlite3_column_int(statement, 12) != 0,
            isLocked: sqlite3_column_int(statement, 13) != 0,
            confidence: sqlite3_column_double(statement, 14)
        )
    }

    private func fetchReadingLayers(versionID: UUID) throws -> [DatabaseReadingLayerRecord] {
        let statement = try prepare("""
            SELECT lyrics_version_id, line_index, kana_text, romaji_text, source,
                   is_locked, created_at, updated_at
            FROM lyric_reading_layers WHERE lyrics_version_id = ? ORDER BY line_index ASC;
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(versionID.uuidString, at: 1, to: statement)
        var result: [DatabaseReadingLayerRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = columnText(statement, index: 0),
                  let id = UUID(uuidString: idText),
                  let source = columnText(statement, index: 4) else {
                throw LyricsRepositoryError.invalidData("ReadingLayerRecord 字段缺失")
            }
            result.append(DatabaseReadingLayerRecord(
                lyricsVersionID: id,
                lineIndex: Int(sqlite3_column_int(statement, 1)),
                kanaText: columnText(statement, index: 2),
                romajiText: columnText(statement, index: 3),
                source: source,
                isLocked: sqlite3_column_int(statement, 5) != 0,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7))
            ))
        }
        return result
    }

    private func applyingLockedReadings(
        to document: LyricsDocument,
        readings: [DatabaseReadingLayerRecord]
    ) -> LyricsDocument {
        guard !readings.isEmpty else { return document }
        var lines = document.lines
        for reading in readings where lines.indices.contains(reading.lineIndex) {
            let current = lines[reading.lineIndex]
            lines[reading.lineIndex] = LyricLine(
                id: current.id,
                timestamp: current.timestamp,
                originalText: current.originalText,
                endTime: current.endTime,
                translationText: current.translationText,
                romajiText: reading.romajiText ?? current.romajiText,
                kanaText: reading.kanaText ?? current.kanaText,
                rubyTokens: current.rubyTokens
            )
        }
        return LyricsDocument(
            identity: document.identity,
            title: document.title,
            artist: document.artist,
            album: document.album,
            duration: document.duration,
            lines: lines,
            isSynchronized: document.isSynchronized,
            source: document.source,
            confidence: document.confidence,
            providerSourceID: document.providerSourceID
        )
    }

    private func insertReadingLayers(
        _ layers: [LyricsReadingLayerDraft],
        versionID: UUID,
        now: Date
    ) throws {
        for layer in layers {
            guard layer.kanaText != nil || layer.romajiText != nil else { continue }
            let record = DatabaseReadingLayerRecord(
                lyricsVersionID: versionID,
                lineIndex: layer.lineIndex,
                kanaText: layer.kanaText,
                romajiText: layer.romajiText,
                source: layer.source,
                isLocked: layer.isLocked,
                createdAt: now,
                updatedAt: now
            )
            let statement = try prepare("""
                INSERT INTO lyric_reading_layers(
                    lyrics_version_id, line_index, kana_text, romaji_text, source,
                    is_locked, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """)
            defer { sqlite3_finalize(statement) }
            try bindText(record.lyricsVersionID.uuidString, at: 1, to: statement)
            try bindInt(record.lineIndex, at: 2, to: statement)
            try bindText(record.kanaText, at: 3, to: statement)
            try bindText(record.romajiText, at: 4, to: statement)
            try bindText(record.source, at: 5, to: statement)
            try bindInt(record.isLocked ? 1 : 0, at: 6, to: statement)
            try bindDouble(record.createdAt.timeIntervalSince1970, at: 7, to: statement)
            try bindDouble(record.updatedAt.timeIntervalSince1970, at: 8, to: statement)
            try stepDone(statement)
        }
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
              let sourceKind = AITranslationSourceKind(rawValue: columnText(statement, index: 3) ?? ""),
              let target = columnText(statement, index: 4),
              let model = columnText(statement, index: 5),
              let host = columnText(statement, index: 6),
              let promptHash = columnText(statement, index: 7),
              let sourceHash = columnText(statement, index: 8),
              let status = AITranslationVersionStatus(rawValue: columnText(statement, index: 14) ?? "") else {
            throw LyricsRepositoryError.invalidData("TranslationVersionRecord 字段缺失")
        }
        return DatabaseTranslationVersionRecord(
            id: id,
            lyricsVersionID: lyricsID,
            parentVersionID: columnText(statement, index: 2).flatMap(UUID.init(uuidString:)),
            sourceKind: sourceKind,
            targetLanguage: target,
            model: model,
            baseURLHost: host,
            promptHash: promptHash,
            sourceContentHash: sourceHash,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10)),
            isMachineGenerated: sqlite3_column_int(statement, 11) != 0,
            isManuallyEdited: sqlite3_column_int(statement, 12) != 0,
            isLocked: sqlite3_column_int(statement, 13) != 0,
            status: status,
            confidence: sqlite3_column_double(statement, 15),
            engineID: columnText(statement, index: 16) ?? "",
            promptPresetID: columnText(statement, index: 17) ?? "",
            profileID: columnText(statement, index: 18).flatMap(UUID.init(uuidString:)),
            profileSnapshot: columnText(statement, index: 19) ?? "",
            temperature: sqlite3_column_double(statement, 20),
            workflowID: columnText(statement, index: 21) ?? TranslationWorkflowID.classicV1.rawValue,
            fallbackStrategy: TranslationFallbackStrategy(rawValue: columnText(statement, index: 22) ?? "none") ?? .none,
            isDraft: sqlite3_column_int(statement, 23) != 0,
            isArchived: sqlite3_column_int(statement, 24) != 0
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
                id, lyrics_version_id, parent_version_id, source_kind, target_language, model,
                base_url_host, prompt_hash, source_content_hash, created_at,
                updated_at, is_machine_generated, is_manually_edited,
                is_locked, status, confidence, engine_id, prompt_preset_id,
                profile_id, profile_snapshot, temperature, workflow_id,
                fallback_strategy, is_draft, is_archived
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(record.id.uuidString, at: 1, to: statement)
        try bindText(record.lyricsVersionID.uuidString, at: 2, to: statement)
        try bindText(record.parentVersionID?.uuidString, at: 3, to: statement)
        try bindText(record.sourceKind.rawValue, at: 4, to: statement)
        try bindText(record.targetLanguage, at: 5, to: statement)
        try bindText(record.model, at: 6, to: statement)
        try bindText(record.baseURLHost, at: 7, to: statement)
        try bindText(record.promptHash, at: 8, to: statement)
        try bindText(record.sourceContentHash, at: 9, to: statement)
        try bindDouble(record.createdAt.timeIntervalSince1970, at: 10, to: statement)
        try bindDouble(record.updatedAt.timeIntervalSince1970, at: 11, to: statement)
        try bindInt(record.isMachineGenerated ? 1 : 0, at: 12, to: statement)
        try bindInt(record.isManuallyEdited ? 1 : 0, at: 13, to: statement)
        try bindInt(record.isLocked ? 1 : 0, at: 14, to: statement)
        try bindText(record.status.rawValue, at: 15, to: statement)
        try bindDouble(record.confidence, at: 16, to: statement)
        try bindText(record.engineID, at: 17, to: statement)
        try bindText(record.promptPresetID, at: 18, to: statement)
        try bindText(record.profileID?.uuidString, at: 19, to: statement)
        try bindText(record.profileSnapshot, at: 20, to: statement)
        try bindDouble(record.temperature, at: 21, to: statement)
        try bindText(record.workflowID, at: 22, to: statement)
        try bindText(record.fallbackStrategy.rawValue, at: 23, to: statement)
        try bindInt(record.isDraft ? 1 : 0, at: 24, to: statement)
        try bindInt(record.isArchived ? 1 : 0, at: 25, to: statement)
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

    private func createMigrationBackup(label: String) throws {
        guard let database else { throw LyricsRepositoryError.unavailable("SQLite handle 已关闭") }
        _ = sqlite3_wal_checkpoint_v2(database, nil, SQLITE_CHECKPOINT_FULL, nil, nil)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let directory = databaseURL.deletingLastPathComponent()
        let base = databaseURL.deletingPathExtension().lastPathComponent
        var destination = directory.appendingPathComponent("\(base).\(label)-\(formatter.string(from: Date())).sqlite3")
        if FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(base).\(label)-\(UUID().uuidString.prefix(8)).sqlite3")
        }
        do {
            try FileManager.default.copyItem(at: databaseURL, to: destination)
        } catch {
            throw LyricsRepositoryError.unavailable("migration \(label) 备份失败：\(error.localizedDescription)")
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

    private func reloadRedirectResolver() throws {
        guard database != nil else { throw LyricsRepositoryError.unavailable("SQLite handle 已关闭") }

        let keyStatement = try prepare("SELECT stable_key FROM tracks;")
        defer { sqlite3_finalize(keyStatement) }
        var knownKeys = Set<String>()
        while sqlite3_step(keyStatement) == SQLITE_ROW {
            guard let key = columnText(keyStatement, index: 0) else {
                throw LyricsRepositoryError.invalidData("Track stable_key 缺失")
            }
            knownKeys.insert(key)
        }

        var redirects: [String: String] = [:]
        if try hasTable("track_identity_redirects") {
            let redirectStatement = try prepare("""
                SELECT source_stable_key, canonical_stable_key
                FROM track_identity_redirects;
                """)
            defer { sqlite3_finalize(redirectStatement) }
            while sqlite3_step(redirectStatement) == SQLITE_ROW {
                guard let source = columnText(redirectStatement, index: 0),
                      let canonical = columnText(redirectStatement, index: 1) else {
                    throw LyricsRepositoryError.invalidData("identity redirect 字段缺失")
                }
                if let existing = redirects[source], existing != canonical {
                    throw LyricsRepositoryError.invalidData("identity redirect 冲突：\(source)")
                }
                redirects[source] = canonical
            }
        } else {
            // Keep an existing formal v3 database logically compatible while
            // v4 remains opt-in. This is read-only: no redirect table or row
            // is written until the user explicitly authorizes migration.
            redirects = DatabaseMigrator.readOnlyInitialRedirects(knownStableKeys: knownKeys)
        }

        let resolver = TrackIdentityRedirectResolver(
            redirects: redirects,
            knownStableKeys: knownKeys
        )
        for source in redirects.keys {
            _ = try resolver.resolve(source)
        }
        redirectResolver = resolver
    }

    private func hasTable(_ name: String) throws -> Bool {
        let statement = try prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;")
        defer { sqlite3_finalize(statement) }
        try bindText(name, at: 1, to: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func permitsV4Migration(databaseAlreadyExisted: Bool) -> Bool {
        if ProcessInfo.processInfo.environment["SPOTIFYLYRICS_ALLOW_V4_MIGRATION"] == "1" {
            return true
        }
        // Explicit Debug/test database overrides are intentionally treated as
        // disposable copies. The formal Application Support database remains
        // v3 and read-only until migration is explicitly enabled.
        if let override = ProcessInfo.processInfo.environment["SPOTIFYLYRICS_DATABASE_PATH"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        let productionURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3")
            .standardizedFileURL
        if databaseAlreadyExisted, databaseURL.standardizedFileURL == productionURL {
            return false
        }
        return true
    }

    private func permitsReadingSchemaMigration() -> Bool {
        // Reading v6 is deliberately a disposable validation schema. The
        // formal Application Support database remains on its accepted v4
        // schema until a separately authorized migration task exists.
        let productionURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3")
            .standardizedFileURL
        return databaseURL.standardizedFileURL != productionURL
    }

    private func resolvedCanonicalStableKey(_ stableKey: String) throws -> String {
        guard let redirectResolver else { return stableKey }
        return try redirectResolver.resolve(stableKey)
    }

    private func resolvedIdentityFamily(stableKey: String) throws -> [String] {
        guard let redirectResolver else { return [stableKey] }
        return try redirectResolver.identityFamily(for: stableKey)
    }

    private func placeholders(count: Int) -> String {
        Array(repeating: "?", count: max(1, count)).joined(separator: ",")
    }

    private func canonicalTrackRecord(_ record: DatabaseTrackRecord, stableKey: String) -> DatabaseTrackRecord {
        guard record.stableKey != stableKey else { return record }
        return DatabaseTrackRecord(
            stableKey: stableKey,
            spotifyID: record.spotifyID,
            spotifyURI: record.spotifyURI,
            isrc: record.isrc,
            title: record.title,
            artistDisplay: record.artistDisplay,
            album: record.album,
            duration: record.duration,
            artworkURL: record.artworkURL,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    private func canonicalAliasRecord(_ record: DatabaseTrackAliasRecord, stableKey: String) -> DatabaseTrackAliasRecord {
        DatabaseTrackAliasRecord(
            trackStableKey: stableKey,
            field: record.field,
            kind: record.kind,
            value: record.value,
            language: record.language,
            script: record.script,
            source: record.source,
            confidence: record.confidence,
            isOfficial: record.isOfficial
        )
    }

    private func canonicalVersionRecord(_ record: DatabaseLyricsVersionRecord, stableKey: String) -> DatabaseLyricsVersionRecord {
        guard record.trackStableKey != stableKey else { return record }
        return DatabaseLyricsVersionRecord(
            id: record.id,
            trackStableKey: stableKey,
            parentVersionID: record.parentVersionID,
            source: record.source,
            providerSourceID: record.providerSourceID,
            language: record.language,
            isSynced: record.isSynced,
            rawText: record.rawText,
            contentHash: record.contentHash,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            isMachineGenerated: record.isMachineGenerated,
            isManuallyEdited: record.isManuallyEdited,
            isLocked: record.isLocked,
            confidence: record.confidence
        )
    }

    private func upsertTrack(_ record: DatabaseTrackRecord) throws {
        let statement = try prepare("""
            INSERT INTO tracks(
                stable_key, spotify_id, spotify_uri, isrc, title, artist_display,
                album, duration, artwork_url, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(stable_key) DO UPDATE SET
                spotify_id = CASE WHEN tracks.spotify_id IS NULL OR length(trim(tracks.spotify_id)) = 0 THEN excluded.spotify_id ELSE tracks.spotify_id END,
                spotify_uri = CASE WHEN tracks.spotify_uri IS NULL OR length(trim(tracks.spotify_uri)) = 0 THEN excluded.spotify_uri ELSE tracks.spotify_uri END,
                isrc = CASE WHEN tracks.isrc IS NULL OR length(trim(tracks.isrc)) = 0 THEN excluded.isrc ELSE tracks.isrc END,
                title = CASE WHEN length(trim(tracks.title)) = 0 THEN excluded.title ELSE tracks.title END,
                artist_display = CASE WHEN length(trim(tracks.artist_display)) = 0 THEN excluded.artist_display ELSE tracks.artist_display END,
                album = CASE WHEN length(trim(tracks.album)) = 0 THEN excluded.album ELSE tracks.album END,
                duration = CASE WHEN tracks.duration <= 0 THEN excluded.duration ELSE tracks.duration END,
                artwork_url = CASE WHEN tracks.artwork_url IS NULL OR length(trim(tracks.artwork_url)) = 0 THEN excluded.artwork_url ELSE tracks.artwork_url END,
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
                id, track_stable_key, parent_version_id, source, provider_source_id, language,
                is_synced, raw_text, content_hash, created_at, updated_at,
                is_machine_generated, is_manually_edited, is_locked, confidence
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(record.id.uuidString, at: 1, to: statement)
        try bindText(record.trackStableKey, at: 2, to: statement)
        try bindText(record.parentVersionID?.uuidString, at: 3, to: statement)
        try bindText(record.source, at: 4, to: statement)
        try bindText(record.providerSourceID, at: 5, to: statement)
        try bindText(record.language, at: 6, to: statement)
        try bindInt(record.isSynced ? 1 : 0, at: 7, to: statement)
        try bindText(record.rawText, at: 8, to: statement)
        try bindText(record.contentHash, at: 9, to: statement)
        try bindDouble(record.createdAt.timeIntervalSince1970, at: 10, to: statement)
        try bindDouble(record.updatedAt.timeIntervalSince1970, at: 11, to: statement)
        try bindInt(record.isMachineGenerated ? 1 : 0, at: 12, to: statement)
        try bindInt(record.isManuallyEdited ? 1 : 0, at: 13, to: statement)
        try bindInt(record.isLocked ? 1 : 0, at: 14, to: statement)
        try bindDouble(record.confidence, at: 15, to: statement)
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

    private func deleteVersionRows(versionID: UUID) throws {
        let statement = try prepare("DELETE FROM lyrics_versions WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        try bindText(versionID.uuidString, at: 1, to: statement)
        try stepDone(statement)
        guard sqlite3_changes(database) > 0 else {
            throw LyricsRepositoryError.invalidData("找不到歌词版本 \(versionID.uuidString)")
        }
    }

    private func fetchAllVersionIDs() throws -> [UUID] {
        let statement = try prepare("SELECT id FROM lyrics_versions;")
        defer { sqlite3_finalize(statement) }
        var result: [UUID] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = columnText(statement, index: 0),
                  let id = UUID(uuidString: text) else {
                throw LyricsRepositoryError.invalidData("歌词版本 UUID 无效")
            }
            result.append(id)
        }
        return result
    }

    private func findVersionID(
        stableKey: String,
        source: String,
        providerSourceID: String,
        contentHash: String
    ) throws -> UUID? {
        let family = try resolvedIdentityFamily(stableKey: stableKey)
        let statement = try prepare("""
            SELECT id FROM lyrics_versions
            WHERE track_stable_key IN (\(placeholders(count: family.count))) AND source = ?
              AND provider_source_id = ? AND content_hash = ?
            LIMIT 1;
            """)
        defer { sqlite3_finalize(statement) }
        for (index, key) in family.enumerated() {
            try bindText(key, at: Int32(index + 1), to: statement)
        }
        let offset = Int32(family.count)
        try bindText(source, at: offset + 1, to: statement)
        try bindText(providerSourceID, at: offset + 2, to: statement)
        try bindText(contentHash, at: offset + 3, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let value = columnText(statement, index: 0), let id = UUID(uuidString: value) else {
            throw LyricsRepositoryError.invalidData("歌词版本 UUID 无效")
        }
        return id
    }

    private func hasLockedVersion(stableKey: String) throws -> Bool {
        let family = try resolvedIdentityFamily(stableKey: stableKey)
        let statement = try prepare("SELECT 1 FROM lyrics_versions WHERE track_stable_key IN (\(placeholders(count: family.count))) AND is_locked = 1 LIMIT 1;")
        defer { sqlite3_finalize(statement) }
        for (index, key) in family.enumerated() {
            try bindText(key, at: Int32(index + 1), to: statement)
        }
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
        let family = try resolvedIdentityFamily(stableKey: stableKey)
        let statement = try prepare("""
            SELECT id, track_stable_key, source, provider_source_id, language,
                   parent_version_id, is_synced, raw_text, content_hash, created_at, updated_at,
                   is_machine_generated, is_manually_edited, is_locked, confidence
            FROM lyrics_versions
            WHERE track_stable_key IN (\(placeholders(count: family.count)))
              AND (is_locked = 1 OR confidence >= ?)
            -- A confirmed alignment is a user-selected child version. Keep it
            -- ahead of its plain-text parent after the lock decision, while
            -- preserving the existing confidence filter for untrusted rows.
            ORDER BY is_locked DESC,
                     CASE WHEN source = 'automaticAlignment' THEN 1 ELSE 0 END DESC,
                     updated_at DESC,
                     confidence DESC
            LIMIT 1;
        """)
        defer { sqlite3_finalize(statement) }
        for (index, key) in family.enumerated() {
            try bindText(key, at: Int32(index + 1), to: statement)
        }
        try bindDouble(LyricsMatcher.highConfidenceThreshold, at: Int32(family.count + 1), to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let idText = columnText(statement, index: 0),
              let id = UUID(uuidString: idText),
              let key = columnText(statement, index: 1),
              let source = columnText(statement, index: 2),
              let provider = columnText(statement, index: 3),
              let language = columnText(statement, index: 4),
              let rawText = columnText(statement, index: 7),
              let contentHash = columnText(statement, index: 8) else {
            throw LyricsRepositoryError.invalidData("LyricsVersionRecord 字段缺失")
        }
        return DatabaseLyricsVersionRecord(
            id: id,
            trackStableKey: key,
            parentVersionID: columnText(statement, index: 5).flatMap(UUID.init(uuidString:)),
            source: source,
            providerSourceID: provider,
            language: language,
            isSynced: sqlite3_column_int(statement, 6) != 0,
            rawText: rawText,
            contentHash: contentHash,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10)),
            isMachineGenerated: sqlite3_column_int(statement, 11) != 0,
            isManuallyEdited: sqlite3_column_int(statement, 12) != 0,
            isLocked: sqlite3_column_int(statement, 13) != 0,
            confidence: sqlite3_column_double(statement, 14)
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
