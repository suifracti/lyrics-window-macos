import Foundation

/// One-button lyrics auto-complete pipeline (product default entry).
///
/// Current Track → aliases → Local → LRCLIB → (future experimental providers)
/// → safe match → original → kana → romaji → timing check → alignment queue → local save hook
///
/// Manual paste/import is an advanced option on exhausted state only.
public struct LyricsAutoCompleteRequest: Equatable, Sendable {
    public let track: Track
    public let metadata: TrackMetadata
    public let generation: UInt64

    public init(track: Track, metadata: TrackMetadata? = nil, generation: UInt64) {
        self.track = track
        self.metadata = metadata ?? TrackMetadata.bootstrap(from: track)
        self.generation = generation
    }
}

public enum LyricsAutoCompletePhase: String, Codable, Sendable, Equatable {
    case planned
    case providerQuery
    case matched
    case layerEnrichment
    case alignmentQueued
    case savedLocal
    case candidates
    case exhausted
    case failed
}

public struct LyricsAutoCompleteResult: Equatable, Sendable {
    public let generation: UInt64
    public let identity: TrackIdentity
    public let phase: LyricsAutoCompletePhase
    public let document: LyricsDocument?
    public let candidates: [LyricsCandidate]
    public let recovery: LyricsRecoveryPlan?
    public let failure: LyricsFailure?
    public let queryVariants: [LyricsQueryVariant]

    public init(
        generation: UInt64,
        identity: TrackIdentity,
        phase: LyricsAutoCompletePhase,
        document: LyricsDocument? = nil,
        candidates: [LyricsCandidate] = [],
        recovery: LyricsRecoveryPlan? = nil,
        failure: LyricsFailure? = nil,
        queryVariants: [LyricsQueryVariant] = []
    ) {
        self.generation = generation
        self.identity = identity
        self.phase = phase
        self.document = document
        self.candidates = candidates
        self.recovery = recovery
        self.failure = failure
        self.queryVariants = queryVariants
    }
}

public protocol LyricsBodyProvider: Sendable {
    var id: String { get }
    func search(
        variant: LyricsQueryVariant,
        identity: TrackIdentity,
        metadata: TrackMetadata
    ) async -> LyricsLookupResult
}

/// Bridges existing `LyricsProvider` lookup(track:) into multi-variant orchestration.
public struct LegacyLyricsBodyProvider: LyricsBodyProvider {
    public let id: String
    private let provider: any LyricsProvider

    public init(id: String? = nil, provider: any LyricsProvider) {
        self.id = id ?? provider.name
        self.provider = provider
    }

    public func search(
        variant: LyricsQueryVariant,
        identity: TrackIdentity,
        metadata: TrackMetadata
    ) async -> LyricsLookupResult {
        let probe = Track(
            id: metadata.track.id,
            title: variant.titleQuery,
            artist: variant.artistQuery ?? metadata.track.artist,
            album: metadata.track.album,
            duration: metadata.track.duration,
            artworkName: metadata.track.artworkName,
            isrc: metadata.track.isrc,
            spotifyId: metadata.track.spotifyId,
            artworkURL: metadata.track.artworkURL,
            spotifyURL: metadata.track.spotifyURL
        )
        return await provider.lookup(track: probe, identity: identity)
    }
}

