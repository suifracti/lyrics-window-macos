import Foundation

private func makeTrack(
    title: String,
    artist: String,
    album: String,
    duration: TimeInterval,
    spotifyID: String
) -> Track {
    Track(
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        spotifyId: spotifyID,
        spotifyURL: URL(string: "spotify:track:\(spotifyID)")
    )
}

@main
struct TrackIdentityV4WaterContract {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fatalError("usage: contract DATABASE_PATH") }
        let databaseURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = databaseURL.deletingLastPathComponent()
        let repository = SQLiteLyricsRepository(
            databaseURL: databaseURL,
            alignmentProvenanceDirectory: root.appendingPathComponent("AlignmentProvenance", isDirectory: true)
        )
        try await repository.prepare()

        let water = makeTrack(
            title: "水曜日の約束",
            artist: "Kawasaki.Rio",
            album: "水曜日の約束",
            duration: 171.177,
            spotifyID: "5MqkkCSrUjqyaKVOlvEn0w"
        )
        let waterIdentity = TrackIdentity(track: water)
        let sourceKey = "spotify-id:spotify:track:5mqkkcsrujqyakvolven0w|metadata:水曜日の約束|kawasakirio|水曜日の約束|171"
        let resolvedWater = try await repository.resolveStableKey(sourceKey)
        let waterFamily = try await repository.identityFamily(stableKey: sourceKey)
        precondition(resolvedWater == waterIdentity.stableKey, "Water old key resolves")
        precondition(waterFamily.count == 2, "Water identity family")

        let stored = try await repository.loadBestStored(track: water, identity: waterIdentity)
        precondition(stored?.document.lines.count == 32, "Water logical read keeps all 32 lines")
        precondition(stored?.document.source == .manualEdit, "locked manual derived version wins")

        let editable = try await repository.loadEditableVersions(track: water, identity: waterIdentity)
        precondition(editable.count >= 5, "Water source and derived versions remain visible")
        precondition(editable.contains { $0.record.trackStableKey == sourceKey }, "old physical version key is retained")
        precondition(editable.contains { $0.record.trackStableKey == waterIdentity.stableKey }, "canonical physical version key is retained")
        precondition(editable.contains { $0.record.source == "qqExperimental" && !$0.record.isSynced }, "QQ plain text remains readable")
        precondition(editable.contains { $0.record.isLocked && $0.record.parentVersionID != nil }, "locked parent chain is retained")
        let aliases = try await repository.loadTrackAliases(stableKey: sourceKey)
        precondition(Set(aliases.map { [$0.field, $0.kind, $0.value].joined(separator: "\u{1f}") }).count == aliases.count, "alias read deduplicates in memory")

        guard let sourceVersion = editable.first(where: { $0.record.isLocked }) else {
            fatalError("Water locked source version missing")
        }
        var translationSource: StoredEditableLyricsVersion?
        for version in editable {
            let hash = LyricsSourceContentHasher.hash(isSynchronized: version.record.isSynced, lines: version.lines)
            let translations = try await repository.loadTranslationVersions(
                lyricsVersionID: version.record.id,
                targetLanguage: "zh-Hans",
                sourceContentHash: hash
            )
            if !translations.isEmpty {
                translationSource = version
                break
            }
        }
        precondition(translationSource != nil, "Water translation relation remains readable")

        let sourceHash = LyricsSourceContentHasher.hash(
            isSynchronized: sourceVersion.record.isSynced,
            lines: sourceVersion.lines
        )

        let editedDocument = LyricsDocument(
            identity: waterIdentity,
            title: water.title,
            artist: water.artist,
            album: water.album,
            duration: water.duration,
            lines: sourceVersion.document.lines,
            isSynchronized: sourceVersion.record.isSynced,
            source: .manualEdit,
            confidence: 1,
            providerSourceID: "v4-water-manual-test"
        )
        let edit = LyricsEditSaveRequest(
            track: water,
            identity: waterIdentity,
            sourceVersionID: sourceVersion.record.id,
            sourceContentHash: sourceHash,
            document: editedDocument,
            createLyricsVersion: true,
            targetSource: .manualEdit
        )
        let saved = try await repository.saveManualEdit(edit)
        precondition(saved.lyricsVersion?.record.trackStableKey == waterIdentity.stableKey, "new writes use canonical key")

        let loveA = makeTrack(title: "恋風", artist: "Lilas", album: "恋風", duration: 182.029, spotifyID: "6qgudk8ty8lan39gtwtxwk")
        let loveB = makeTrack(title: "恋風", artist: "Lilas", album: "Laugh", duration: 183.56, spotifyID: "3gw8n3dg28vayguvc3lqxl")
        let loveAKey = TrackIdentity(track: loveA).stableKey
        let loveBKey = TrackIdentity(track: loveB).stableKey
        precondition(loveAKey != loveBKey, "Love tracks remain separate")
        let resolvedLoveA = try await repository.resolveStableKey(loveAKey)
        let resolvedLoveB = try await repository.resolveStableKey(loveBKey)
        precondition(resolvedLoveA == loveAKey, "Love A has no redirect")
        precondition(resolvedLoveB == loveBKey, "Love B has no redirect")

        print("track identity v4 Water contract passed")
    }
}
