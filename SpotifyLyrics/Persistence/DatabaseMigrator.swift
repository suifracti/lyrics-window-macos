import Foundation
import SQLite3

/// Forward-only SQLite schema migrations. The repository calls this from its
/// actor, so no migration work runs on MainActor.
public enum DatabaseMigrator {
    public static let currentVersion = 2

    public static func migrate(_ database: OpaquePointer) throws {
        do {
            try execute(database, sql: """
                CREATE TABLE IF NOT EXISTS schema_migrations (
                    version INTEGER PRIMARY KEY,
                    applied_at REAL NOT NULL
                );
                """)

            var version = try integerValue(database, sql: "PRAGMA user_version;")
            guard version <= currentVersion else {
                throw LyricsRepositoryError.unsupportedSchema(version)
            }

            if version < 1 {
                try migrateV1(database)
                version = 1
            }
            if version < 2 {
                try migrateV2(database)
                version = 2
            }
        } catch let error as LyricsRepositoryError {
            // A corrupt/partially readable SQLite file must be reported as a
            // migration failure, not leaked as a generic database error. This
            // gives the caller one actionable startup failure path while still
            // preserving an explicitly unsupported future schema version.
            switch error {
            case .migrationFailed, .unsupportedSchema:
                throw error
            default:
                throw LyricsRepositoryError.migrationFailed(currentVersion, error.localizedDescription)
            }
        } catch {
            throw LyricsRepositoryError.migrationFailed(currentVersion, error.localizedDescription)
        }
    }

    private static func migrateV1(_ database: OpaquePointer) throws {
        try execute(database, sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            try execute(database, sql: """
                CREATE TABLE IF NOT EXISTS tracks (
                    stable_key TEXT PRIMARY KEY NOT NULL,
                    spotify_id TEXT,
                    spotify_uri TEXT,
                    isrc TEXT,
                    title TEXT NOT NULL,
                    artist_display TEXT NOT NULL,
                    album TEXT NOT NULL,
                    duration REAL NOT NULL DEFAULT 0,
                    artwork_url TEXT,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );

                CREATE TABLE IF NOT EXISTS track_aliases (
                    track_stable_key TEXT NOT NULL,
                    field TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    value TEXT NOT NULL,
                    language TEXT,
                    script TEXT NOT NULL,
                    source TEXT NOT NULL,
                    confidence REAL NOT NULL,
                    is_official INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (track_stable_key, field, kind, value),
                    FOREIGN KEY (track_stable_key) REFERENCES tracks(stable_key) ON DELETE CASCADE
                );

                CREATE TABLE IF NOT EXISTS lyrics_versions (
                    id TEXT PRIMARY KEY NOT NULL,
                    track_stable_key TEXT NOT NULL,
                    source TEXT NOT NULL,
                    provider_source_id TEXT NOT NULL DEFAULT '',
                    language TEXT NOT NULL DEFAULT 'und',
                    is_synced INTEGER NOT NULL DEFAULT 0,
                    raw_text TEXT NOT NULL,
                    content_hash TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    is_machine_generated INTEGER NOT NULL DEFAULT 0,
                    is_manually_edited INTEGER NOT NULL DEFAULT 0,
                    is_locked INTEGER NOT NULL DEFAULT 0,
                    confidence REAL NOT NULL,
                    FOREIGN KEY (track_stable_key) REFERENCES tracks(stable_key) ON DELETE CASCADE
                );

                CREATE TABLE IF NOT EXISTS lyric_lines (
                    lyrics_version_id TEXT NOT NULL,
                    line_index INTEGER NOT NULL,
                    start_time REAL,
                    end_time REAL,
                    original_text TEXT NOT NULL,
                    kana_text TEXT,
                    romaji_text TEXT,
                    translation_text TEXT,
                    PRIMARY KEY (lyrics_version_id, line_index),
                    FOREIGN KEY (lyrics_version_id) REFERENCES lyrics_versions(id) ON DELETE CASCADE
                );

                CREATE UNIQUE INDEX IF NOT EXISTS lyrics_versions_dedup
                    ON lyrics_versions(track_stable_key, source, provider_source_id, content_hash);
                CREATE INDEX IF NOT EXISTS lyrics_versions_best
                    ON lyrics_versions(track_stable_key, is_locked, confidence, updated_at);
                CREATE INDEX IF NOT EXISTS track_aliases_lookup
                    ON track_aliases(track_stable_key, field, kind);
                CREATE INDEX IF NOT EXISTS lyric_lines_version_order
                    ON lyric_lines(lyrics_version_id, line_index);
                """)
            try execute(database, sql: "INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (1, strftime('%s','now'));")
            try execute(database, sql: "PRAGMA user_version = 1;")
            try execute(database, sql: "COMMIT;")
        } catch {
            _ = try? execute(database, sql: "ROLLBACK;")
            throw error
        }
    }

