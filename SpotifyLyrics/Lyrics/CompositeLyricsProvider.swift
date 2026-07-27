import Foundation

/// Compatibility wrapper over `LyricsSearchManager`.
public final class CompositeLyricsProvider: LyricsProvider, @unchecked Sendable {
    public let name: String
    public let underlyingProviders: [LyricsProvider]
    private let manager: LyricsSearchManager

    public init(providers: [LyricsProvider], name: String? = nil) {
        self.underlyingProviders = providers
        self.manager = LyricsSearchManager(providers: providers, name: name ?? "LyricsSearchManager")
        self.name = self.manager.name
    }

    public func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult {
        await manager.lookup(track: track, identity: identity)
    }

    public var searchManager: LyricsSearchManager { manager }
}
