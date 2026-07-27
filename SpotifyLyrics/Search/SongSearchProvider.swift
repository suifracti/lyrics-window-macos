import Foundation

public protocol SongSearchProvider {
    var name: String { get }
    func search(query: SongSearchQuery) async throws -> [SongSearchResult]
}
