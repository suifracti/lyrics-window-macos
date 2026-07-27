import Foundation

public final class CompositeLyricsProvider: LyricsProvider {
    public let name = "Local + LRCLIB"
    private let providers: [LyricsProvider]

    public init(providers: [LyricsProvider]) {
        self.providers = providers
    }

    public func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult {
        var latestFailure: String?
        var sawNoLyrics = false

        for provider in providers {
            let result = await provider.lookup(track: track, identity: identity)
            switch result {
            case .match, .candidates:
                return result
            case .noLyrics:
                sawNoLyrics = true
            case .noMatch:
                continue
            case .failed(let message):
                latestFailure = message
            }
        }

        if let latestFailure { return .failed(latestFailure) }
        return sawNoLyrics ? .noLyrics : .noMatch
    }
}
