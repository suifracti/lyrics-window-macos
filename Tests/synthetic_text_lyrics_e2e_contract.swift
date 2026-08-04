import Foundation

private let syntheticA = """
夜の窓に雨が落ちる
遠い街の灯りを見ている
名前のない風が通り過ぎる
まだ知らない朝を待っている
"""

private let syntheticB = """
曖昧な言葉を残して
静かな道を歩いている
昨日の夢はまだ消えない
新しい季節を待っている
"""

private func fixtureTrack(id: String, title: String) -> Track {
    Track(
        title: title,
        artist: id == "forever-test" ? "VILLSHANA, Mahiru" : "みさき",
        album: "SYNTHETIC TEST ONLY",
        duration: 180,
        spotifyId: id,
        spotifyURL: URL(string: "spotify:track:\(id)")
    )
}

private func blankDocument(track: Track, identity: TrackIdentity, source: LyricsSource) -> LyricsDocument {
    LyricsDocument(
        identity: identity,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration,
        lines: [LyricLine(timestamp: 0, originalText: "")],
        isSynchronized: false,
        source: source,
        confidence: 1,
        spotifyTrackID: identity.spotifyTrackID,
        isrc: identity.isrc
    )
}

private final class SyntheticKeyStore: AITranslationAPIKeyStore, @unchecked Sendable {
    func read() -> String? { "synthetic-test-key" }
    func save(_ key: String) throws { _ = key }
    func delete() throws {}
}

private actor SyntheticHTTPMetrics {
    private(set) var requestCount = 0
    private(set) var sawAllSourceLines = false

    func record(body: String) {
        requestCount += 1
        sawAllSourceLines = body.contains("夜の窓に雨が落ちる")
            && body.contains("遠い街の灯りを見ている")
            && body.contains("名前のない風が通り過ぎる")
            && body.contains("まだ知らない朝を待っている")
    }
}

private final class SyntheticHTTPClient: AIHTTPClient, @unchecked Sendable {
    private let metrics = SyntheticHTTPMetrics()

    func requestMetrics() async -> (Int, Bool) {
        (await metrics.requestCount, await metrics.sawAllSourceLines)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let requestBody = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        await metrics.record(body: requestBody)

        let responseItems: [[String: Any]] = (0..<4).map {
            ["index": $0, "translation": "SYNTHETIC TEST TRANSLATION \($0)"]
        }
        let responseContent = String(
            data: try! JSONSerialization.data(withJSONObject: responseItems),
            encoding: .utf8
        )!
        let responseEnvelope: [String: Any] = [
            "choices": [["message": ["content": responseContent]]]
        ]
        let responseData = try! JSONSerialization.data(withJSONObject: responseEnvelope)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (responseData, response)
    }
}

