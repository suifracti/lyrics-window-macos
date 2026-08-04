import Foundation

@main
struct ReadingPersistenceContract {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotifyLyricsReadingContract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("SpotifyLyrics.sqlite3")
        let repository = SQLiteLyricsRepository(databaseURL: url)
        try await repository.prepare()
        let schemaVersion = try await repository.schemaVersion()
        precondition(schemaVersion == 6)

        let track = Track(
            title: "生ビールを飲む",
            artist: "TEST",
            album: "Reading Fixture",
            duration: 120,
            isrc: "JP-READING-1",
            spotifyId: "reading-fixture",
            artworkURL: nil,
            spotifyURL: URL(string: "spotify:track:reading-fixture")
        )
        let identity = TrackIdentity(track: track)
        let document = LyricsDocument(
            identity: identity,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            lines: [
                LyricLine(timestamp: 0, originalText: "生ビールを飲む", romajiText: "nama biiru o nomu", kanaText: "なまビールをのむ"),
                LyricLine(timestamp: 4, originalText: "学生として生きる", romajiText: "gakusei to shite ikiru", kanaText: "がくせいとしていきる")
            ],
            isSynchronized: true,
            source: .manualCreate,
            confidence: 1,
            providerSourceID: "reading-fixture"
        )
        let saved = try await repository.save(track: track, identity: identity, document: document)
        guard let lyricsVersionID = saved.versionID, let sourceHash = saved.sourceContentHash else {
            fatalError("fixture lyrics did not save")
        }

        let now = Date()
        let version = ReadingVersionRecord(
            id: UUID(),
            lyricsVersionID: lyricsVersionID,
            sourceContentHash: sourceHash,
            engineID: ReadingEngineID.japaneseDictionary.rawValue,
            representationID: ReadingRepresentationID.kana.rawValue,
            language: .japanese,
            createdAt: now,
            updatedAt: now,
            isMachineGenerated: true,
            isManuallyEdited: false,
            isCurrent: false,
            isLocked: false,
            isArchived: false,
            parentVersionID: nil,
            confidence: 0.96,
            warningMetadata: [],
            contextHash: "fixture-context"
        )
        let lines = [
            ReadingLineResult(lineIndex: 0, originalText: "生ビールを飲む", readingText: "なまビールをのむ", language: .japanese, tokens: [], confidence: 0.96),
            ReadingLineResult(lineIndex: 1, originalText: "学生として生きる", readingText: "がくせいとしていきる", language: .japanese, tokens: [], confidence: 0.96)
        ]
        _ = try await repository.saveReadingVersion(ReadingVersionSaveRequest(record: version, lines: lines))
        let loaded = try await repository.loadReadingVersions(
            lyricsVersionID: lyricsVersionID,
            representationID: ReadingRepresentationID.kana.rawValue,
            sourceContentHash: sourceHash
        )
        precondition(loaded.count == 1)
        precondition(loaded[0].lines.map { $0.readingText } == ["なまビールをのむ", "がくせいとしていきる"])

        try await repository.adoptReadingVersion(versionID: version.id)
        let adopted = try await repository.loadReadingVersions(
            lyricsVersionID: lyricsVersionID,
            representationID: ReadingRepresentationID.kana.rawValue,
            sourceContentHash: sourceHash
        )
        precondition(adopted.first?.record.isCurrent == true)
        try await repository.markReadingLocked(versionID: version.id, locked: true)
        do {
            try await repository.deleteReadingVersion(versionID: version.id)
            fatalError("locked reading version must not be deleted")
        } catch let error as ReadingRepositoryError {
            precondition(error == .lockedVersion)
        }

        // The source fingerprint is part of every lookup. A stale hash must
        // fail closed instead of projecting a reading onto changed lyrics.
        do {
            _ = try await repository.loadReadingVersions(
                lyricsVersionID: lyricsVersionID,
                representationID: nil,
                sourceContentHash: "stale"
            )
            fatalError("stale source hash must be rejected")
        } catch let error as ReadingRepositoryError {
            precondition(error == .sourceContentMismatch)
        }

        print("phase 2.6A reading persistence contract passed")
    }
}
