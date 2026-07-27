import Foundation

/// LRCLIB is intentionally isolated as a lyrics-only provider.
/// Free-text track search must not call LRCLIB or attach online lyrics bodies.
@available(*, deprecated, message: "Use LRCLIBLyricsProvider via LyricsSearchManager instead of track search.")
public final class LRCLIBProvider: TrackSearchProvider {
    public let name = "LRCLIB (disabled in track search)"

    public init() {}

    public func search(query: TrackSearchQuery) async throws -> [TrackSearchResult] {
        // Hard isolation: never participate in track/catalog search.
        []
    }
}
