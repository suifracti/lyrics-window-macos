import Combine
import Foundation

@MainActor
public final class LyricsSessionController: ObservableObject {
    @Published public private(set) var state: LyricsLoadState = .idle
    @Published public private(set) var lyrics: [LyricLine] = []
    @Published public private(set) var isSynchronized = true
    @Published public private(set) var activeIdentity: TrackIdentity?
    @Published public private(set) var activeLyricsVersionID: UUID?
    @Published public private(set) var activeSourceContentHash: String?
    @Published public private(set) var revision: UInt64 = 0
    @Published public private(set) var persistenceStatusMessage: String?

    private let searchManager: LyricsSearchManager
    private let repository: (any LyricsRepository)?
    private var requestTask: Task<Void, Never>?
    private var automaticRecoveryRetryIdentity: TrackIdentity?
    private var activeTrack: Track?

    /// Primary production path: multi-variant LyricsSearchManager (not a dead Orchestrator).
    public init(
        providers: [LyricsProvider],
        name: String = "LyricsSearchManager",
        repository: (any LyricsRepository)? = nil
    ) {
        self.searchManager = LyricsSearchManager(providers: providers, name: name)
        self.repository = repository
    }

    /// Test/compat wrapper around a single composite provider.
    public convenience init(provider: LyricsProvider) {
        if let composite = provider as? CompositeLyricsProvider {
            self.init(providers: composite.underlyingProviders, name: composite.name)
        } else {
            self.init(providers: [provider], name: provider.name)
        }
    }

    deinit {
        requestTask?.cancel()
    }

    public var activeDocument: LyricsDocument? {
        state.document
    }

    public func autoComplete(track: Track, identity: TrackIdentity) {
        begin(track: track, identity: identity)
    }

    public func updateProviders(_ providers: [LyricsProvider]) {
        searchManager.updateProviders(providers)
        requestTask?.cancel()
        requestTask = nil
        revision &+= 1
    }

    public func begin(
        track: Track,
        identity: TrackIdentity,
        automaticallySearch: Bool = true
    ) {
        cancelCurrentRequest()
        revision &+= 1
        let requestRevision = revision
        if activeIdentity != identity {
            automaticRecoveryRetryIdentity = nil
        }
        activeIdentity = identity
        activeTrack = track
        activeLyricsVersionID = nil
        activeSourceContentHash = nil
        persistenceStatusMessage = nil
        lyrics = []
        isSynchronized = true
        state = .loading(identity)

        LyricsE2ELog.log(
            "SESSION begin rev=\(requestRevision) identity=\(identity.stableKey) title=\(track.title) artist=\(track.artist) duration=\(track.duration) spotifyId=\(track.spotifyId ?? "")"
        )

        guard automaticallySearch else {
            state = .idle
            LyricsE2ELog.log("SESSION automatic search disabled identity=\(identity.stableKey)")
            return
        }

        requestTask = Task { [weak self, searchManager, repository] in
            var outcome: SearchOutcome?
            var cachedReference: StoredLyricsDocument?
            var persistenceError: String?
            var repositoryReady = false

            if let repository {
                do {
                    try await repository.prepare()
                    repositoryReady = true
                    if let cached = try await repository.loadBestStored(track: track, identity: identity) {
                        cachedReference = cached
                        LyricsE2ELog.log(
                            "SESSION persistence hit rev=\(requestRevision) source=\(cached.document.source) provider=\(cached.document.providerSourceID ?? "") lines=\(cached.document.lines.count) sync=\(cached.document.isSynchronized)"
                        )
                        outcome = SearchOutcome(result: .match(cached.document), diagnostics: [])
                    } else {
                        LyricsE2ELog.log("SESSION persistence miss rev=\(requestRevision) identity=\(identity.stableKey)")
                    }
                } catch {
                    persistenceError = error.localizedDescription
                    LyricsE2ELog.log("PERSISTENCE prepare/load failed rev=\(requestRevision) error=\(error.localizedDescription)")
                }
            }

            if outcome == nil, !Task.isCancelled {
                let searched = await searchManager.search(track: track, identity: identity)
                outcome = searched
            }

            guard let outcome else { return }
            guard !Task.isCancelled else {
                LyricsE2ELog.log("SESSION cancelled before apply rev=\(requestRevision)")
                return
            }
            LyricsE2ELog.log("SESSION search finished rev=\(requestRevision) result=\(Self.describe(outcome.result)) diag=\(outcome.diagnostics.count)")
            for d in outcome.diagnostics {
                LyricsE2ELog.log("  DIAG \(d.provider) \(Self.describeDiag(d.outcome)) \(String(format: "%.2f", d.duration))s")
            }
            let didApply = await MainActor.run { [weak self] () -> Bool in
                guard let self,
                      self.activeIdentity == identity,
                      self.revision == requestRevision else {
                    let currentRevision = self?.revision.description ?? "none"
                    LyricsE2ELog.log("SESSION drop stale result rev=\(requestRevision) current=\(currentRevision)")
                    return false
                }
                self.persistenceStatusMessage = persistenceError
                self.apply(outcome.result, identity: identity, requestRevision: requestRevision)
                if let cachedReference {
                    self.activeLyricsVersionID = cachedReference.versionID
                    self.activeSourceContentHash = cachedReference.sourceContentHash
                }
                return true
            }

            // Persist only after the current Session has accepted the match.
            // This prevents a late result from a cancelled track request from
            // being written as if it belonged to the next playback session.
            if didApply,
               repositoryReady,
               case .match(let document) = outcome.result,
               !Task.isCancelled,
               document.identity == identity,
               !document.lines.isEmpty,
               LyricsMatcher.isHighConfidence(document.confidence) {
                do {
                    let saved = try await repository?.save(
                        track: track,
                        identity: identity,
                        document: document
                    )
                    LyricsE2ELog.log(
                        "SESSION persistence save rev=\(requestRevision) disposition=\(String(describing: saved?.disposition)) lines=\(document.lines.count)"
                    )
                    if let saved, saved.versionID != nil {
                        await MainActor.run { [weak self] in
                            guard let self, self.activeIdentity == identity else { return }
                            self.activeLyricsVersionID = saved.versionID
                            self.activeSourceContentHash = saved.sourceContentHash
                        }
                    }
                } catch {
                    let message = error.localizedDescription
                    LyricsE2ELog.log("PERSISTENCE save failed rev=\(requestRevision) error=\(message)")
                    await MainActor.run { [weak self] in
                        guard let self, self.activeIdentity == identity else { return }
                        self.persistenceStatusMessage = message
                    }
                }
            }
        }
    }

