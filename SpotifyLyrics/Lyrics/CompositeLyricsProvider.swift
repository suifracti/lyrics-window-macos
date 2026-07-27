import Foundation

/// Compatibility wrapper over `LyricsSearchManager`.
public final class CompositeLyricsProvider: LyricsProvider, @unchecked Sendable {
    public let name: String
    private let manager: LyricsSearchManager

    public init(providers: [LyricsProvider], name: String? = nil) {
        self.manager = LyricsSearchManager(providers: providers, name: name ?? "Local + LRCLIB")
        self.name = self.manager.name
    }

    public func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult {
        await manager.lookup(track: track, identity: identity)
    }

    public var searchManager: LyricsSearchManager { manager }
}
