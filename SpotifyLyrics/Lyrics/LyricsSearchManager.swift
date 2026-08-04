import Foundation

/// Multi-variant lyrics search: Local → other providers, one provider at a time per variant.
/// Applies SafeMatcher and does not auto-adopt conflicting versions.
public final class LyricsSearchManager: @unchecked Sendable {
    public let name: String
    private let providersLock = NSLock()
    private let negativeCacheLock = NSLock()
    private var providers: [LyricsProvider]
    private var negativeCache: [String: NegativeCacheEntry] = [:]
    private let negativeCacheLifetime: TimeInterval

    private struct NegativeCacheEntry {
        let result: NegativeResult
        let expiresAt: Date
    }

    private enum NegativeResult {
        case noLyrics
        case noMatch

        var lookupResult: LyricsLookupResult {
            switch self {
            case .noLyrics: return .noLyrics
            case .noMatch: return .noMatch
            }
        }
    }

    public init(
        providers: [LyricsProvider],
        name: String = "Lyrics Search",
        negativeCacheLifetime: TimeInterval = 45
    ) {
        self.providers = providers
        self.name = name
        self.negativeCacheLifetime = max(1, negativeCacheLifetime)
    }

    /// Replaces the runtime provider order without exposing provider objects
    /// to SwiftUI. The active session cancels its in-flight request before
    /// calling this method, so a disabled provider cannot receive a new probe.
    public func updateProviders(_ providers: [LyricsProvider]) {
        providersLock.lock()
        self.providers = providers
        providersLock.unlock()
        clearNegativeCache()
        LyricsE2ELog.log("MANAGER providers updated=" + providers.map { $0.name }.joined(separator: ","))
    }

    public func providerNames() -> [String] {
        providerSnapshot().map(\.name)
    }

    private func providerSnapshot() -> [LyricsProvider] {
        providersLock.lock()
        defer { providersLock.unlock() }
        return providers
    }

    public func lookup(
        track: Track,
        identity: TrackIdentity,
        queryOverride: String? = nil,
        forceRefresh: Bool = false,
        aliases: [TrackAlias] = []
    ) async -> LyricsLookupResult {
        let outcome = await search(
            track: track,
            identity: identity,
            queryOverride: queryOverride,
            forceRefresh: forceRefresh,
            aliases: aliases
        )
        return outcome.result
    }

