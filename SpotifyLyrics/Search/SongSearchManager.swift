import Combine
import Foundation

/// Compatibility facade over `TrackSearchManager` for existing UI bindings.
/// Track search never attaches lyrics bodies; selection resolves lyrics separately.
@MainActor
public final class SongSearchManager: ObservableObject {
    @Published public private(set) var state: SongSearchState = .idle

    public let trackSearchManager: TrackSearchManager
    private var requestTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    public init(providers: [TrackSearchProvider]) {
        self.trackSearchManager = TrackSearchManager(providers: providers)
    }

    /// Legacy constructor accepted `SongSearchProvider`. Bridge adapters keep call sites compiling.
    public convenience init(providers: [SongSearchProvider]) {
        self.init(providers: providers.map { SongSearchProviderBridge(provider: $0) })
    }

    deinit {
        requestTask?.cancel()
    }

    @discardableResult
    public func search(
        query: SongSearchQuery,
        debounceNanoseconds: UInt64 = 0
    ) -> Task<Void, Never>? {
        generation &+= 1
        let requestGeneration = generation
        requestTask?.cancel()

        guard !query.isEmpty else {
            state = .idle
            requestTask = nil
            _ = trackSearchManager.search(query: query, debounceNanoseconds: debounceNanoseconds)
            return nil
        }

        state = .searching(query)
        let trackTask = trackSearchManager.search(query: query, debounceNanoseconds: debounceNanoseconds)
        requestTask = Task { [weak self] in
            await trackTask?.value
            guard let self, self.generation == requestGeneration else { return }
            self.state = self.trackSearchManager.state.songSearchState
        }
        return requestTask
    }

    public func cancel() {
        generation &+= 1
        requestTask?.cancel()
        requestTask = nil
        trackSearchManager.cancel()
        state = .idle
    }
}

/// Adapts legacy `SongSearchProvider` implementations into metadata-only track search.
private struct SongSearchProviderBridge: TrackSearchProvider {
    let provider: SongSearchProvider
    var name: String { provider.name }

    func search(query: TrackSearchQuery) async throws -> [TrackSearchResult] {
        let results = try await provider.search(query: query)
        return results.map { result in
            // Drop any accidental lyrics payload from legacy providers.
            TrackSearchResult(
                id: result.id,
                source: result.source,
                track: result.track,
                confidence: result.confidence,
                artworkURL: result.artworkURL,
                catalogMetadata: result.catalogMetadata
            )
        }
    }
}
