import Foundation
import SQLite3


private func makeTrack() -> Track {
    Track(
        title: "Contract Song",
        artist: "Contract Artist",
        album: "Contract Album",
        duration: 120,
        spotifyId: "contract-track",
        spotifyURL: URL(string: "spotify:track:contract-track")
    )
}

private func makeDocument(track: Track, identity: TrackIdentity) -> LyricsDocument {
    LyricsDocument(
        identity: identity,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration,
        lines: [
            LyricLine(timestamp: 0, originalText: "第一行", romajiText: "daiichi gyou", kanaText: "だいいちぎょう"),
            LyricLine(timestamp: 3, originalText: "", romajiText: nil, kanaText: nil),
            LyricLine(timestamp: 6, originalText: "第三行", romajiText: "daisan gyou", kanaText: "だいさんぎょう")
        ],
        isSynchronized: true,
        source: .lrclib,
        confidence: 0.99,
        providerSourceID: "contract-source"
    )
}

private func execute(_ db: OpaquePointer, _ sql: String) {
    var message: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(db, sql, nil, nil, &message)
    let errorText = message.map { String(cString: $0) } ?? "sqlite error"
    precondition(result == SQLITE_OK, errorText)
    sqlite3_free(message)
}

private func makeV1Database(at url: URL, stableKey: String) {
    var db: OpaquePointer?
    precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    guard let db else { fatalError("db") }
    execute(db, """
        CREATE TABLE tracks(stable_key TEXT PRIMARY KEY, spotify_id TEXT, spotify_uri TEXT, isrc TEXT, title TEXT, artist_display TEXT, album TEXT, duration REAL, artwork_url TEXT, created_at REAL, updated_at REAL);
        CREATE TABLE track_aliases(track_stable_key TEXT, field TEXT, kind TEXT, value TEXT, language TEXT, script TEXT, source TEXT, confidence REAL, is_official INTEGER, PRIMARY KEY(track_stable_key, field, kind, value));
        CREATE TABLE lyrics_versions(id TEXT PRIMARY KEY, track_stable_key TEXT, source TEXT, provider_source_id TEXT, language TEXT, is_synced INTEGER, raw_text TEXT, content_hash TEXT, created_at REAL, updated_at REAL, is_machine_generated INTEGER, is_manually_edited INTEGER, is_locked INTEGER, confidence REAL);
        CREATE TABLE lyric_lines(lyrics_version_id TEXT, line_index INTEGER, start_time REAL, end_time REAL, original_text TEXT, kana_text TEXT, romaji_text TEXT, translation_text TEXT, PRIMARY KEY(lyrics_version_id, line_index));
        PRAGMA user_version = 1;
        """)
    let now = Date().timeIntervalSince1970
    execute(db, "INSERT INTO tracks VALUES('\(stableKey)','legacy-id','spotify:track:legacy-id',NULL,'Legacy','Artist','Album',90,NULL,\(now),\(now));")
    execute(db, "INSERT INTO lyrics_versions VALUES('00000000-0000-0000-0000-000000000001','\(stableKey)','lrclib','legacy','ja',1,'原文','legacy-hash',\(now),\(now),0,0,0,0.9);")
    execute(db, "INSERT INTO lyric_lines VALUES('00000000-0000-0000-0000-000000000001',0,0,2,'原文','げんぶん','genbun','译文');")
}

@main
struct TranslationPersistenceContract {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotifyLyricsTranslationContract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let url = root.appendingPathComponent("SpotifyLyrics.sqlite3")
        let repository = SQLiteLyricsRepository(databaseURL: url)
        try await repository.prepare()
        let schemaVersion = try await repository.schemaVersion()
        precondition(schemaVersion == DatabaseMigrator.currentVersion)
        let hasUniqueIndex = try await repository.hasUniqueTranslationVersionIndex()
        precondition(hasUniqueIndex == false)

        let track = makeTrack()
        let identity = TrackIdentity(track: track)
        let document = makeDocument(track: track, identity: identity)
        let savedLyrics = try await repository.save(track: track, identity: identity, document: document)
        guard case .inserted = savedLyrics.disposition, let lyricsVersionID = savedLyrics.versionID,
              let sourceHash = savedLyrics.sourceContentHash else { fatalError("lyrics source not saved") }