    public func search(
        track: Track,
        identity: TrackIdentity,
        queryOverride: String? = nil,
        forceRefresh: Bool = false,
        aliases: [TrackAlias] = []
    ) async -> SearchOutcome {
        if Task.isCancelled {
            return SearchOutcome(result: .failed(.cancelled), diagnostics: [])
        }

        let metadata = TrackMetadata.bootstrap(from: track)
        let mergedAliases = Self.mergeAliases(metadata.aliases, aliases)
        // Keep identity stable with caller-supplied identity (playback).
        let meta = TrackMetadata(
            identity: identity,
            track: track,
            aliases: mergedAliases,
            versionTags: metadata.versionTags
        )
        let variants = LyricsQueryPlanner.plan(for: meta, manualQuery: queryOverride)
        let cacheKey = Self.negativeCacheKey(
            identity: identity,
            queryOverride: queryOverride
        )
        if forceRefresh {
            removeNegativeCache(for: cacheKey)
        } else if let cached = cachedNegativeResult(for: cacheKey) {
            LyricsE2ELog.log("MANAGER negative-cache hit identity=\(identity.stableKey) result=\(cached)")
            return SearchOutcome(result: cached.lookupResult, diagnostics: [])
        }
        let configuredProviders = providerSnapshot()
        LyricsE2ELog.log("MANAGER start title=\(track.title) artist=\(track.artist) variants=\(variants.count) providers=\(configuredProviders.map { $0.name }) queryOverride=\(queryOverride ?? "")")
        var diagnostics: [LyricsProviderDiagnostic] = []
        var acceptedCandidates: [String: LyricsCandidate] = [:]
        var sawNoLyrics = false
        var sawNoMatch = false
        var firstFailure: LyricsFailure?

        func alias(for variant: LyricsQueryVariant) -> TrackAlias? {
            guard let id = variant.aliasIDs.first else { return nil }
            return meta.aliases.first { $0.id == id }
        }

        for variant in variants {
            if Task.isCancelled {
                return SearchOutcome(result: .failed(.cancelled), diagnostics: diagnostics)
            }

            let probeTrack = Track(
                id: track.id,
                title: variant.titleQuery,
                artist: variant.artistQuery ?? track.artist,
                album: track.album,
                duration: track.duration,
                artworkName: track.artworkName,
                isrc: track.isrc,
                spotifyId: track.spotifyId,
                artworkURL: track.artworkURL,
                spotifyURL: track.spotifyURL
            )

            for provider in configuredProviders {
                if Task.isCancelled {
                    return SearchOutcome(result: .failed(.cancelled), diagnostics: diagnostics)
                }

                let started = Date()
                let result = await provider.lookup(track: probeTrack, identity: identity)
                let elapsed = Date().timeIntervalSince(started)

                switch result {
                case .match(let document):
                    guard document.identity == identity else {
                        diagnostics.append(
                            LyricsProviderDiagnostic(
                                provider: "\(provider.name)@\(variant.strategy.rawValue)",
                                outcome: .failed(.unknown("歌词身份不一致")),
                                duration: elapsed
                            )
                        )
                        continue
                    }

                    let candidateID = document.providerSourceID.map {
                        "\(provider.name):document:\($0)"
                    } ?? "\(provider.name):document:\(document.title ?? probeTrack.title)"
                    let candidate = LyricsCandidate(
                        id: candidateID,
                        identity: identity,
                        title: document.title ?? probeTrack.title,
                        artist: document.artist ?? probeTrack.artist,
                        album: document.album ?? track.album,
                        duration: document.duration ?? track.duration,
                        lines: document.lines,
                        isSynchronized: document.isSynchronized,
                        source: document.source,
                        confidence: document.confidence,
                        providerSourceID: document.providerSourceID,
                        spotifyTrackID: document.spotifyTrackID,
                        isrc: document.isrc,
                        language: document.language
                    )
                    let decision = LyricsSafeMatcher.decide(
                        candidate: candidate,
                        metadata: meta,
                        aliasUsed: alias(for: variant),
                        queryVariant: variant
                    )
                    diagnostics.append(
                        LyricsProviderDiagnostic(
                            provider: "\(provider.name)@\(variant.strategy.rawValue)",
                            outcome: .match,
                            duration: elapsed,
                            matchDecisions: [decision]
                        )
                    )

                    if decision.tier == .autoHigh || decision.tier == .autoMedium {
                        let enriched = Self.finalizeDocument(document, identity: identity)
                        LyricsE2ELog.log("MANAGER AUTO_ADOPT provider=\(provider.name) strategy=\(variant.strategy.rawValue) kind=\(variant.queryKind.rawValue) tier=\(decision.tier) score=\(decision.score) evidence=\(decision.explanation.joined(separator: ";")) lines=\(enriched.lines.count) sync=\(enriched.isSynchronized)")
                        return SearchOutcome(result: .match(enriched), diagnostics: diagnostics)
                    }
                    if decision.tier == .candidates {
                        Self.acceptCandidate(
                            candidate,
                            provider: provider.name,
                            variant: variant,
                            decision: decision,
                            into: &acceptedCandidates
                        )
                    }
                    // reject → ignore

                case .candidates(let list):
                    var candidateDecisions: [LyricsMatchDecision] = []
                    var autoAdoption: (LyricsCandidate, LyricsMatchDecision)?
                    for item in list where item.identity == identity {
                        let decision = LyricsSafeMatcher.decide(
                            candidate: item,
                            metadata: meta,
                            aliasUsed: alias(for: variant),
                            queryVariant: variant
                        )
                        candidateDecisions.append(decision)
                        if decision.tier == .autoHigh || decision.tier == .autoMedium {
                            autoAdoption = (item, decision)
                            break
                        }
                        if decision.tier == .candidates {
                            Self.acceptCandidate(
                                item,
                                provider: provider.name,
                                variant: variant,
                                decision: decision,
                                into: &acceptedCandidates
                            )
                        }
                    }
                    diagnostics.append(
                        LyricsProviderDiagnostic(
                            provider: "\(provider.name)@\(variant.strategy.rawValue)",
                            outcome: .candidates(list.count),
                            duration: elapsed,
                            matchDecisions: candidateDecisions
                        )
                    )
                    if let (item, decision) = autoAdoption {
                        let document = LyricsDocument(
                            identity: identity,
                            title: item.title,
                            artist: item.artist,
                            album: item.album,
                            duration: item.duration,
                            lines: item.lines,
                            isSynchronized: item.isSynchronized,
                            source: item.source,
                            confidence: item.confidence,
                            providerSourceID: item.providerSourceID,
                            spotifyTrackID: item.spotifyTrackID,
                            isrc: item.isrc,
                            language: item.language
                        )
                        let enriched = Self.finalizeDocument(document, identity: identity)
                        LyricsE2ELog.log("MANAGER AUTO_ADOPT from-candidates provider=\(provider.name) strategy=\(variant.strategy.rawValue) kind=\(variant.queryKind.rawValue) tier=\(decision.tier) score=\(decision.score) evidence=\(decision.explanation.joined(separator: ";")) lines=\(enriched.lines.count)")
                        return SearchOutcome(result: .match(enriched), diagnostics: diagnostics)
                    }

                case .noLyrics:
                    sawNoLyrics = true
                    diagnostics.append(
                        LyricsProviderDiagnostic(
                            provider: "\(provider.name)@\(variant.strategy.rawValue)",
                            outcome: .noLyrics,
                            duration: elapsed
                        )
                    )

                case .noMatch:
                    sawNoMatch = true
                    diagnostics.append(
                        LyricsProviderDiagnostic(
                            provider: "\(provider.name)@\(variant.strategy.rawValue)",
                            outcome: .noMatch,
                            duration: elapsed
                        )
                    )

                case .failed(let failure):
                    if failure == .cancelled {
                        return SearchOutcome(result: .failed(.cancelled), diagnostics: diagnostics)
                    }
                    if firstFailure == nil {
                        firstFailure = failure
                    }
                    diagnostics.append(
                        LyricsProviderDiagnostic(
                            provider: "\(provider.name)@\(variant.strategy.rawValue)",
                            outcome: .failed(failure),
                            duration: elapsed
                        )
                    )
                    // Isolate: continue other providers/variants
                }
            }
        }

        if !acceptedCandidates.isEmpty {
            let sorted = acceptedCandidates.values
                .sorted { $0.displayedConfidence > $1.displayedConfidence }
            return SearchOutcome(result: .candidates(sorted), diagnostics: diagnostics)
        }

        if firstFailure == nil, sawNoLyrics {
            storeNegativeResult(.noLyrics, for: cacheKey)
            return SearchOutcome(result: .noLyrics, diagnostics: diagnostics)
        }
        if firstFailure == nil, sawNoMatch {
            storeNegativeResult(.noMatch, for: cacheKey)
            return SearchOutcome(result: .noMatch, diagnostics: diagnostics)
        }
        if let firstFailure {
            return SearchOutcome(result: .failed(firstFailure), diagnostics: diagnostics)
        }
        return SearchOutcome(result: .noMatch, diagnostics: diagnostics)
    }