    private struct LegacyGroup {
        let versionID: String
        let isSynchronized: Bool
        let lines: [DatabaseLyricLineRecord]
    }

    private static func migrateV2(_ database: OpaquePointer) throws {
        try execute(database, sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            try execute(database, sql: """
                CREATE TABLE IF NOT EXISTS translation_versions (
                    id TEXT PRIMARY KEY NOT NULL,
                    lyrics_version_id TEXT NOT NULL,
                    source_kind TEXT NOT NULL,
                    target_language TEXT NOT NULL,
                    model TEXT NOT NULL DEFAULT '',
                    base_url_host TEXT NOT NULL DEFAULT '',
                    prompt_hash TEXT NOT NULL DEFAULT '',
                    source_content_hash TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    is_machine_generated INTEGER NOT NULL DEFAULT 0,
                    is_manually_edited INTEGER NOT NULL DEFAULT 0,
                    is_locked INTEGER NOT NULL DEFAULT 0,
                    status TEXT NOT NULL,
                    confidence REAL NOT NULL DEFAULT 0,
                    FOREIGN KEY (lyrics_version_id) REFERENCES lyrics_versions(id) ON DELETE CASCADE
                );

                CREATE TABLE IF NOT EXISTS translation_lines (
                    translation_version_id TEXT NOT NULL,
                    line_index INTEGER NOT NULL,
                    translated_text TEXT NOT NULL,
                    PRIMARY KEY (translation_version_id, line_index),
                    FOREIGN KEY (translation_version_id) REFERENCES translation_versions(id) ON DELETE CASCADE
                );

                CREATE INDEX IF NOT EXISTS translation_versions_lookup
                    ON translation_versions(lyrics_version_id, target_language, source_content_hash, status, updated_at);
                CREATE INDEX IF NOT EXISTS translation_versions_selection
                    ON translation_versions(lyrics_version_id, is_locked, updated_at);
                CREATE INDEX IF NOT EXISTS translation_lines_version_order
                    ON translation_lines(translation_version_id, line_index);
                """)

            for group in try legacyGroups(database) {
                guard !group.lines.isEmpty else { continue }
                let sourceHash = LyricsSourceContentHasher.hash(
                    isSynchronized: group.isSynchronized,
                    lines: group.lines
                )
                guard try !translationVersionExists(
                    database,
                    lyricsVersionID: group.versionID,
                    sourceContentHash: sourceHash
                ) else { continue }

                let versionID = UUID().uuidString
                let complete = group.lines.allSatisfy { row in
                    let originalBlank = row.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let translationBlank = row.translationText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
                    return originalBlank == translationBlank
                }
                try insertTranslationVersion(
                    database,
                    id: versionID,
                    lyricsVersionID: group.versionID,
                    sourceHash: sourceHash,
                    status: complete ? "complete" : "incomplete"
                )
                for row in group.lines {
                    try insertTranslationLine(
                        database,
                        versionID: versionID,
                        index: row.lineIndex,
                        text: row.translationText ?? ""
                    )
                }
            }

            try execute(database, sql: "INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (2, strftime('%s','now'));")
            try execute(database, sql: "PRAGMA user_version = 2;")
            try execute(database, sql: "COMMIT;")
        } catch {
            _ = try? execute(database, sql: "ROLLBACK;")
            throw error
        }
    }