        let config = AITranslationConfiguration(baseURL: "https://proxy.example/api/openai/v1", model: "test-model")
        let lines = [
            AITranslationLine(index: 0, translation: "第一行译文"),
            AITranslationLine(index: 1, translation: ""),
            AITranslationLine(index: 2, translation: "第三行译文")
        ]
        let draft = AITranslationDraft(
            lines: lines,
            targetLanguage: config.targetLanguage,
            model: config.model,
            baseURLHost: "proxy.example",
            promptHash: "prompt-contract",
            sourceContentHash: sourceHash
        )
        let first = try await repository.saveTranslation(
            lyricsVersionID: lyricsVersionID,
            sourceContentHash: sourceHash,
            originalLines: document.lines.map(\.originalText),
            draft: draft,
            forceNewVersion: false
        )
        let second = try await repository.saveTranslation(
            lyricsVersionID: lyricsVersionID,
            sourceContentHash: sourceHash,
            originalLines: document.lines.map(\.originalText),
            draft: draft,
            forceNewVersion: true
        )
        precondition(first.record.id != second.record.id, "explicit retranslation must create a new version")
        let versions = try await repository.loadTranslationVersions(
            lyricsVersionID: lyricsVersionID,
            targetLanguage: config.targetLanguage,
            sourceContentHash: sourceHash
        )
        precondition(versions.count == 2)
        precondition(versions.allSatisfy { $0.lines.count == 3 })

        do {
            _ = try await repository.saveTranslation(
                lyricsVersionID: lyricsVersionID,
                sourceContentHash: "stale-hash",
                originalLines: document.lines.map(\.originalText),
                draft: draft,
                forceNewVersion: true
            )
            fatalError("stale source accepted")
        } catch TranslationRepositoryError.sourceContentMismatch { }

        do {
            let invalid = AITranslationDraft(
                lines: [AITranslationLine(index: 0, translation: "")],
                targetLanguage: config.targetLanguage,
                model: config.model,
                baseURLHost: "proxy.example",
                promptHash: "bad",
                sourceContentHash: sourceHash
            )
            _ = try await repository.saveTranslation(
                lyricsVersionID: lyricsVersionID,
                sourceContentHash: sourceHash,
                originalLines: document.lines.map(\.originalText),
                draft: invalid,
                forceNewVersion: true
            )
            fatalError("invalid draft persisted")
        } catch TranslationRepositoryError.invalidLines { }
        let afterInvalid = try await repository.loadTranslationVersions(
            lyricsVersionID: lyricsVersionID,
            targetLanguage: config.targetLanguage,
            sourceContentHash: sourceHash
        )
        precondition(afterInvalid.count == 2)

        try await repository.markTranslationLocked(versionID: first.record.id, locked: true)
        let lockedFirst = try await repository.loadTranslationVersions(
            lyricsVersionID: lyricsVersionID,
            targetLanguage: config.targetLanguage,
            sourceContentHash: sourceHash
        ).first
        precondition(lockedFirst?.record.isLocked == true)

        // Migration imports the legacy column without guessing language/model.
        let legacyURL = root.appendingPathComponent("legacy.sqlite3")
        let legacyTrack = Track(title: "Legacy", artist: "Artist", album: "Album", duration: 90, spotifyId: "legacy-id")
        let legacyIdentity = TrackIdentity(track: legacyTrack)
        makeV1Database(at: legacyURL, stableKey: legacyIdentity.stableKey)
        let legacyRepository = SQLiteLyricsRepository(databaseURL: legacyURL)
        try await legacyRepository.prepare()
        let legacySchemaVersion = try await legacyRepository.schemaVersion()
        precondition(legacySchemaVersion == DatabaseMigrator.currentVersion)
        let legacySource = try await legacyRepository.loadBestStored(track: legacyTrack, identity: legacyIdentity)
        guard let legacySource, let legacyID = legacySource.versionID, let legacyHash = legacySource.sourceContentHash else {
            fatalError("legacy lyrics missing")
        }
        let legacyTranslations = try await legacyRepository.loadTranslationVersions(
            lyricsVersionID: legacyID,
            targetLanguage: "und",
            sourceContentHash: legacyHash
        )
        precondition(legacyTranslations.count == 1)
        precondition(legacyTranslations[0].record.sourceKind == .legacyImported)
        precondition(legacyTranslations[0].lines[0].translatedText == "译文")
        let backupCount = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("pre-v3") }.count
        precondition(backupCount == 1, "v2 migration must make a backup")

        let reopened = SQLiteLyricsRepository(databaseURL: legacyURL)
        try await reopened.prepare()
        let legacyAgain = try await reopened.loadTranslationVersions(
            lyricsVersionID: legacyID,
            targetLanguage: "und",
            sourceContentHash: legacyHash
        )
        precondition(legacyAgain.count == 1, "migration must be idempotent")

        print("translation persistence contracts passed")
    }
}