    public func clearNegativeCache() {
        negativeCacheLock.lock()
        negativeCache.removeAll()
        negativeCacheLock.unlock()
    }

    private static func mergeAliases(_ generated: [TrackAlias], _ stored: [TrackAlias]) -> [TrackAlias] {
        var result: [TrackAlias] = []
        var seen = Set<String>()
        for alias in generated + stored {
            let key = [alias.field.rawValue, alias.kind.rawValue, TrackTextNormalizer.normalize(alias.value)].joined(separator: "\u{1f}")
            guard seen.insert(key).inserted else { continue }
            result.append(alias)
        }
        return result
    }

    private static func negativeCacheKey(identity: TrackIdentity, queryOverride: String?) -> String {
        let query = TrackTextNormalizer.normalize(queryOverride ?? "")
        return identity.stableKey + "|query:" + query
    }

    private func cachedNegativeResult(for key: String) -> NegativeResult? {
        negativeCacheLock.lock()
        defer { negativeCacheLock.unlock() }
        guard let entry = negativeCache[key] else { return nil }
        if entry.expiresAt <= Date() {
            negativeCache.removeValue(forKey: key)
            return nil
        }
        return entry.result
    }

    private func removeNegativeCache(for key: String) {
        negativeCacheLock.lock()
        negativeCache.removeValue(forKey: key)
        negativeCacheLock.unlock()
    }

