import Foundation

/// Lyrics lookup for an already-confirmed `TrackIdentity`.
/// Never performs free-text catalog search and never writes online lyrics to disk.
public final class LyricsSearchManager: LyricsProvider, @unchecked Sendable {
    public let name: String

    private let providers: [LyricsProvider]

    public init(providers: [LyricsProvider], name: String = "Lyrics Search") {
        self.providers = providers
        self.name = name
    }

    public func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult {
        await search(track: track, identity: identity).result
    }

    public struct SearchOutcome {
        public let result: LyricsLookupResult
        public let diagnostics: [LyricsProviderDiagnostic]
    }

    public func search(track: Track, identity: TrackIdentity) async -> SearchOutcome {
        var diagnostics: [LyricsProviderDiagnostic] = []
        var candidates: [LyricsCandidate] = []
        var firstFailure: LyricsFailure?
        var sawNoLyrics = false
        var sawNoMatch = false

        for provider in providers {
            if Task.isCancelled {
                return SearchOutcome(
                    result: .failed(.unknown("歌词请求已取消")),
                    diagnostics: diagnostics
                )
            }

            let started = Date()
            let result = await provider.lookup(track: track, identity: identity)
            let elapsed = Date().timeIntervalSince(started)

            switch result {
            case .match(let document):
                guard document.identity == identity else {
                    diagnostics.append(
                        LyricsProviderDiagnostic(
                            provider: provider.name,
                            outcome: .failed(.unknown("identity mismatch")),
                            duration: elapsed
                        )
                    )
                    continue
                }
                diagnostics.append(
                    LyricsProviderDiagnostic(
                        provider: provider.name,
                        outcome: .match,
                        duration: elapsed
                    )
                )
                return SearchOutcome(result: .match(document), diagnostics: diagnostics)

            case .candidates(let values):
                let valid = values.filter { $0.identity == identity && !$0.lines.isEmpty }
                candidates.append(contentsOf: valid)
                diagnostics.append(
                    LyricsProviderDiagnostic(
                        provider: provider.name,
                        outcome: .candidates(valid.count),
                        duration: elapsed
                    )
                )

            case .noLyrics:
                sawNoLyrics = true
                diagnostics.append(
                    LyricsProviderDiagnostic(
                        provider: provider.name,
                        outcome: .noLyrics,
                        duration: elapsed
                    )
                )

            case .noMatch:
                sawNoMatch = true
                diagnostics.append(
                    LyricsProviderDiagnostic(
                        provider: provider.name,
                        outcome: .noMatch,
                        duration: elapsed
                    )
                )

            case .failed(let failure):
                if firstFailure == nil {
                    firstFailure = failure
                }
                diagnostics.append(
                    LyricsProviderDiagnostic(
                        provider: provider.name,
                        outcome: .failed(failure),
                        duration: elapsed
                    )
                )
            }
        }

        if !candidates.isEmpty {
            let sorted = candidates.sorted { $0.confidence > $1.confidence }
            if let best = sorted.first,
               LyricsMatcher.isHighConfidence(best.confidence),
               sorted.dropFirst().first.map({ best.confidence - $0.confidence >= 0.05 }) ?? true {
                return SearchOutcome(
                    result: .match(
                        LyricsDocument(
                            identity: identity,
                            title: best.title,
                            artist: best.artist,
                            album: best.album,
                            duration: best.duration,
                            lines: best.lines,
                            isSynchronized: best.isSynchronized,
                            source: best.source,
                            confidence: best.confidence
                        )
                    ),
                    diagnostics: diagnostics
                )
            }
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

    public init(provider: String, outcome: Outcome, duration: TimeInterval) {
        self.provider = provider
        self.outcome = outcome
        self.duration = duration
    }
}
