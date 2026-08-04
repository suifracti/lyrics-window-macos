import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private func makeDocument() -> (Track, TrackIdentity, LyricsDocument, UUID) {
    let track = Track(
        title: "夜の契約",
        artist: "Contract Artist",
        album: "Contract Album",
        duration: 120,
        spotifyId: "phase25c-track",
        spotifyURL: URL(string: "spotify:track:phase25c-track")
    )
    let identity = TrackIdentity(track: track)
    let document = LyricsDocument(
        identity: identity,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration,
        lines: [
            LyricLine(timestamp: 0, originalText: "夜の窓"),
            LyricLine(timestamp: 2, originalText: "静かな雨")
        ],
        isSynchronized: true,
        source: .lrclib,
        confidence: 1,
        providerSourceID: "phase25c"
    )
    return (track, identity, document, UUID())
}

private actor MemoryTranslationRepository: TranslationRepository {
    private var versions: [StoredTranslationVersion] = []
    private(set) var adoptedIDs: [UUID] = []
    private(set) var archivedIDs: [UUID] = []

    func loadTranslationVersions(
        lyricsVersionID: UUID,
        targetLanguage: String,
        sourceContentHash: String
    ) async throws -> [StoredTranslationVersion] {
        versions.filter {
            $0.record.lyricsVersionID == lyricsVersionID &&
            $0.record.targetLanguage == targetLanguage &&
            $0.record.sourceContentHash == sourceContentHash
        }
    }

    func saveTranslation(
        lyricsVersionID: UUID,
        sourceContentHash: String,
        originalLines: [String],
        draft: AITranslationDraft,
        forceNewVersion: Bool
    ) async throws -> StoredTranslationVersion {
        require(forceNewVersion || versions.isEmpty, "new explicit translation must not overwrite an existing version")
        require(originalLines.count == draft.lines.count, "fixture line count")
        let id = UUID()
        let now = Date()
        let record = DatabaseTranslationVersionRecord(
            id: id,
            lyricsVersionID: lyricsVersionID,
            sourceKind: draft.sourceKind,
            targetLanguage: draft.targetLanguage,
            model: draft.model,
            baseURLHost: draft.baseURLHost,
            promptHash: draft.promptHash,
            sourceContentHash: sourceContentHash,
            createdAt: now,
            updatedAt: now,
            isMachineGenerated: draft.isMachineGenerated,
            isManuallyEdited: draft.isManuallyEdited,
            isLocked: false,
            status: .complete,
            confidence: draft.confidence,
            engineID: draft.engineID,
            promptPresetID: draft.promptPresetID,
            profileID: draft.profileID,
            profileSnapshot: draft.profileSnapshot,
            temperature: draft.temperature,
            workflowID: draft.workflowID,
            fallbackStrategy: draft.fallbackStrategy,
            isDraft: draft.isDraft,
            isArchived: draft.isArchived
        )
        let lines = draft.lines.map {
            DatabaseTranslationLineRecord(
                translationVersionID: id,
                lineIndex: $0.index,
                translatedText: $0.translation
            )
        }
        let stored = StoredTranslationVersion(record: record, lines: lines)
        versions.insert(stored, at: 0)
        return stored
    }

    func markTranslationLocked(versionID: UUID, locked: Bool) async throws {
        versions = versions.map { version in
            guard version.record.id == versionID else { return version }
            var record = version.record
            record = DatabaseTranslationVersionRecord(
                id: record.id,
                lyricsVersionID: record.lyricsVersionID,
                parentVersionID: record.parentVersionID,
                sourceKind: record.sourceKind,
                targetLanguage: record.targetLanguage,
                model: record.model,
                baseURLHost: record.baseURLHost,
                promptHash: record.promptHash,
                sourceContentHash: record.sourceContentHash,
                createdAt: record.createdAt,
                updatedAt: Date(),
                isMachineGenerated: record.isMachineGenerated,
                isManuallyEdited: record.isManuallyEdited,
                isLocked: locked,
                status: record.status,
                confidence: record.confidence,
                engineID: record.engineID,
                promptPresetID: record.promptPresetID,
                profileID: record.profileID,
                profileSnapshot: record.profileSnapshot,
                temperature: record.temperature,
                workflowID: record.workflowID,
                fallbackStrategy: record.fallbackStrategy,
                isDraft: record.isDraft,
                isArchived: record.isArchived
            )
            return version.with(record: record)
        }
    }

    func deleteTranslation(versionID: UUID) async throws {
        versions.removeAll { $0.record.id == versionID }
    }

    func adoptTranslation(versionID: UUID) async throws {
        adoptedIDs.append(versionID)
        versions = versions.map { version in
            guard version.record.id == versionID else { return version }
            return version.with(record: version.record.with(isDraft: false, isArchived: false))
        }
    }

    func archiveTranslation(versionID: UUID, archived: Bool) async throws {
        archivedIDs.append(versionID)
        versions = versions.map { version in
            guard version.record.id == versionID else { return version }
            return version.with(record: version.record.with(isArchived: archived))
        }
    }

    func snapshot() -> [StoredTranslationVersion] { versions }
}

