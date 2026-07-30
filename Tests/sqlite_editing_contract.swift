import Foundation

@main
struct SQLiteEditingContract {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SpotifyLyricsEditing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("SpotifyLyrics.sqlite3")
        let repository = SQLiteLyricsRepository(databaseURL: url)
        try await repository.prepare()

        let track = Track(id: "edit-track", title: "恋風", artist: "Lilas", album: "Single", duration: 182, spotifyId: "edit-track")
        let identity = TrackIdentity(track: track)
        let providerDocument = LyricsDocument(
            identity: identity,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            lines: [
                LyricLine(timestamp: 0, originalText: "第一行", endTime: 2, romajiText: "daiichi gyou", kanaText: "だいいちぎょう"),
                LyricLine(timestamp: 2, originalText: "第二行", endTime: 5, romajiText: "daini gyou", kanaText: "だいにぎょう")
            ],
            isSynchronized: true,
            source: .lrclib,
            confidence: 1,
            providerSourceID: "lrclib-real"
        )
        let saved = try await repository.save(track: track, identity: identity, document: providerDocument)
        guard let providerID = saved.versionID, let providerHash = saved.sourceContentHash else { throw TestError("provider save") }

        let editedDocument = LyricsDocument(
            identity: identity,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            lines: [
                LyricLine(timestamp: 0, originalText: "第一行（修订）", endTime: 2, romajiText: "daiichi gyou shuusei", kanaText: "だいいちぎょうしゅうせい"),
                LyricLine(timestamp: 2, originalText: "第二行", endTime: 5, romajiText: "daini gyou", kanaText: "だいにぎょう")
            ],
            isSynchronized: true,
            source: .manualEdit,
            confidence: 1,
            providerSourceID: "manualEdit"
        )
        let edit = LyricsEditSaveRequest(
            track: track,
            identity: identity,
            sourceVersionID: providerID,
            sourceContentHash: providerHash,
            document: editedDocument,
            createLyricsVersion: true,
            lockLyricsVersion: true,
            translation: ManualTranslationEdit(
                targetLanguage: "zh-Hans",
                lines: ["第一行（人工）", "第二行（人工）"],
                isLocked: true
            ),
            readingLayers: [LyricsReadingLayerDraft(
                lineIndex: 0,
                kanaText: "だいいちぎょうしゅうせい",
                romajiText: "daiichi gyou shuusei",
                isLocked: true
            )]
        )
        let result = try await repository.saveManualEdit(edit)
        guard let manual = result.lyricsVersion, let manualTranslation = result.translationVersion else {
            throw TestError("manual versions missing")
        }
        guard manual.record.source == "manualEdit",
              manual.record.parentVersionID == providerID,
              manual.record.isLocked,
              manual.document.lines[0].originalText == "第一行（修订）",
              manual.lockedReadingLayers.first?.kanaText == "だいいちぎょうしゅうせい",
              manualTranslation.record.sourceKind == AITranslationSourceKind.manualEdit,
              manualTranslation.record.isLocked,
              manualTranslation.lines.count == 2 else {
            throw TestError("manual version fields incorrect")
        }

        let importedDocument = LyricsDocument(
            identity: identity,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            lines: [
                LyricLine(timestamp: 0, originalText: "纯文本一"),
                LyricLine(timestamp: 0, originalText: "纯文本二")
            ],
            isSynchronized: false,
            source: .manualImport
        )
        let imported = try await repository.saveManualEdit(LyricsEditSaveRequest(
            track: track,
            identity: identity,
            sourceVersionID: providerID,
            sourceContentHash: providerHash,
            document: importedDocument,
            createLyricsVersion: true,
            targetSource: .manualImport
        ))
        guard imported.lyricsVersion?.record.source == "manualImport",
              imported.lyricsVersion?.record.isSynced == false else {
            throw TestError("manual import source or plain timing was changed")
        }

        let versions = try await repository.loadEditableVersions(track: track, identity: identity)
        guard versions.count == 3,
              versions.contains(where: { $0.record.id == providerID && $0.record.source == "lrclib" }),
              versions.contains(where: { $0.record.id == manual.record.id && $0.record.parentVersionID == providerID }) else {
            throw TestError("provider parent version was not preserved")
        }

        let restarted = SQLiteLyricsRepository(databaseURL: url)
        try await restarted.prepare()
        let restored = try await restarted.loadEditableVersion(versionID: manual.record.id, track: track, identity: identity)
        guard restored?.record.isLocked == true,
              restored?.lockedReadingLayers.first?.isLocked == true,
              restored?.document.lines[0].kanaText == "だいいちぎょうしゅうせい" else {
            throw TestError("manual lock/readings did not survive restart")
        }

        do {
            _ = try await restarted.saveManualEdit(LyricsEditSaveRequest(
                track: track,
                identity: identity,
                sourceVersionID: providerID,
                sourceContentHash: "stale",
                document: editedDocument,
                createLyricsVersion: true
            ))
            throw TestError("stale edit accepted")
        } catch LyricsEditingRepositoryError.sourceContentMismatch { }

        let invalid = LyricsDocument(
            identity: identity,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            lines: [LyricLine(timestamp: -1, originalText: "非法")],
            isSynchronized: true,
            source: .manualEdit
        )
        do {
            _ = try await restarted.saveManualEdit(LyricsEditSaveRequest(
                track: track,
                identity: identity,
                sourceVersionID: providerID,
                sourceContentHash: providerHash,
                document: invalid,
                createLyricsVersion: true
            ))
            throw TestError("invalid timeline accepted")
        } catch LyricsEditingRepositoryError.invalidTimeline { }

        print("sqlite editing contract passed")
    }
}

struct TestError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}
