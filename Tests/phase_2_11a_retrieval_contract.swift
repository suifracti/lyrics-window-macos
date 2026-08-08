import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private final class CountingProvider: LyricsProvider, @unchecked Sendable {
    let name: String
    private let lock = NSLock()
    private var calls = 0
    private let result: LyricsLookupResult

    init(name: String, result: LyricsLookupResult) {
        self.name = name
        self.result = result
    }

    func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult {
        incrementCallCount()
        return result
    }

    private func incrementCallCount() {
        lock.lock()
        calls += 1
        lock.unlock()
    }

    func callCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}

private final class FallbackProvider: LyricsProvider, @unchecked Sendable {
    let name: String
    private let result: LyricsLookupResult

    init(name: String, result: LyricsLookupResult) {
        self.name = name
        self.result = result
    }

    func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult {
        result
    }
}

private final class LocalLaneProvider: LyricsProvider, @unchecked Sendable {
    let name = "Local fixture"
    let executionLane: LyricsProviderExecutionLane = .local
    let timeoutInterval: TimeInterval = 2

    func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult {
        .noMatch
    }
}

private final class DelayedProvider: LyricsProvider, @unchecked Sendable {
    let name: String
    let executionLane: LyricsProviderExecutionLane
    let timeoutInterval: TimeInterval
    private let delay: TimeInterval
    private let result: LyricsLookupResult
    private let lock = NSLock()
    private var calls = 0

    init(
        name: String,
        lane: LyricsProviderExecutionLane = .network,
        timeout: TimeInterval = 8,
        delay: TimeInterval,
        result: LyricsLookupResult
    ) {
        self.name = name
        self.executionLane = lane
        self.timeoutInterval = timeout
        self.delay = delay
        self.result = result
    }

    func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult {
        lock.withLock { calls += 1 }
        do {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } catch {
            return .failed(.cancelled)
        }
        return result
    }

    func callCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}

