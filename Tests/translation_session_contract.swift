import Foundation

private func makeTrack(_ id: String, title: String) -> Track {
    Track(
        title: title,
        artist: "Contract Artist",
        album: "Contract Album",
        duration: 120,
        spotifyId: id,
        spotifyURL: URL(string: "spotify:track:\(id)")
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
            LyricLine(timestamp: 0, originalText: "第一行"),
            LyricLine(timestamp: 2, originalText: "第二行")
        ],
        isSynchronized: true,
        source: .lrclib,
        confidence: 0.99,
        providerSourceID: "session-contract"
    )
}

private actor MemoryTranslationRepository: TranslationRepository {
    struct Save: Sendable {
        let lyricsVersionID: UUID
        let sourceContentHash: String
    }

    private(set) var saves: [Save] = []

    func loadTranslationVersions(
        lyricsVersionID: UUID,
        targetLanguage: String,
        sourceContentHash: String
    ) async throws -> [StoredTranslationVersion] {
        _ = lyricsVersionID
        _ = targetLanguage
        _ = sourceContentHash
        return []
    }

    func saveTranslation(
        lyricsVersionID: UUID,
        sourceContentHash: String,
        originalLines: [String],
        draft: AITranslationDraft,
        forceNewVersion: Bool
    ) async throws -> StoredTranslationVersion {
        _ = originalLines
        _ = forceNewVersion
        let id = UUID()
        saves.append(Save(lyricsVersionID: lyricsVersionID, sourceContentHash: sourceContentHash))
        let now = Date()
        let record = DatabaseTranslationVersionRecord(
            id: id,
            lyricsVersionID: lyricsVersionID,
            sourceKind: draft.sourceKind,
            targetLanguage: draft.targetLanguage,
            model: draft.model,
            baseURLHost: draft.baseURLHost,
            promptHash: draft.promptHash,
            sourceContentHash: draft.sourceContentHash,
            createdAt: now,
            updatedAt: now,
            isMachineGenerated: true,
            isManuallyEdited: false,
            isLocked: false,
            status: .complete,
            confidence: draft.confidence
        )
        let lines = draft.lines.map {
            DatabaseTranslationLineRecord(
                translationVersionID: id,
                lineIndex: $0.index,
                translatedText: $0.translation
            )
        }
        return StoredTranslationVersion(record: record, lines: lines)
    }

    func markTranslationLocked(versionID: UUID, locked: Bool) async throws {
        _ = versionID
        _ = locked
    }

    func deleteTranslation(versionID: UUID) async throws {
        _ = versionID
    }

    func saveSnapshot() -> [Save] { saves }
}

private actor CallCounter {
    var value = 0

    func increment() { value += 1 }
}

private final class SlowTranslationService: AITranslationService, @unchecked Sendable {
    private let counter = CallCounter()

    func translate(
        context: AITranslationContext,
        sourceContentHash: String,
        configuration: AITranslationConfiguration
    ) async throws -> AITranslationDraft {
        await counter.increment()

        // Deliberately ignore cancellation. The controller must still reject
        // the result after a track switch before it reaches the repository.
        try? await Task.sleep(nanoseconds: 150_000_000)
        return AITranslationDraft(
            lines: context.lines.map { AITranslationLine(index: $0.index, translation: "译文 \($0.index)") },
            targetLanguage: configuration.targetLanguage,
            model: configuration.model,
            baseURLHost: "contract.test",
            promptHash: "session-contract",
            sourceContentHash: sourceContentHash
        )
    }

    func testConnection(configuration: AITranslationConfiguration) async throws {
        _ = configuration
    }

    func calls() async -> Int { await counter.value }
}

@main
struct TranslationSessionContract {
    static func main() async {
        let repository = MemoryTranslationRepository()
        let service = SlowTranslationService()
        let configuration = AITranslationConfiguration(
            baseURL: "https://contract.test",
            model: "contract-model",
            autoTranslateNewLyrics: false
        )

        let controller = await MainActor.run {
            TranslationSessionController(repository: repository, service: service)
        }

        let trackA = makeTrack("a", title: "歌曲 A")
        let identityA = TrackIdentity(track: trackA)
        let documentA = makeDocument(track: trackA, identity: identityA)
        let hashA = LyricsPersistenceMapper.sourceContentHash(document: documentA)
        await MainActor.run {
            controller.synchronize(
                document: documentA,
                lyricsVersionID: UUID(uuidString: "00000000-0000-0000-0000-00000000000a")!,
                sourceContentHash: hashA,
                configuration: configuration
            )
            controller.translateCurrentLyrics()
            controller.translateCurrentLyrics()
        }

        try? await Task.sleep(nanoseconds: 30_000_000)

        let trackB = makeTrack("b", title: "歌曲 B")
        let identityB = TrackIdentity(track: trackB)
        let documentB = makeDocument(track: trackB, identity: identityB)
        let hashB = LyricsPersistenceMapper.sourceContentHash(document: documentB)
        await MainActor.run {
            controller.synchronize(
                document: documentB,
                lyricsVersionID: UUID(uuidString: "00000000-0000-0000-0000-00000000000b")!,
                sourceContentHash: hashB,
                configuration: configuration
            )
            controller.translateCurrentLyrics()
        }

        try? await Task.sleep(nanoseconds: 350_000_000)
        let saves = await repository.saveSnapshot()
        let calls = await service.calls()
        precondition(calls == 2, "duplicate in-flight request was not merged")
        precondition(saves.count == 1, "stale track translation reached persistence")
        precondition(saves[0].sourceContentHash == hashB, "saved translation belongs to the wrong track")
        print("translation session contracts passed")
    }
}