private struct FixtureTranslationEngine: TranslationEngine {
    let metadata = TranslationEngineMetadata(
        stableID: TranslationEngineID.openAICompatible.rawValue,
        displayName: "合同测试引擎",
        availability: .available,
        requiresAPIKey: false,
        supportsModelDirectory: false
    )

    func translate(
        context: AITranslationContext,
        sourceContentHash: String,
        configuration: AITranslationConfiguration
    ) async throws -> AITranslationDraft {
        AITranslationDraft(
            lines: context.lines.map { AITranslationLine(index: $0.index, translation: "译文 ($0.index)") },
            targetLanguage: configuration.targetLanguage,
            model: "fixture-model",
            baseURLHost: "fixture.test",
            promptHash: "fixture-prompt",
            sourceContentHash: sourceContentHash,
            engineID: metadata.stableID,
            promptPresetID: configuration.promptPresetID,
            profileID: configuration.profileID,
            profileSnapshot: configuration.profileSnapshot,
            temperature: configuration.temperature,
            workflowID: configuration.workflowID,
            fallbackStrategy: configuration.fallbackStrategy,
            isDraft: true
        )
    }

    func testConnection(configuration: AITranslationConfiguration) async throws { _ = configuration }
}

private struct ModelDirectoryHTTPFixture: AIHTTPClient {
    let statusCode: Int
    let body: Data

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        require(request.httpMethod == "GET", "model directory must use GET")
        require(request.url?.path.hasSuffix("/models") == true, "model directory path")
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (body, response)
    }
}

