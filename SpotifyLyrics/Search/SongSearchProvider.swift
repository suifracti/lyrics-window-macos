import Foundation

/// Legacy free-text search provider protocol.
/// New code should implement `TrackSearchProvider` (metadata only).
public protocol SongSearchProvider {
    var name: String { get }
    func search(query: SongSearchQuery) async throws -> [SongSearchResult]
}