    private static func legacyGroups(_ database: OpaquePointer) throws -> [LegacyGroup] {
        let statement = try prepare(database, sql: """
            SELECT lv.id, lv.is_synced,
                   ll.line_index, ll.start_time, ll.end_time,
                   ll.original_text, ll.kana_text, ll.romaji_text, ll.translation_text
            FROM lyrics_versions AS lv
            JOIN lyric_lines AS ll ON ll.lyrics_version_id = lv.id
            WHERE EXISTS (
                SELECT 1 FROM lyric_lines AS nonempty
                WHERE nonempty.lyrics_version_id = lv.id
                  AND nonempty.translation_text IS NOT NULL
                  AND length(trim(nonempty.translation_text)) > 0
            )
            ORDER BY lv.id, ll.line_index;
            """)
        defer { sqlite3_finalize(statement) }

        var grouped: [LegacyGroup] = []
        var currentID: String?
        var current: [DatabaseLyricLineRecord] = []
        var currentSynchronized = false
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw sqliteError(database) }
            guard let versionID = columnText(statement, index: 0),
                  let original = columnText(statement, index: 5) else {
                throw LyricsRepositoryError.migrationFailed(2, "legacy lyric line 字段缺失")
            }
            if currentID != versionID {
                if let currentID, !current.isEmpty {
                    grouped.append(LegacyGroup(versionID: currentID, isSynchronized: currentSynchronized, lines: current))
                }
                current = []
                currentID = versionID
                currentSynchronized = sqlite3_column_int(statement, 1) != 0
            }
            let line = DatabaseLyricLineRecord(
                lyricsVersionID: UUID(uuidString: versionID) ?? UUID(),
                lineIndex: Int(sqlite3_column_int(statement, 2)),
                startTime: columnDouble(statement, index: 3),
                endTime: columnDouble(statement, index: 4),
                originalText: original,
                kanaText: columnText(statement, index: 6),
                romajiText: columnText(statement, index: 7),
                translationText: columnText(statement, index: 8)
            )
            current.append(line)
        }
        if let currentID, !current.isEmpty {
            grouped.append(LegacyGroup(versionID: currentID, isSynchronized: currentSynchronized, lines: current))
        }
        return grouped
    }

    private static func translationVersionExists(
        _ database: OpaquePointer,
        lyricsVersionID: String,
        sourceContentHash: String
    ) throws -> Bool {
        let statement = try prepare(database, sql: """
            SELECT 1 FROM translation_versions
            WHERE lyrics_version_id = ? AND source_kind = 'legacyImported'
              AND target_language = 'und' AND source_content_hash = ? LIMIT 1;
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(lyricsVersionID, at: 1, to: statement)
        try bindText(sourceContentHash, at: 2, to: statement)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func insertTranslationVersion(
        _ database: OpaquePointer,
        id: String,
        lyricsVersionID: String,
        sourceHash: String,
        status: String
    ) throws {
        let statement = try prepare(database, sql: """
            INSERT INTO translation_versions(
                id, lyrics_version_id, source_kind, target_language, model,
                base_url_host, prompt_hash, source_content_hash, created_at,
                updated_at, is_machine_generated, is_manually_edited,
                is_locked, status, confidence
            ) VALUES (?, ?, 'legacyImported', 'und', '', '', '', ?, ?, ?, 0, 0, 0, ?, 0.5);
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(id, at: 1, to: statement)
        try bindText(lyricsVersionID, at: 2, to: statement)
        try bindText(sourceHash, at: 3, to: statement)
        try bindDouble(Date().timeIntervalSince1970, at: 4, to: statement)
        try bindDouble(Date().timeIntervalSince1970, at: 5, to: statement)
        try bindText(status, at: 6, to: statement)
        try stepDone(database, statement: statement)
    }

    private static func insertTranslationLine(
        _ database: OpaquePointer,
        versionID: String,
        index: Int,
        text: String
    ) throws {
        let statement = try prepare(database, sql: """
            INSERT INTO translation_lines(translation_version_id, line_index, translated_text)
            VALUES (?, ?, ?);
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(versionID, at: 1, to: statement)
        try bindInt(index, at: 2, to: statement)
        try bindText(text, at: 3, to: statement)
        try stepDone(database, statement: statement)
    }

    private static func execute(_ database: OpaquePointer, sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "SQLite error (result \(result))"
            sqlite3_free(errorMessage)
            throw LyricsRepositoryError.migrationFailed(currentVersion, message)
        }
    }

    private static func integerValue(_ database: OpaquePointer, sql: String) throws -> Int {
        let statement = try prepare(database, sql: sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw LyricsRepositoryError.migrationFailed(currentVersion, "无法读取 schema version")
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private static func prepare(_ database: OpaquePointer, sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw sqliteError(database)
        }
        return statement
    }

    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func bindText(_ value: String, at index: Int32, to statement: OpaquePointer) throws {
        let result = value.withCString { sqlite3_bind_text(statement, index, $0, -1, transientDestructor) }
        guard result == SQLITE_OK else { throw LyricsRepositoryError.sqlite("绑定文本失败") }
    }

    private static func bindInt(_ value: Int, at index: Int32, to statement: OpaquePointer) throws {
        guard sqlite3_bind_int(statement, index, Int32(value)) == SQLITE_OK else {
            throw LyricsRepositoryError.sqlite("绑定整数失败")
        }
    }

    private static func bindDouble(_ value: Double, at index: Int32, to statement: OpaquePointer) throws {
        guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
            throw LyricsRepositoryError.sqlite("绑定数字失败")
        }
    }

    private static func stepDone(_ database: OpaquePointer, statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw sqliteError(database) }
    }

    private static func columnText(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private static func columnDouble(_ statement: OpaquePointer, index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }

    private static func sqliteError(_ database: OpaquePointer) -> LyricsRepositoryError {
        LyricsRepositoryError.migrationFailed(currentVersion, String(cString: sqlite3_errmsg(database)))
    }
}