    public func beginLoadingPlaceholder(identity: TrackIdentity, message: String = "") {
        cancelCurrentRequest()
        revision &+= 1
        activeIdentity = identity
        activeLyricsVersionID = nil
        activeSourceContentHash = nil
        lyrics = []
        isSynchronized = true
        state = .loading(identity)
        LyricsE2ELog.log("SESSION placeholder identity=\(identity.stableKey) msg=\(message)")
    }

    public func fail(identity: TrackIdentity, failure: LyricsFailure) {
        guard activeIdentity == identity else { return }
        cancelCurrentRequest()
        revision &+= 1
        lyrics = []
        isSynchronized = true
        state = .failed(identity, failure)
        LyricsE2ELog.log("SESSION fail identity=\(identity.stableKey) \(failure)")
    }

    public func retry(track: Track, identity: TrackIdentity) {
        autoComplete(track: track, identity: identity)
    }

    @discardableResult
    public func retryAfterNetworkRecovery(track: Track, identity: TrackIdentity) -> Bool {
        guard activeIdentity == identity,
              case .failed(let failedIdentity, .networkUnavailable) = state,
              failedIdentity == identity,
              automaticRecoveryRetryIdentity != identity else {
            return false
        }
        automaticRecoveryRetryIdentity = identity
        begin(track: track, identity: identity)
        return true
    }

    public func clear() {
        cancelCurrentRequest()
        revision &+= 1
        activeIdentity = nil
        activeLyricsVersionID = nil
        activeSourceContentHash = nil
        activeTrack = nil
        automaticRecoveryRetryIdentity = nil
        lyrics = []
        isSynchronized = true
        state = .idle
        LyricsE2ELog.log("SESSION clear")
    }

    public func enterMockPreview(lines: [LyricLine]) {
        cancelCurrentRequest()
        revision &+= 1
        activeIdentity = nil
        activeLyricsVersionID = nil
        activeSourceContentHash = nil
        activeTrack = nil
        automaticRecoveryRetryIdentity = nil
        lyrics = lines
        isSynchronized = true
        state = .mockPreview
        LyricsE2ELog.log("SESSION mockPreview lines=\(lines.count)")
    }

