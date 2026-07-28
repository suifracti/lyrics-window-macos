import Foundation
import SQLite3

/// Forward-only schema migration entry point. All migrations run in the
/// repository's SQLite actor, never on the app's MainActor.
public enum DatabaseMigrator {
    public static let currentVersion = 1

    public static func migrate(_ database: OpaquePointer) throws {
        do {
            try execute(database, sql: """
                CREATE TABLE IF NOT EXISTS schema_migrations (
                    version INTEGER PRIMARY KEY,
                    applied_at REAL NOT NULL
                );
                """)

            let version = try integerValue(database, sql: "PRAGMA user_version;")
            guard version <= currentVersion else {
                throw LyricsRepositoryError.unsupportedSchema(version)
            }

            if version < 1 {
                try execute(database, sql: "BEGIN IMMEDIATE TRANSACTION;")
                do {
                    try execute(database, sql: """
                        CREATE TABLE tracks (
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

                        CREATE TABLE track_aliases (
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

                        CREATE TABLE lyrics_versions (
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

                        CREATE TABLE lyric_lines (
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

                        CREATE UNIQUE INDEX lyrics_versions_dedup
                            ON lyrics_versions(track_stable_key, source, provider_source_id, content_hash);
                        CREATE INDEX lyrics_versions_best
                            ON lyrics_versions(track_stable_key, is_locked, confidence, updated_at);
                        CREATE INDEX track_aliases_lookup
                            ON track_aliases(track_stable_key, field, kind);
                        CREATE INDEX lyric_lines_version_order
                            ON lyric_lines(lyrics_version_id, line_index);
                        """)
                    try execute(database, sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (1, strftime('%s','now'));" )
                    try execute(database, sql: "PRAGMA user_version = 1;")
                    try execute(database, sql: "COMMIT;")
                } catch {
                    _ = try? execute(database, sql: "ROLLBACK;")
                    throw error
                }
            }
        } catch let error as LyricsRepositoryError {
            throw error
        } catch {
            throw LyricsRepositoryError.migrationFailed(currentVersion, error.localizedDescription)
        }
    }

    private static func execute(_ database: OpaquePointer, sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "SQLite error (result)"
            sqlite3_free(errorMessage)
            throw LyricsRepositoryError.migrationFailed(currentVersion, message)
        }
    }

    private static func integerValue(_ database: OpaquePointer, sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw LyricsRepositoryError.migrationFailed(currentVersion, "无法读取 schema version")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw LyricsRepositoryError.migrationFailed(currentVersion, "无法读取 schema version")
        }
        return Int(sqlite3_column_int(statement, 0))
    }
}