@main
struct Phase211ARetrievalContract {
    static func main() async {
        let defaultNetworkProvider = FallbackProvider(name: "Network fixture", result: .noMatch)
        require(defaultNetworkProvider.executionLane == .network, "providers default to the network lane")
        require(defaultNetworkProvider.timeoutInterval == 8, "network timeout default")
        let localLaneProvider = LocalLaneProvider()
        require(localLaneProvider.executionLane == .local, "local provider lane")
        require(localLaneProvider.timeoutInterval == 2, "local provider timeout")

        let liveTrack = Track(
            title: "春を告げる - From THE FIRST TAKE",
            artist: "yama",
            album: "春を告げる - From THE FIRST TAKE",
            duration: 300,
            spotifyId: "track-id"
        )
        let liveMetadata = TrackMetadata.bootstrap(from: liveTrack)
        let liveIdentity = TrackIdentity(track: liveTrack)

        func document(source: LyricsSource, providerID: String) -> LyricsDocument {
            LyricsDocument(
                identity: liveIdentity,
                title: liveTrack.title,
                artist: liveTrack.artist,
                album: liveTrack.album,
                duration: liveTrack.duration,
                lines: [LyricLine(timestamp: 0, originalText: "fixture")],
                isSynchronized: true,
                source: source,
                confidence: 1,
                providerSourceID: providerID,
                spotifyTrackID: liveTrack.spotifyId
            )
        }

        let untouchedNetwork = DelayedProvider(
            name: "must-not-run",
            delay: 0.01,
            result: .match(document(source: .lrclib, providerID: "network"))
        )
        let localFirstManager = LyricsSearchManager(providers: [
            DelayedProvider(
                name: "local",
                lane: .local,
                delay: 0,
                result: .match(document(source: .local, providerID: "local"))
            ),
            untouchedNetwork
        ])
        guard case .match(let localDocument) = await localFirstManager.lookup(
            track: liveTrack,
            identity: liveIdentity
        ) else {
            preconditionFailure("local exact match should be adopted")
        }
        require(localDocument.source == .local, "local lane wins before network")
        require(untouchedNetwork.callCount() == 0, "local match must prevent network probes")

        let concurrentManager = LyricsSearchManager(providers: [
            DelayedProvider(name: "slow miss", delay: 0.20, result: .noMatch),
            DelayedProvider(
                name: "slow match",
                delay: 0.20,
                result: .match(document(source: .amll, providerID: "concurrent"))
            )
        ])
        let concurrentStart = Date()
        guard case .match = await concurrentManager.lookup(track: liveTrack, identity: liveIdentity) else {
            preconditionFailure("concurrent network fallback should match")
        }
        require(
            Date().timeIntervalSince(concurrentStart) < 0.34,
            "network providers must complete near the slower single delay, not their sum"
        )

        let timeoutManager = LyricsSearchManager(providers: [
            DelayedProvider(name: "timeout", timeout: 0.05, delay: 0.30, result: .noMatch),
            DelayedProvider(
                name: "match after timeout",
                delay: 0.03,
                result: .match(document(source: .qqExperimental, providerID: "timeout-fallback"))
            )
        ])
        let timeoutStart = Date()
        guard case .match(let timeoutFallback) = await timeoutManager.lookup(
            track: liveTrack,
            identity: liveIdentity
        ) else {
            preconditionFailure("one provider timeout must not suppress another match")
        }
        require(timeoutFallback.source == .qqExperimental, "post-timeout provider match")
        require(Date().timeIntervalSince(timeoutStart) < 0.18, "provider timeout must bound the variant")

        let orderedManager = LyricsSearchManager(providers: [
            DelayedProvider(
                name: "configured first",
                delay: 0.14,
                result: .match(document(source: .lrclib, providerID: "first"))
            ),
            DelayedProvider(
                name: "finishes first",
                delay: 0.01,
                result: .match(document(source: .amll, providerID: "second"))
            )
        ])
        guard case .match(let orderedDocument) = await orderedManager.lookup(
            track: liveTrack,
            identity: liveIdentity
        ) else {
            preconditionFailure("configured provider priority should produce a match")
        }
        require(orderedDocument.source == .lrclib, "completion order must not replace configured priority")

        let cancellationManager = LyricsSearchManager(providers: [
            DelayedProvider(name: "cancellable", delay: 1, result: .noMatch)
        ])
        let cancelledTask = Task {
            await cancellationManager.lookup(track: liveTrack, identity: liveIdentity)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        cancelledTask.cancel()
        if case .failed(.cancelled) = await cancelledTask.value {} else {
            preconditionFailure("cancelled search must return cancelled")
        }

        let versionPlan = LyricsQueryPlanner.plan(for: liveMetadata)
        require(
            versionPlan.contains {
                $0.queryKind == .normalizedVersionTitleFullArtist
                    && $0.titleQuery == "春を告げる"
                    && $0.artistQuery == "yama"
            },
            "version-stripped query must preserve the full artist"
        )
        let multiVersionTrack = Track(
            title: "Forever - Live",
            artist: "VILLSHANA, Mahiru",
            album: "KILL is LOVE",
            duration: 169
        )
        let multiVersionPlan = LyricsQueryPlanner.plan(
            for: TrackMetadata.bootstrap(from: multiVersionTrack)
        )
        require(
            multiVersionPlan.contains { $0.queryKind == .normalizedVersionTitlePrimaryArtist },
            "version-stripped primary-artist fallback"
        )

        let manualPlan = LyricsQueryPlanner.plan(
            for: liveMetadata,
            manualQuery: "Haru wo Tsugeru yama"
        )
        require(manualPlan.first?.queryKind == .manualOverride, "manual query must run first")
        require(manualPlan.first?.titleQuery == "Haru wo Tsugeru yama", "manual query is preserved")

        let aliasMetadata = TrackMetadata(
            identity: liveMetadata.identity,
            track: liveMetadata.track,
            aliases: liveMetadata.aliases + [
                TrackAlias(
                    id: "english-title",
                    field: .title,
                    kind: .officialEnglish,
                    value: "Spring Is Coming",
                    language: "en",
                    script: .latin,
                    source: .spotifyMetadata,
                    confidence: 1,
                    isOfficial: true
                )
            ],
            versionTags: liveMetadata.versionTags
        )
        require(
            LyricsQueryPlanner.plan(for: aliasMetadata).contains { $0.queryKind == .officialEnglishAlias },
            "persisted official alias must be queryable"
        )

        let candidateTrack = Track(
            title: "Forever",
            artist: "VILLSHANA, Mahiru",
            album: "KILL is LOVE",
            duration: 169,
            spotifyId: "forever-id"
        )
        let candidateIdentity = TrackIdentity(track: candidateTrack)
        let featuredCandidate = LyricsCandidate(
            id: "netease:42",
            identity: candidateIdentity,
            title: "Forever",
            artist: "VILLSHANA",
            album: candidateTrack.album,
            duration: candidateTrack.duration,
            lines: [LyricLine(timestamp: 0, originalText: "Forever")],
            source: .neteaseExperimental,
            confidence: 0.8,
            providerSourceID: "42"
        )
        let candidateProvider = CountingProvider(name: "网易云实验源", result: .candidates([featuredCandidate]))
        let candidateManager = LyricsSearchManager(providers: [candidateProvider])
        let candidateOutcome = await candidateManager.search(track: candidateTrack, identity: candidateIdentity)
        guard case .candidates(let candidates) = candidateOutcome.result,
              let enriched = candidates.first else {
            preconditionFailure("expected a user-selectable candidate")
        }
        require(enriched.providerName == "网易云实验源", "candidate provider explanation")
        require(enriched.queryKind != nil, "candidate query method explanation")
        require(!enriched.matchExplanation.isEmpty, "candidate match explanation")
        require(enriched.matchExplanation.contains { $0.contains("titleExact") }, "title evidence explanation")
        require(enriched.matchExplanation.contains { $0.contains("primaryArtistExact") }, "artist evidence explanation")
        require(enriched.matchScore != nil, "safe matcher score explanation")

        let noMatchProvider = CountingProvider(name: "LRCLIB", result: .noMatch)
        let noMatchManager = LyricsSearchManager(providers: [noMatchProvider])
        let first = await noMatchManager.search(track: liveTrack, identity: TrackIdentity(track: liveTrack))
        let callsAfterFirst = noMatchProvider.callCount()
        let second = await noMatchManager.search(track: liveTrack, identity: TrackIdentity(track: liveTrack))
        let callsAfterSecond = noMatchProvider.callCount()
        require(callsAfterFirst > 0, "no-match search should query a provider")
        require(callsAfterSecond == callsAfterFirst, "short negative cache should avoid duplicate automatic requests")
        if case .noMatch = first.result {} else { preconditionFailure("first result should be noMatch") }
        if case .noMatch = second.result {} else { preconditionFailure("cached result should remain noMatch") }

        let mixedFailureManager = LyricsSearchManager(providers: [
            FallbackProvider(name: "本地歌词", result: .noMatch),
            FallbackProvider(name: "LRCLIB", result: .failed(.networkUnavailable))
        ])
        let mixedFailure = await mixedFailureManager.search(
            track: liveTrack,
            identity: TrackIdentity(track: liveTrack)
        )
        if case .failed(.networkUnavailable) = mixedFailure.result {} else {
            preconditionFailure("network failure must not be disguised as noMatch")
        }

        _ = await noMatchManager.search(
            track: liveTrack,
            identity: TrackIdentity(track: liveTrack),
            forceRefresh: true
        )
        require(noMatchProvider.callCount() > callsAfterSecond, "explicit retry must bypass negative cache")

        let fallbackDocument = LyricsDocument(
            identity: TrackIdentity(track: liveTrack),
            title: liveTrack.title,
            artist: liveTrack.artist,
            album: liveTrack.album,
            duration: liveTrack.duration,
            lines: [LyricLine(timestamp: 0, originalText: "fallback")],
            isSynchronized: false,
            source: .qqExperimental,
            confidence: 0.95,
            providerSourceID: "qq:42",
            spotifyTrackID: liveTrack.spotifyId
        )
        let fallbackManager = LyricsSearchManager(providers: [
            FallbackProvider(name: "LRCLIB", result: .failed(.networkUnavailable)),
            FallbackProvider(name: "QQ 音乐实验源", result: .match(fallbackDocument))
        ])
        let fallback = await fallbackManager.search(track: liveTrack, identity: TrackIdentity(track: liveTrack))
        guard case .match(let adopted) = fallback.result else {
            preconditionFailure("provider failure must fall through to the next provider")
        }
        require(adopted.source == .qqExperimental, "fallback source adopted")

        print("phase 2.11A retrieval contract passed")
    }
}