    public func adopt(candidate: LyricsCandidate) {
        guard activeIdentity == candidate.identity else {
            LyricsE2ELog.log("SESSION adopt candidate REJECT identity mismatch")
            return
        }
        guard !candidate.lines.isEmpty else {
            lyrics = []
            state = .noLyrics(candidate.identity)
            return
        }
        let document = LyricsDocument(
            identity: candidate.identity,
            title: candidate.title,
            artist: candidate.artist,
            album: candidate.album,
            duration: candidate.duration,
            lines: candidate.lines,
            isSynchronized: candidate.isSynchronized,
            source: candidate.source,
            confidence: candidate.confidence,
            providerSourceID: candidate.providerSourceID
        )
        applyLoadedDocument(document, identity: candidate.identity)
        persistAdoptedDocument(document)
    }

    public func adopt(document: LyricsDocument) {
        guard activeIdentity == document.identity else {
            LyricsE2ELog.log("SESSION adopt document REJECT identity mismatch")
            return
        }
        cancelCurrentRequest()
        revision &+= 1
        applyLoadedDocument(document, identity: document.identity)
        persistAdoptedDocument(document)
    }

    /// Applies a version that has already been committed by the editing
    /// repository. Unlike `adopt(document:)`, this does not write the same
    /// document back again; it only refreshes the live session's identity,
    /// version id and source fingerprint.
    public func adoptPersisted(
        document: LyricsDocument,
        versionID: UUID,
        sourceContentHash: String
    ) {
        guard activeIdentity == document.identity else {
            LyricsE2ELog.log("SESSION adopt persisted REJECT identity mismatch")
            return
        }
        cancelCurrentRequest()
        revision &+= 1
        activeLyricsVersionID = versionID
        applyLoadedDocument(document, identity: document.identity)
        activeSourceContentHash = sourceContentHash
        LyricsE2ELog.log("SESSION adopt persisted version=\(versionID.uuidString) source=\(document.source)")
    }


    /// Keep plain lyrics visible while alignment runs.
    public func beginAlignment(identity: TrackIdentity, plain: LyricsDocument) {
        guard activeIdentity == identity else { return }
        cancelCurrentRequest()
        revision &+= 1
        lyrics = plain.lines
        isSynchronized = false
        state = .alignmentRunning(identity, plain, 0)
        LyricsE2ELog.log("SESSION alignmentRunning start lines=\(plain.lines.count)")
    }

    public func updateAlignmentProgress(identity: TrackIdentity, plain: LyricsDocument, progress: Double) {
        guard activeIdentity == identity else { return }
        if case .alignmentRunning = state {
            state = .alignmentRunning(identity, plain, min(1, max(0, progress)))
        }
    }

    /// Preview timed lyrics without committing as final locked/synced state.
    public func presentAlignmentPreview(
        identity: TrackIdentity,
        plain: LyricsDocument,
        timed: LyricsDocument,
        report: AlignmentReport
    ) {
        guard activeIdentity == identity else { return }
        cancelCurrentRequest()
        revision &+= 1
        lyrics = timed.lines
        isSynchronized = true // allow scrub preview; still marked as preview in state
        state = .alignmentPreview(identity, plain: plain, timed: timed, report: report)
        LyricsE2ELog.log("SESSION alignmentPreview lines=\(timed.lines.count) overall=\(report.overallConfidence) low=\(report.lowConfidenceCount)")
    }

    public func cancelAlignmentPreview(identity: TrackIdentity, plain: LyricsDocument) {
        guard activeIdentity == identity else { return }
        cancelCurrentRequest()
        revision &+= 1
        applyLoadedDocument(plain, identity: identity)
        LyricsE2ELog.log("SESSION alignmentPreview cancelled -> plain")
    }

    public func confirmAlignment(
        identity: TrackIdentity,
        timed: LyricsDocument,
        report: AlignmentReport,
        saveLocal: Bool
    ) throws -> URL? {
        guard activeIdentity == identity else { return nil }
        cancelCurrentRequest()
        revision &+= 1
        var confirmed = timed
        // Confirm as synchronized automatic alignment result.
        confirmed = LyricsDocument(
            identity: timed.identity,
            title: timed.title,
            artist: timed.artist,
            album: timed.album,
            duration: timed.duration,
            lines: timed.lines,
            isSynchronized: true,
            source: .automaticAlignment,
            confidence: report.overallConfidence,
            providerSourceID: timed.providerSourceID
        )
        lyrics = confirmed.lines
        isSynchronized = true
        state = .loaded(confirmed)
        LyricsE2ELog.log("SESSION alignment confirmed lines=\(confirmed.lines.count)")
        persistAdoptedDocument(confirmed)
        guard saveLocal else { return nil }
        return try LocalAlignedLyricsStore.save(document: confirmed, report: report, manuallyCorrected: false)
    }

