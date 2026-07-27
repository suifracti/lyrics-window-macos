import Foundation

/// Local track metadata search backed by the shared read-only lyrics index.
public final class LocalSearchProvider: TrackSearchProvider {
    public let name = "Local Search"

    private let index: LocalLyricsIndex

    public init(searchDirectories: [URL]? = nil, index: LocalLyricsIndex? = nil) {
        if let index {
            self.index = index
        } else if let searchDirectories {
            self.index = LocalLyricsIndex(searchDirectories: searchDirectories)
        } else {
            self.index = .shared
        }
    }

    public func search(query: TrackSearchQuery) async throws -> [TrackSearchResult] {
        index.searchTracks(matching: query)
    }
}

/// Explicit alias for research naming.
public typealias LocalTrackSearchProvider = LocalSearchProvider
