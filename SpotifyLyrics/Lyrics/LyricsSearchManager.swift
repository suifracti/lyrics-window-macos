import Foundation

/// Multi-variant lyrics search: Local → other providers, one provider at a time per variant.
/// Applies SafeMatcher and does not auto-adopt conflicting versions.
public final class LyricsSearchManager: @unchecked Sendable {
    public let name: String
    private let providersLock = NSLock()
    private var providers: [LyricsProvider]

    public init(providers: [LyricsProvider], name: String = "Lyrics Search") {
        self.providers = providers
        self.name = name
    }

    /// Replaces the runtime provider order without exposing provider objects
    /// to SwiftUI. The active session cancels its in-flight request before
    /// calling this method, so a disabled provider cannot receive a new probe.
    public func updateProviders(_ providers: [LyricsProvider]) {
        providersLock.lock()
        self.providers = providers
        providersLock.unlock()
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

    public func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult {
        let outcome = await search(track: track, identity: identity)
        return outcome.result
    }

    public func search(track: Track, identity: TrackIdentity) async -> SearchOutcome {
        if Task.isCancelled {
            return SearchOutcome(result: .failed(.cancelled), diagnostics: [])
        }

        let metadata = TrackMetadata.bootstrap(from: track)
        // Keep identity stable with caller-supplied identity (playback).
        let meta = TrackMetadata(
            identity: identity,
            track: track,
            aliases: metadata.aliases,
            versionTags: metadata.versionTags
        )
        let variants = LyricsQueryPlanner.plan(for: meta)
        let configuredProviders = providerSnapshot()
        LyricsE2ELog.log("MANAGER start title=\(track.title) artist=\(track.artist) variants=\(variants.count) providers=\(configuredProviders.map { $0.name })")
        var diagnostics: [LyricsProviderDiagnostic] = []
        var acceptedCandidates: [LyricsCandidate] = []
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
                        acceptedCandidates.append(candidate)
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
                            acceptedCandidates.append(item)
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
            var seen = Set<String>()
            let sorted = acceptedCandidates
                .filter { seen.insert($0.id).inserted }
                .sorted { $0.confidence > $1.confidence }
                .map { Self.enrichCandidate($0) }
            return SearchOutcome(result: .candidates(sorted), diagnostics: diagnostics)
        }

        if sawNoLyrics {
            return SearchOutcome(result: .noLyrics, diagnostics: diagnostics)
        }
        if sawNoMatch {
            return SearchOutcome(result: .noMatch, diagnostics: diagnostics)
        }
        if let firstFailure {
            return SearchOutcome(result: .failed(firstFailure), diagnostics: diagnostics)
        }
        return SearchOutcome(result: .noMatch, diagnostics: diagnostics)
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

    private static func enrichCandidate(_ candidate: LyricsCandidate) -> LyricsCandidate {
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
            language: candidate.language
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