    private func applyLoadedDocument(_ document: LyricsDocument, identity: TrackIdentity) {
        let enrichedLines = LyricsLayerEnricher.enrich(lines: document.lines)
        let enriched = LyricsDocument(
            identity: identity,
            title: document.title,
            artist: document.artist,
            album: document.album,
            duration: document.duration,
            lines: enrichedLines,
            isSynchronized: document.isSynchronized,
            source: document.source,
            confidence: document.confidence,
            providerSourceID: document.providerSourceID
        )
        lyrics = enriched.lines
        isSynchronized = enriched.isSynchronized
        activeSourceContentHash = LyricsPersistenceMapper.sourceContentHash(document: enriched)
        if enriched.lines.isEmpty {
            state = .noLyrics(identity)
            LyricsE2ELog.log("SESSION apply empty -> noLyrics source=\(enriched.source)")
        } else if enriched.isSynchronized {
            state = .loaded(enriched)
            LyricsE2ELog.log("SESSION apply loaded source=\(enriched.source) lines=\(enriched.lines.count) first=\(enriched.lines.first?.originalText ?? "")")
        } else {
            // Plain text: show full lyrics, never fake synced scrolling.
            state = .alignmentQueued(identity, enriched)
            LyricsE2ELog.log("SESSION apply alignmentQueued source=\(enriched.source) lines=\(enriched.lines.count) first=\(enriched.lines.first?.originalText ?? "")")
        }
    }

    private func apply(
        _ result: LyricsLookupResult,
        identity: TrackIdentity,
        requestRevision: UInt64
    ) {
        guard activeIdentity == identity, revision == requestRevision else {
            LyricsE2ELog.log("SESSION drop stale result rev=\(requestRevision) current=\(revision)")
            return
        }

        switch result {
        case .match(let document):
            guard document.identity == identity else {
                lyrics = []
                state = .failed(identity, .unknown("歌词身份与当前歌曲不一致"))
                LyricsE2ELog.log("SESSION match identity mismatch")
                return
            }
            applyLoadedDocument(document, identity: identity)
        case .candidates(let candidates):
            lyrics = []
            isSynchronized = true
            state = .candidates(identity, candidates)
            LyricsE2ELog.log("SESSION candidates count=\(candidates.count)")
        case .noLyrics:
            lyrics = []
            isSynchronized = true
            state = .noLyrics(identity)
            LyricsE2ELog.log("SESSION noLyrics")
        case .noMatch:
            lyrics = []
            isSynchronized = true
            state = .noMatch(identity)
            LyricsE2ELog.log("SESSION noMatch")
        case .failed(let failure):
            lyrics = []
            isSynchronized = true
            state = .failed(identity, failure)
            LyricsE2ELog.log("SESSION failed \(failure)")
        }
    }

    private func cancelCurrentRequest() {
        requestTask?.cancel()
        requestTask = nil
    }

    private func persistAdoptedDocument(_ document: LyricsDocument) {
        guard let repository, let activeTrack,
              activeIdentity == document.identity,
              !document.lines.isEmpty else { return }
        let identity = document.identity
        Task { [weak self] in
            do {
                let result = try await repository.save(
                    track: activeTrack,
                    identity: identity,
                    document: document
                )
                LyricsE2ELog.log(
                    "SESSION adopted persistence disposition=\(String(describing: result.disposition)) source=\(document.source) lines=\(document.lines.count)"
                )
                if let versionID = result.versionID {
                    await MainActor.run { [weak self] in
                        guard let self, self.activeIdentity == identity else { return }
                        self.activeLyricsVersionID = versionID
                        self.activeSourceContentHash = result.sourceContentHash
                    }
                }
            } catch {
                LyricsE2ELog.log("PERSISTENCE adopted save failed error=\(error.localizedDescription)")
                await MainActor.run {
                    guard let self, self.activeIdentity == identity else { return }
                    self.persistenceStatusMessage = error.localizedDescription
                }
            }
        }
    }

    private static func describe(_ result: LyricsLookupResult) -> String {
        switch result {
        case .match(let d): return "match(\(d.source),lines=\(d.lines.count),sync=\(d.isSynchronized))"
        case .candidates(let c): return "candidates(\(c.count))"
        case .noLyrics: return "noLyrics"
        case .noMatch: return "noMatch"
        case .failed(let f): return "failed(\(f))"
        }
    }

    private static func describeDiag(_ o: LyricsProviderDiagnostic.Outcome) -> String {
        switch o {
        case .match: return "match"
        case .candidates(let n): return "candidates(\(n))"
        case .noLyrics: return "noLyrics"
        case .noMatch: return "noMatch"
        case .failed(let f): return "failed(\(f))"
        }
    }
}
