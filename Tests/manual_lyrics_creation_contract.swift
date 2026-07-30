import Foundation

@main
struct ManualLyricsCreationContract {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SpotifyLyricsManualCreation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = SQLiteLyricsRepository(databaseURL: root.appendingPathComponent("SpotifyLyrics.sqlite3"))
        try await repository.prepare()
        let track = Track(title: "Forever", artist: "VILLSHANA, Mahiru", album: "Single", duration: 180, spotifyId: "forever-test")
        let identity = TrackIdentity(track: track)

        let plain = try TextLyricsImportParser.parse("第一行\n\n第二行")
        let document = plain.document(identity: identity, track: track, source: .manualImport)
        let saved = try await repository.saveManualEdit(LyricsEditSaveRequest(
            track: track,
            identity: identity,
            sourceVersionID: UUID(),
            sourceContentHash: "new-source",
            document: document,
            createLyricsVersion: true,
            lockLyricsVersion: true,
            targetSource: .manualImport,
            isNewSource: true
        ))
        guard let imported = saved.lyricsVersion else { throw ContractError("new manual version missing") }
        try require(imported.record.source == "manualImport", "manual import source")
        try require(imported.record.parentVersionID == nil, "new import has no fake parent")
        try require(imported.record.isLocked, "new import lock persisted")
        try require(imported.record.isManuallyEdited, "manual import is marked manually edited")
        try require(!imported.record.isSynced, "new import remains plain")
        try require(imported.document.lines.map(\.originalText) == ["第一行", "", "第二行"], "new import lines persisted")

        do {
            _ = try await repository.saveManualEdit(LyricsEditSaveRequest(
                track: track,
                identity: identity,
                sourceVersionID: UUID(),
                sourceContentHash: "empty",
                document: LyricsDocument(identity: identity, title: track.title, artist: track.artist, album: track.album, duration: track.duration, lines: [], isSynchronized: false, source: .manualCreate),
                createLyricsVersion: true,
                targetSource: .manualCreate,
                isNewSource: true
            ))
            throw ContractError("empty lyrics version was written")
        } catch LyricsEditingRepositoryError.invalidDocument {
            // expected
        }

        do {
            _ = try await repository.saveManualEdit(LyricsEditSaveRequest(
                track: track,
                identity: identity,
                sourceVersionID: UUID(),
                sourceContentHash: "blank-only",
                document: LyricsDocument(
                    identity: identity,
                    title: track.title,
                    artist: track.artist,
                    album: track.album,
                    duration: track.duration,
                    lines: [LyricLine(timestamp: 0, originalText: "   ")],
                    isSynchronized: false,
                    source: .manualCreate
                ),
                createLyricsVersion: true,
                targetSource: .manualCreate,
                isNewSource: true
            ))
            throw ContractError("blank-only lyrics version was written")
        } catch LyricsEditingRepositoryError.invalidDocument {
            // expected
        }

        do {
            let otherTrack = Track(title: "Other", artist: "Other Artist", album: "Other", duration: 120, spotifyId: "other-test")
            _ = try await repository.saveManualEdit(LyricsEditSaveRequest(
                track: otherTrack,
                identity: identity,
                sourceVersionID: UUID(),
                sourceContentHash: "cross-track",
                document: document,
                createLyricsVersion: true,
                targetSource: .manualCreate,
                isNewSource: true
            ))
            throw ContractError("cross-track manual source was accepted")
        } catch LyricsEditingRepositoryError.identityMismatch {
            // expected: a stale editor must not attach A's text to B.
        }

        let restarted = SQLiteLyricsRepository(databaseURL: repository.databaseURL)
        try await restarted.prepare()
        let restored = try await restarted.loadEditableVersion(versionID: imported.record.id, track: track, identity: identity)
        try require(restored?.record.isLocked == true, "locked version restored after restart")
        try require(restored?.record.source == "manualImport", "source restored after restart")
        try require(restored?.document.lines.count == 3, "line count restored after restart")
        print("manual lyrics creation contract passed")
    }

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw ContractError(message) }
    }
}

struct ContractError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { "FAIL: \(message)" }
}