public actor LyricsRecoveryOrchestrator {
    private let providers: [any LyricsBodyProvider]
    private var currentGeneration: UInt64 = 0

    public init(providers: [any LyricsBodyProvider]) {
        self.providers = providers
    }

    public func cancelInFlight() {
        currentGeneration &+= 1
    }

    @discardableResult
    public func autoComplete(_ request: LyricsAutoCompleteRequest) async -> LyricsAutoCompleteResult {
        let generation = request.generation
        currentGeneration = generation
        let identity = request.metadata.identity
        let metadata = request.metadata
        let variants = LyricsQueryPlanner.plan(for: metadata)

        guard !providers.isEmpty else {
            let recovery = LyricsRecoveryPlanner.plan(metadata: metadata, exhaustedVariants: variants)
            return LyricsAutoCompleteResult(
                generation: generation,
                identity: identity,
                phase: .exhausted,
                recovery: recovery,
                queryVariants: variants
            )
        }

        var allCandidates: [LyricsCandidate] = []
        var adopted: LyricsDocument?
        var sawFailure = false
        var lastFailure: LyricsFailure?

        for variant in variants {
            if generation != currentGeneration {
                return LyricsAutoCompleteResult(
                    generation: generation,
                    identity: identity,
                    phase: .failed,
                    failure: .cancelled,
                    queryVariants: variants
                )
            }

            for provider in providers {
                if generation != currentGeneration {
                    return LyricsAutoCompleteResult(
                        generation: generation,
                        identity: identity,
                        phase: .failed,
                        failure: .cancelled,
                        queryVariants: variants
                    )
                }

                let result = await provider.search(variant: variant, identity: identity, metadata: metadata)
                switch result {
                case .match(let document):
                    let asCandidate = LyricsCandidate(
                        id: "\(provider.id)-\(variant.id)-match",
                        identity: identity,
                        title: document.title ?? variant.titleQuery,
                        artist: document.artist ?? variant.artistQuery ?? metadata.track.artist,
                        album: document.album ?? metadata.track.album,
                        duration: document.duration ?? metadata.track.duration,
                        lines: document.lines,
                        isSynchronized: document.isSynchronized,
                        source: document.source,
                        confidence: document.confidence
                    )
                    let alias = variant.aliasIDs.first.flatMap { id in metadata.aliases.first { $0.id == id } }
                    let decision = LyricsSafeMatcher.decide(
                        candidate: asCandidate,
                        metadata: metadata,
                        aliasUsed: alias
                    )
                    if decision.tier == .autoHigh || decision.tier == .autoMedium {
                        adopted = document
                        break
                    } else if decision.tier == .candidates {
                        allCandidates.append(asCandidate)
                    }
                case .candidates(let list):
                    for item in list {
                        let alias = variant.aliasIDs.first.flatMap { id in metadata.aliases.first { $0.id == id } }
                        let decision = LyricsSafeMatcher.decide(
                            candidate: item,
                            metadata: metadata,
                            aliasUsed: alias
                        )
                        if decision.tier == .autoHigh || decision.tier == .autoMedium {
                            adopted = LyricsDocument(
                                identity: identity,
                                title: item.title,
                                artist: item.artist,
                                album: item.album,
                                duration: item.duration,
                                lines: item.lines,
                                isSynchronized: item.isSynchronized,
                                source: item.source,
                                confidence: item.confidence
                            )
                            break
                        } else if decision.tier == .candidates {
                            allCandidates.append(item)
                        }
                    }
                case .noLyrics, .noMatch:
                    continue
                case .failed(let failure):
                    sawFailure = true
                    lastFailure = failure
                    // isolate: continue other providers/variants
                    continue
                }
                if adopted != nil { break }
            }
            if adopted != nil { break }
        }

        if generation != currentGeneration {
            return LyricsAutoCompleteResult(
                generation: generation,
                identity: identity,
                phase: .failed,
                failure: .cancelled,
                queryVariants: variants
            )
        }

        if var document = adopted {
            let enriched = LyricsLayerEnricher.enrich(lines: document.lines)
            document = LyricsDocument(
                identity: document.identity,
                title: document.title,
                artist: document.artist,
                album: document.album,
                duration: document.duration,
                lines: enriched,
                isSynchronized: document.isSynchronized,
                source: document.source,
                confidence: document.confidence
            )
            let phase: LyricsAutoCompletePhase = document.isSynchronized ? .layerEnrichment : .alignmentQueued
            return LyricsAutoCompleteResult(
                generation: generation,
                identity: identity,
                phase: phase,
                document: document,
                queryVariants: variants
            )
        }

        if !allCandidates.isEmpty {
            // unique by id
            var seen = Set<String>()
            let unique = allCandidates.filter { seen.insert($0.id).inserted }
            return LyricsAutoCompleteResult(
                generation: generation,
                identity: identity,
                phase: .candidates,
                candidates: unique,
                queryVariants: variants
            )
        }

        let recovery = LyricsRecoveryPlanner.plan(metadata: metadata, exhaustedVariants: variants)
        if sawFailure, allCandidates.isEmpty {
            // still exhausted for lyrics body; surface recovery, keep last failure for diagnostics
            return LyricsAutoCompleteResult(
                generation: generation,
                identity: identity,
                phase: .exhausted,
                recovery: recovery,
                failure: lastFailure,
                queryVariants: variants
            )
        }

        return LyricsAutoCompleteResult(
            generation: generation,
            identity: identity,
            phase: .exhausted,
            recovery: recovery,
            queryVariants: variants
        )
    }
}
