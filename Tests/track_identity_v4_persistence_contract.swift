import Foundation
import SQLite3

private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func exec(_ database: OpaquePointer, _ sql: String) {
    var error: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(database, sql, nil, nil, &error)
    if result != SQLITE_OK {
        let message = error.map { String(cString: $0) } ?? "sqlite error \(result)"
        sqlite3_free(error)
        fatalError(message)
    }
}

private func makeV3WaterFixture(at url: URL) {
    var database: OpaquePointer?
    precondition(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK)
    defer { sqlite3_close(database) }
    guard let database else { fatalError("fixture database missing") }

    exec(database, """
        PRAGMA foreign_keys = ON;
        CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY NOT NULL, applied_at REAL NOT NULL);
        INSERT INTO schema_migrations(version, applied_at) VALUES (1, 1), (2, 2), (3, 3);
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
        PRAGMA user_version = 3;
        INSERT INTO tracks(stable_key, spotify_id, spotify_uri, isrc, title, artist_display, album, duration, created_at, updated_at)
        VALUES
          ('spotify-id:5mqkkcsrujqyakvolven0w|metadata:水曜日の約束|kawasakirio|水曜日の約束|171', '5mqkkcsrujqyakvolven0w', 'spotify:track:5mqkkcsrujqyakvolven0w', 'JP92N2518615', '水曜日の約束', 'Kawasaki.Rio', '水曜日の約束', 171.177, 1, 1),
          ('spotify-id:spotify:track:5mqkkcsrujqyakvolven0w|metadata:水曜日の約束|kawasakirio|水曜日の約束|171', 'spotify:track:5mqkkcsrujqyakvolven0w', 'spotify:track:5mqkkcsrujqyakvolven0w', NULL, '水曜日の約束', 'Kawasaki.Rio', '水曜日の約束', 171.177, 2, 2);
        """)
}

private func scalarInt(_ database: OpaquePointer, _ sql: String) -> Int {
    var statement: OpaquePointer?
    precondition(sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK)
    defer { sqlite3_finalize(statement) }
    precondition(sqlite3_step(statement) == SQLITE_ROW)
    return Int(sqlite3_column_int(statement, 0))
}

private func tableExists(_ database: OpaquePointer, _ name: String) -> Bool {
    var statement: OpaquePointer?
    precondition(sqlite3_prepare_v2(
        database,
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;",
        -1,
        &statement,
        nil
    ) == SQLITE_OK)
    defer { sqlite3_finalize(statement) }
    precondition(sqlite3_bind_text(statement, 1, name, -1, transientDestructor) == SQLITE_OK)
    return sqlite3_step(statement) == SQLITE_ROW
}

private func assertReadOnlyV4DryRun(at url: URL) throws {
    makeV3WaterFixture(at: url)
    var database: OpaquePointer?
    precondition(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
    defer { sqlite3_close(database) }
    guard let database else { fatalError("fixture database missing") }
    try DatabaseMigrator.migrate(database, allowV4Migration: false)
    precondition(scalarInt(database, "PRAGMA user_version;") == 3, "read-only v4 dry-run keeps v3")
    precondition(!tableExists(database, "track_identity_redirects"), "read-only v4 dry-run creates no tables")
}

@main
struct TrackIdentityV4PersistenceContract {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotifyLyricsIdentityV4-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try assertReadOnlyV4DryRun(
            at: root.appendingPathComponent("read-only-v3.sqlite3")
        )

        let databaseURL = root.appendingPathComponent("SpotifyLyrics.sqlite3")
        makeV3WaterFixture(at: databaseURL)

        let provenance = root.appendingPathComponent("provenance", isDirectory: true)
        let repository = SQLiteLyricsRepository(databaseURL: databaseURL, alignmentProvenanceDirectory: provenance)
        try await repository.prepare()
        let schemaVersion = try await repository.schemaVersion()
        let foreignKeysEnabled = try await repository.foreignKeysEnabled()
        precondition(schemaVersion == 4, "v4 migration")
        precondition(foreignKeysEnabled, "foreign keys")

        let canonical = "spotify-id:5mqkkcsrujqyakvolven0w|metadata:水曜日の約束|kawasakirio|水曜日の約束|171"
        let source = "spotify-id:spotify:track:5mqkkcsrujqyakvolven0w|metadata:水曜日の約束|kawasakirio|水曜日の約束|171"
        let redirectCount = try await repository.redirectCount()
        let resolvedSource = try await repository.resolveStableKey(source)
        let resolvedCanonical = try await repository.resolveStableKey(canonical)
        let family = try await repository.identityFamily(stableKey: source)
        precondition(redirectCount == 1, "only the initial Water redirect is seeded")
        precondition(resolvedSource == canonical, "Water source redirects")
        precondition(resolvedCanonical == canonical, "Water canonical remains stable")
        precondition(family == [canonical, source], "identity family")

        let reopened = SQLiteLyricsRepository(databaseURL: databaseURL, alignmentProvenanceDirectory: provenance)
        try await reopened.prepare()
        let reopenedRedirectCount = try await reopened.redirectCount()
        let reopenedSource = try await reopened.resolveStableKey(source)
        precondition(reopenedRedirectCount == 1, "v4 migration is idempotent")
        precondition(reopenedSource == canonical, "redirect survives restart")

        print("track identity v4 persistence contract passed")
    }
}
