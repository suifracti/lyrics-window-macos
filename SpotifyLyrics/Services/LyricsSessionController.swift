import Combine
import Foundation

@MainActor
public final class LyricsSessionController: ObservableObject {
    @Published public private(set) var state: LyricsLoadState = .idle
    @Published public private(set) var lyrics: [LyricLine] = []
    @Published public private(set) var isSynchronized = true
    @Published public private(set) var activeIdentity: TrackIdentity?
    @Published public private(set) var revision: UInt64 = 0

    private let searchManager: LyricsSearchManager
    private var requestTask: Task<Void, Never>?
    private var automaticRecoveryRetryIdentity: TrackIdentity?

    /// Primary production path: multi-variant LyricsSearchManager (not a dead Orchestrator).
    public init(providers: [LyricsProvider], name: String = "LyricsSearchManager") {
        self.searchManager = LyricsSearchManager(providers: providers, name: name)
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

    public func autoComplete(track: Track, identity: TrackIdentity) {
        begin(track: track, identity: identity)
    }

    public func begin(track: Track, identity: TrackIdentity) {
        cancelCurrentRequest()
        revision &+= 1
        let requestRevision = revision
        if activeIdentity != identity {
            automaticRecoveryRetryIdentity = nil
        }
        activeIdentity = identity
        lyrics = []
        isSynchronized = true
        state = .loading(identity)

        LyricsE2ELog.log(
            "SESSION begin rev=\(requestRevision) identity=\(identity.stableKey) title=\(track.title) artist=\(track.artist) duration=\(track.duration) spotifyId=\(track.spotifyId ?? "")"
        )

        requestTask = Task { [weak self, searchManager] in
            let outcome = await searchManager.search(track: track, identity: identity)
            guard !Task.isCancelled else {
                LyricsE2ELog.log("SESSION cancelled before apply rev=\(requestRevision)")
                return
            }
            LyricsE2ELog.log("SESSION search finished rev=\(requestRevision) result=\(Self.describe(outcome.result)) diag=\(outcome.diagnostics.count)")
            for d in outcome.diagnostics {
                LyricsE2ELog.log("  DIAG \(d.provider) \(Self.describeDiag(d.outcome)) \(String(format: "%.2f", d.duration))s")
            }
            await MainActor.run {
                self?.apply(outcome.result, identity: identity, requestRevision: requestRevision)
            }
        }
    }

    public func beginLoadingPlaceholder(identity: TrackIdentity, message: String = "") {
        cancelCurrentRequest()
        revision &+= 1
        activeIdentity = identity
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
            confidence: candidate.confidence
        )
        applyLoadedDocument(document, identity: candidate.identity)
    }

    public func adopt(document: LyricsDocument) {
        guard activeIdentity == document.identity else {
            LyricsE2ELog.log("SESSION adopt document REJECT identity mismatch")
            return
        }
        cancelCurrentRequest()
        revision &+= 1
        applyLoadedDocument(document, identity: document.identity)
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
            confidence: report.overallConfidence
        )
        lyrics = confirmed.lines
        isSynchronized = true
        state = .loaded(confirmed)
        LyricsE2ELog.log("SESSION alignment confirmed lines=\(confirmed.lines.count)")
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
            confidence: document.confidence
        )
        lyrics = enriched.lines
        isSynchronized = enriched.isSynchronized
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