private func waitForEditorSave(_ editor: LyricsEditorSessionController) async -> Bool {
    for _ in 0..<100 {
        let saved = await MainActor.run { editor.state == .saved }
        if saved { return true }
        let failed = await MainActor.run {
            if case .failed = editor.state { return true }
            return false
        }
        if failed { return false }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return false
}

private func waitForTranslation(_ controller: TranslationSessionController) async -> Bool {
    for _ in 0..<100 {
        let ready = await MainActor.run {
            switch controller.state {
            case .loaded, .candidateReady:
                return true
            default:
                return false
            }
        }
        if ready { return true }
        let failed = await MainActor.run {
            if case .failed = controller.state { return true }
            return false
        }
        if failed { return false }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return false
}

@main
struct SyntheticTextLyricsE2EContract {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpotifyLyricsSyntheticE2E-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseURL = root.appendingPathComponent("SpotifyLyrics.sqlite3")
        let repository = SQLiteLyricsRepository(databaseURL: databaseURL)
        try await repository.prepare()

        // TEST ONLY: A is read as a UTF-8 BOM + CRLF TXT fixture and is never
        // presented as the real lyrics of the Spotify track named Forever.
        let trackA = fixtureTrack(id: "forever-test", title: "Forever")
        let identityA = TrackIdentity(track: trackA)
        let txtA = Data([0xEF, 0xBB, 0xBF]) + syntheticA
            .replacingOccurrences(of: "\n", with: "\r\n")
            .data(using: .utf8)!
        let parsedA = try TextLyricsImportParser.parse(txtA)
        try require(parsedA.encoding == .utf8BOM, "A encoding")
        try require(parsedA.lines.count == 4, "A line count")

        let editorA = await MainActor.run { () -> LyricsEditorSessionController in
            let editor = LyricsEditorSessionController(repository: repository)
            editor.isStillCurrent = { true }
            editor.beginNew(
                track: trackA,
                identity: identityA,
                document: blankDocument(track: trackA, identity: identityA, source: .manualCreate),
                source: .manualImport,
                revision: 1,
                configuration: AITranslationConfiguration()
            )
            editor.prepareTextImport(data: txtA, source: .manualImport)
            editor.confirmTextImport()
            return editor
        }
        let draftA = await MainActor.run { editorA.draft }
        try require(draftA?.lines.count == 4, "A preview loaded into editor")
        try require(draftA?.lines.allSatisfy { !$0.originalText.isEmpty } == true, "A original text preserved")
        try require(draftA?.lines.allSatisfy { $0.kanaText != nil && $0.romajiText != nil } == true, "A readings generated")
        await MainActor.run { editorA.save(lockLyrics: true) }
        try require(await waitForEditorSave(editorA), "A editor save")

        let storedA = try await repository.loadEditableVersions(track: trackA, identity: identityA)
            .first(where: { $0.record.source == "manualImport" })
        guard let storedA else { throw ContractFailure("A manualImport not persisted") }
        try require(storedA.record.isLocked, "A lyrics locked")
        try require(!storedA.record.isSynced, "A remains plain text")
        try require(storedA.lines.count == 4, "A lines persisted")
        try require(storedA.lines.allSatisfy { $0.startTime == nil && $0.endTime == nil }, "A has no fabricated timing")
        try require(storedA.lines.allSatisfy { $0.kanaText != nil && $0.romajiText != nil }, "A readings persisted")

        // Exercise the production OpenAI-compatible client, parser, session,
        // and SQLite translation repository with an in-memory synthetic HTTP
        // response. No external service and no user credential are used.
        let http = SyntheticHTTPClient()
        let translationService = OpenAICompatibleTranslationService(
            client: OpenAICompatibleClient(httpClient: http),
            keyStore: SyntheticKeyStore()
        )
        let translation = await MainActor.run {
            TranslationSessionController(repository: repository, service: translationService)
        }
        let configuration = AITranslationConfiguration(
            baseURL: "https://synthetic.test/v1",
            model: "synthetic-test-model",
            targetLanguage: "zh-Hans",
            style: "natural_song",
            autoTranslateNewLyrics: false
        )
        await MainActor.run {
            translation.synchronize(
                document: storedA.document,
                lyricsVersionID: storedA.record.id,
                sourceContentHash: storedA.record.contentHash,
                configuration: configuration
            )
            translation.translateCurrentLyrics()
        }
        if !(await waitForTranslation(translation)) {
            let translationDiagnostic = await MainActor.run {
                let error = translation.errorMessage ?? "none"
                return "state=\(translation.state) error=\(error)"
            }
            throw ContractFailure("synthetic AI translation failed: \(translationDiagnostic)")
        }
        let metrics = await http.requestMetrics()
        try require(metrics.0 == 1 && metrics.1, "AI received whole-song context once")
        let candidateID = await MainActor.run { translation.pendingCandidate?.record.id }
        try require(candidateID != nil, "A translation remains an explicit candidate")
        await MainActor.run { translation.adoptTranslation(versionID: candidateID!) }
        for _ in 0..<100 {
            let adopted = await MainActor.run { translation.selectedVersion?.record.id == candidateID }
            if adopted { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let translatedA = await MainActor.run { translation.selectedVersion }
        try require(translatedA?.isComplete == true && translatedA?.lines.count == 4, "A translation adopted and complete")
        await MainActor.run { translation.lockSelected() }
        var lockedTranslation = try await repository.loadTranslationVersions(
            lyricsVersionID: storedA.record.id,
            targetLanguage: "zh-Hans",
            sourceContentHash: storedA.record.contentHash
        ).first
        for _ in 0..<100 where lockedTranslation?.record.isLocked != true {
            try? await Task.sleep(nanoseconds: 20_000_000)
            lockedTranslation = try await repository.loadTranslationVersions(
                lyricsVersionID: storedA.record.id,
                targetLanguage: "zh-Hans",
                sourceContentHash: storedA.record.contentHash
            ).first
        }
        try require(lockedTranslation?.record.isLocked == true, "A translation locked")

        // TEST ONLY: B is the clipboard/manualCreate fixture. It is not the
        // real lyrics of あやふや.
        let trackB = fixtureTrack(id: "ayafuya-test", title: "あやふや")
        let identityB = TrackIdentity(track: trackB)
        let editorB = await MainActor.run { () -> LyricsEditorSessionController in
            let editor = LyricsEditorSessionController(repository: repository)
            editor.isStillCurrent = { true }
            editor.beginNew(
                track: trackB,
                identity: identityB,
                document: blankDocument(track: trackB, identity: identityB, source: .manualCreate),
                source: .manualCreate,
                revision: 2,
                configuration: AITranslationConfiguration()
            )
            editor.prepareTextImport(syntheticB, source: .manualCreate)
            editor.confirmTextImport()
            return editor
        }
        try require(await MainActor.run { editorB.draft?.lines.count == 4 }, "B clipboard preview loaded")
        try require(await MainActor.run { editorB.draft?.lines.allSatisfy { $0.kanaText != nil && $0.romajiText != nil } == true }, "B readings generated")
        await MainActor.run { editorB.save(lockLyrics: true) }
        try require(await waitForEditorSave(editorB), "B editor save")
        let storedB = try await repository.loadEditableVersions(track: trackB, identity: identityB)
            .first(where: { $0.record.source == "manualCreate" })
        try require(storedB?.record.isLocked == true, "B manualCreate locked")
        try require(storedB?.record.isSynced == false, "B remains plain text")
        try require(storedB?.lines.count == 4, "B lines persisted")

        // Simulate switching from A to B while A is still in a pending editor
        // preview. The controller must reject the save and leave the database
        // unchanged.
        let staleEditor = await MainActor.run { () -> LyricsEditorSessionController in
            let editor = LyricsEditorSessionController(repository: repository)
            editor.isStillCurrent = { true }
            editor.beginNew(
                track: trackA,
                identity: identityA,
                document: blankDocument(track: trackA, identity: identityA, source: .manualCreate),
                source: .manualCreate,
                revision: 3,
                configuration: AITranslationConfiguration()
            )
            editor.prepareTextImport(syntheticA, source: .manualCreate)
            editor.confirmTextImport()
            editor.observePlayback(identity: identityB, revision: 4)
            editor.isStillCurrent = { false }
            editor.save(lockLyrics: true)
            return editor
        }
        try require(await MainActor.run { staleEditor.state == .stale }, "cut-song save rejected")
        let versionsAfterStale = try await repository.loadEditableVersions(track: trackA, identity: identityA)
        try require(versionsAfterStale.count == 1, "stale editor did not write A again")

        // Reopen the repository to prove restart recovery from the temporary
        // database, including locked reading and translation layers.
        let restarted = SQLiteLyricsRepository(databaseURL: databaseURL)
        try await restarted.prepare()
        let restoredA = try await restarted.loadBestStored(track: trackA, identity: identityA)
        let restoredB = try await restarted.loadBestStored(track: trackB, identity: identityB)
        try require(restoredA?.document.lines.count == 4, "A restored after restart")
        try require(restoredB?.document.lines.count == 4, "B restored after restart")
        try require(restoredA?.document.isSynchronized == false && restoredB?.document.isSynchronized == false, "restart keeps plain status")
        let restoredTranslations = try await restarted.loadTranslationVersions(
            lyricsVersionID: storedA.record.id,
            targetLanguage: "zh-Hans",
            sourceContentHash: storedA.record.contentHash
        )
        try require(restoredTranslations.count == 1 && restoredTranslations[0].record.isLocked, "translation restored and locked")

        do {
            _ = try TextLyricsImportParser.parse("\u{FEFF}\r\n\n \t")
            throw ContractFailure("empty text accepted")
        } catch TextLyricsImportError.empty {
            // expected
        }

        print("synthetic text lyrics e2e contract passed (TEST fixtures only; no real song lyrics asserted)")
    }

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw ContractFailure(message) }
    }
}

private struct ContractFailure: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { "FAIL: \(message)" }
}