    private func storeNegativeResult(_ result: NegativeResult, for key: String) {
        negativeCacheLock.lock()
        negativeCache[key] = NegativeCacheEntry(
            result: result,
            expiresAt: Date().addingTimeInterval(negativeCacheLifetime)
        )
        negativeCacheLock.unlock()
    }

    private static func acceptCandidate(
        _ candidate: LyricsCandidate,
        provider: String,
        variant: LyricsQueryVariant,
        decision: LyricsMatchDecision,
        into storage: inout [String: LyricsCandidate]
    ) {
        let enriched = enrichCandidate(
            candidate,
            providerName: provider,
            variant: variant,
            decision: decision
        )
        guard let existing = storage[enriched.id] else {
            storage[enriched.id] = enriched
            return
        }
        if enriched.displayedConfidence > existing.displayedConfidence {
            storage[enriched.id] = enriched
        }
    }

    /// Enrich layers; preserve originalText; mark unsynced documents clearly.
    private static func finalizeDocument(_ document: LyricsDocument, identity: TrackIdentity) -> LyricsDocument {
        let lines = LyricsLayerEnricher.enrich(lines: document.lines)
        return LyricsDocument(
            identity: identity,
            title: document.title,
            artist: document.artist,
            album: document.album,
            duration: document.duration,
            lines: lines,
            isSynchronized: document.isSynchronized,
            source: document.source,
            confidence: document.confidence,
            providerSourceID: document.providerSourceID,
            spotifyTrackID: document.spotifyTrackID,
            isrc: document.isrc,
            language: document.language
        )
    }

    private static func enrichCandidate(
        _ candidate: LyricsCandidate,
        providerName: String? = nil,
        variant: LyricsQueryVariant? = nil,
        decision: LyricsMatchDecision? = nil
    ) -> LyricsCandidate {
        LyricsCandidate(
            id: candidate.id,
            identity: candidate.identity,
            title: candidate.title,
            artist: candidate.artist,
            album: candidate.album,
            duration: candidate.duration,
            lines: LyricsLayerEnricher.enrich(lines: candidate.lines),
            isSynchronized: candidate.isSynchronized,
            source: candidate.source,
            confidence: candidate.confidence,
            providerSourceID: candidate.providerSourceID,
            spotifyTrackID: candidate.spotifyTrackID,
            isrc: candidate.isrc,
            language: candidate.language,
            providerName: providerName ?? candidate.providerName,
            queryKind: variant?.queryKind.rawValue ?? candidate.queryKind,
            queryTitle: variant?.titleQuery ?? candidate.queryTitle,
            queryArtist: variant?.artistQuery ?? candidate.queryArtist,
            matchScore: decision?.score ?? candidate.matchScore,
            matchExplanation: decision?.explanation ?? candidate.matchExplanation
        )
    }
}

public struct SearchOutcome {
    public let result: LyricsLookupResult
    public let diagnostics: [LyricsProviderDiagnostic]

    public init(result: LyricsLookupResult, diagnostics: [LyricsProviderDiagnostic]) {
        self.result = result
        self.diagnostics = diagnostics
    }
}

public struct LyricsProviderDiagnostic: Equatable {
    public enum Outcome: Equatable {
        case match
        case candidates(Int)
        case noLyrics
        case noMatch
        case failed(LyricsFailure)
    }

    public let provider: String
    public let outcome: Outcome
    public let duration: TimeInterval
    public let matchDecisions: [LyricsMatchDecision]

    public init(
        provider: String,
        outcome: Outcome,
        duration: TimeInterval,
        matchDecisions: [LyricsMatchDecision] = []
    ) {
        self.provider = provider
        self.outcome = outcome
        self.duration = duration
        self.matchDecisions = matchDecisions
    }
}
