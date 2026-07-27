import Foundation

public protocol TrackSearchProvider {
    var name: String { get }
    func search(query: TrackSearchQuery) async throws -> [TrackSearchResult]
}