private func waitForCandidate(_ controller: TranslationSessionController) async -> UUID? {
    for _ in 0..<100 {
        let candidate = await MainActor.run { controller.pendingCandidate?.record.id }
        if candidate != nil { return candidate }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return nil
}

private func waitForSelection(_ controller: TranslationSessionController, id: UUID) async -> Bool {
    for _ in 0..<100 {
        let selected = await MainActor.run { controller.selectedVersion?.record.id == id }
        if selected { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return false
}

@main
struct Phase25CContract {
    static func main() async throws {
        require(AITranslationConfiguration(engineID: TranslationEngineID.appleSystem.rawValue).isConfigured, "Apple engine must not require a remote URL or model")

        let profile = TranslationStyleProfile(
            name: "合同风格",
            customInstructions: "保持专有名词不变",
            preserveProperNouns: true,
            preserveRepetition: true,
            keepSongTone: true
        )
        let profileConfiguration = AITranslationConfiguration(
            promptPresetID: profile.basePresetID.rawValue,
            profileID: profile.id,
            profileSnapshot: profile.snapshotString
        )
        let prompt = try AITranslationPromptBuilder().build(
            context: AITranslationContext(
                title: "夜", artist: "歌手", album: "专辑", sourceLanguage: "ja", targetLanguage: "zh-Hans",
                style: "natural_song", lines: [AITranslationSourceLine(index: 0, original: "夜")]
            ),
            configuration: profileConfiguration
        )
        require(prompt.system.contains("保持专有名词不变"), "profile snapshot must affect the execution prompt")

        let modelConfiguration = AITranslationConfiguration(
            baseURL: "https://models.fixture/v1",
            model: "manual-model"
        )
        let modelPayload = Data(#"{"data":[{"id":"z-model"},{"id":"a-model"}]}"#.utf8)
        let models = try await OpenAICompatibleClient(
            httpClient: ModelDirectoryHTTPFixture(statusCode: 200, body: modelPayload)
        ).listModels(configuration: modelConfiguration, apiKey: "fixture-key")
        require(models.map(\.id) == ["a-model", "z-model"], "model directory should sort nonsecret model IDs")
        let empty = try await OpenAICompatibleClient(
            httpClient: ModelDirectoryHTTPFixture(statusCode: 200, body: Data(#"{"data":[]}"#.utf8))
        ).listModels(configuration: modelConfiguration, apiKey: "fixture-key")
        require(empty.isEmpty, "empty model directory status")
        for status in [401, 429, 404, 503] {
            do {
                _ = try await OpenAICompatibleClient(
                    httpClient: ModelDirectoryHTTPFixture(statusCode: status, body: Data())
                ).listModels(configuration: modelConfiguration, apiKey: "fixture-key")
                throw ContractFailure("model directory status (status) was accepted")
            } catch let error as AITranslationError {
                switch status {
                case 401: require(error == .unauthorized, "401 model directory status")
                case 429: require(error == .rateLimited, "429 model directory status")
                default: require(error == .server(status), "model directory HTTP status (status)")
                }
            }
        }

        let (_, identity, document, lyricsVersionID) = makeDocument()
        let sourceHash = LyricsPersistenceMapper.sourceContentHash(document: document)
        let repository = MemoryTranslationRepository()
        let controller = await MainActor.run {
            TranslationSessionController(repository: repository, engine: FixtureTranslationEngine())
        }
        let configuration = AITranslationConfiguration(
            baseURL: "https://fixture.test/v1",
            model: "fixture-model",
            promptPresetID: TranslationPromptPresetID.contextAware.rawValue,
            workflowID: TranslationWorkflowID.contextualV2.rawValue
        )
        await MainActor.run {
            controller.synchronize(
                document: document,
                lyricsVersionID: lyricsVersionID,
                sourceContentHash: sourceHash,
                configuration: configuration
            )
            controller.translateCurrentLyrics()
        }
        guard let firstCandidateID = await waitForCandidate(controller) else {
            throw ContractFailure("translation did not produce a candidate")
        }
        let beforeAdopt = await MainActor.run { (controller.selectedVersion, controller.state) }
        require(beforeAdopt.0 == nil, "generated result must not become current before adoption")
        if case .candidateReady = beforeAdopt.1 { } else { throw ContractFailure("candidate state missing") }

        await MainActor.run { controller.adoptTranslation(versionID: firstCandidateID) }
        let adoptedSelection = await waitForSelection(controller, id: firstCandidateID)
        require(adoptedSelection, "explicit adoption did not select the candidate")
        let adopted = await MainActor.run { controller.selectedVersion }
        require(adopted?.record.isDraft == false, "adopted translation remains a draft")
        require(adopted?.record.engineID == TranslationEngineID.openAICompatible.rawValue, "engine metadata missing")

        await MainActor.run { controller.retranslateCurrentLyrics() }
        guard let secondCandidateID = await waitForCandidate(controller) else {
            throw ContractFailure("explicit retranslation did not create a candidate")
        }
        require(firstCandidateID != secondCandidateID, "explicit retranslation reused the old version ID")
        let duringRetranslate = await MainActor.run { controller.selectedVersion?.record.id }
        require(duringRetranslate == firstCandidateID, "retranslation replaced the selected version before adoption")

        await MainActor.run {
            controller.selectNone()
            require(controller.selectedVersion == nil, "no translation must clear the current selection")
            require(controller.pendingCandidate == nil, "no translation must clear pending candidate presentation")
        }
        let projected = await MainActor.run {
            controller.project(onto: [LyricLine(timestamp: 0, originalText: "原文", translationText: "不应显示")])
        }
        require(projected.first?.translationText == nil, "no translation selection leaked the translation layer")

        await MainActor.run { controller.restoreRecommended() }
        let restoredSelection = await waitForSelection(controller, id: firstCandidateID)
        require(restoredSelection, "restore recommended did not restore the adopted version")
        let storedVersions = await repository.snapshot()
        require(storedVersions.count == 2, "candidate/adopt flow did not preserve both versions")
        require(storedVersions.contains { $0.record.id == secondCandidateID && $0.record.isDraft }, "second candidate was not retained as a draft")
        _ = identity
        print("phase 2.5C contracts passed")
    }
}

private struct ContractFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
