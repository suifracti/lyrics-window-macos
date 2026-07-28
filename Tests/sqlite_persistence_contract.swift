import Foundation

private func makeTrack(
    title: String,
    artist: String,
    duration: TimeInterval,
    spotifyID: String
) -> Track {
    Track(
        title: title,
        artist: artist,
        album: "Album",
        duration: duration,
        isrc: "JP-TEST-\(spotifyID)",
        spotifyId: spotifyID,
        artworkURL: URL(string: "https://example.test/\(spotifyID).jpg"),
        spotifyURL: URL(string: "spotify:track:\(spotifyID)")
    )
}

private func makeDocument(
    track: Track,
    identity: TrackIdentity,
    source: LyricsSource,
    lineCount: Int,
    synchronized: Bool,
    confidence: Double = 0.98,
    providerSourceID: String
) -> LyricsDocument {
    let lines = (0..<lineCount).map { index in
        LyricLine(
            timestamp: synchronized ? Double(index) * 3.25 : 0,
            originalText: "原文 \(index)",
            translationText: index == 0 ? "translation" : nil,
            romajiText: "genbun \(index)",
            kanaText: "げんぶん \(index)"
        )
    }
    return LyricsDocument(
        identity: identity,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration,
        lines: lines,
        isSynchronized: synchronized,
        source: source,
        confidence: confidence,
        providerSourceID: providerSourceID
    )
}

@main
struct SQLitePersistenceContract {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotifyLyricsSQLiteContract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("SpotifyLyrics.sqlite3")
        let repository = SQLiteLyricsRepository(databaseURL: databaseURL)
        try await repository.prepare()
        precondition(FileManager.default.fileExists(atPath: databaseURL.path))
        let schemaVersion = try await repository.schemaVersion()
        let foreignKeysEnabled = try await repository.foreignKeysEnabled()
        precondition(schemaVersion == DatabaseMigrator.currentVersion)
        precondition(foreignKeysEnabled)

        let syncedTrack = makeTrack(title: "恋風", artist: "Lilas", duration: 205, spotifyID: "koikaze")
        let syncedIdentity = TrackIdentity(track: syncedTrack)
        let synced = makeDocument(
            track: syncedTrack,
            identity: syncedIdentity,
            source: .lrclib,
            lineCount: 42,
            synchronized: true,
            providerSourceID: "lrclib:42"
        )
        let firstSave = try await repository.save(
            track: syncedTrack,
            identity: syncedIdentity,
            document: synced
        )
        guard case .inserted = firstSave.disposition else {
            fatalError("first synced save must insert: \(firstSave)")
        }
        let restored = try await repository.loadBest(track: syncedTrack, identity: syncedIdentity)
        precondition(restored?.lines.count == 42)
        precondition(restored?.isSynchronized == true)
        precondition(restored?.lines.first?.timestamp == 0, "first synced line should keep its start timestamp")
        guard restored?.lines.first?.kanaText == "げんぶん 0" else {
            fatalError("unexpected first layers: original=\(restored?.lines.first?.originalText ?? "nil") kana=\(restored?.lines.first?.kanaText ?? "nil") romaji=\(restored?.lines.first?.romajiText ?? "nil")")
        }
        precondition(restored?.lines.first?.romajiText == "genbun 0")
        precondition(restored?.providerSourceID == "lrclib:42")
        precondition(restored?.lines[1].timestamp == 3.25)

        let duplicate = try await repository.save(
            track: syncedTrack,
            identity: syncedIdentity,
            document: synced
        )
        guard case .duplicate = duplicate.disposition else {
            fatalError("same content must deduplicate: \(duplicate)")
        }
        let syncedVersionCount = try await repository.versionCount(trackStableKey: syncedIdentity.stableKey)
        precondition(syncedVersionCount == 1)

        let plainTrack = makeTrack(title: "水曜日の約束", artist: "Kawasaki.Rio", duration: 171.177, spotifyID: "suiyoubi")
        let plainIdentity = TrackIdentity(track: plainTrack)
        let plain = makeDocument(
            track: plainTrack,
            identity: plainIdentity,
            source: .qqExperimental,
            lineCount: 32,
            synchronized: false,
            providerSourceID: "qq:plain-32"
        )
        _ = try await repository.save(track: plainTrack, identity: plainIdentity, document: plain)
        let plainRestored = try await repository.loadBest(track: plainTrack, identity: plainIdentity)
        precondition(plainRestored?.lines.count == 32)
        precondition(plainRestored?.isSynchronized == false)
        precondition(plainRestored?.lines.allSatisfy { $0.timestamp == 0 } == true)

        let otherTrack = makeTrack(title: "あやふや", artist: "みさき", duration: 180, spotifyID: "ayafuya")
        let otherIdentity = TrackIdentity(track: otherTrack)
        let otherRestored = try await repository.loadBest(track: otherTrack, identity: otherIdentity)
        precondition(otherRestored == nil)
        let empty = LyricsDocument(
            identity: otherIdentity,
            title: otherTrack.title,
            artist: otherTrack.artist,
            album: otherTrack.album,
            duration: otherTrack.duration,
            lines: [],
            isSynchronized: false,
            source: .qqExperimental,
            confidence: 1,
            providerSourceID: "qq:empty"
        )
        let emptyResult = try await repository.save(track: otherTrack, identity: otherIdentity, document: empty)
        guard case .rejected = emptyResult.disposition else {
            fatalError("empty lyrics must be rejected")
        }
        let emptyVersionCount = try await repository.versionCount(trackStableKey: otherIdentity.stableKey)
        precondition(emptyVersionCount == 0)

        let lowConfidence = makeDocument(
            track: otherTrack,
            identity: otherIdentity,
            source: .lrclib,
            lineCount: 1,
            synchronized: true,
            confidence: 0.2,
            providerSourceID: "lrclib:low"
        )
        let lowResult = try await repository.save(track: otherTrack, identity: otherIdentity, document: lowConfidence)
        guard case .rejected = lowResult.disposition else {
            fatalError("low confidence lyrics must be rejected")
        }

        try await repository.markLocked(versionID: firstSave.versionID!, locked: true)
        let competing = makeDocument(
            track: syncedTrack,
            identity: syncedIdentity,
            source: .qqExperimental,
            lineCount: 43,
            synchronized: false,
            providerSourceID: "qq:wrong-version"
        )
        let blocked = try await repository.save(track: syncedTrack, identity: syncedIdentity, document: competing)
        guard case .skippedLocked = blocked.disposition else {
            fatalError("locked version must block network replacement: \(blocked)")
        }
        let lockedVersionCount = try await repository.versionCount(trackStableKey: syncedIdentity.stableKey)
        precondition(lockedVersionCount == 1)

        let corruptedURL = root.appendingPathComponent("corrupted.sqlite3")
        try Data("not sqlite".utf8).write(to: corruptedURL)
        let corruptedRepository = SQLiteLyricsRepository(databaseURL: corruptedURL)
        do {
            try await corruptedRepository.prepare()
            fatalError("corrupted database must report an error")
        } catch let error as LyricsRepositoryError {
            guard case .migrationFailed = error else {
                fatalError("unexpected persistence error: \(error)")
            }
        }

        print("sqlite persistence contract passed")
    }
}
