import Combine
import Foundation

@MainActor
public final class SongSearchManager: ObservableObject {
    @Published public private(set) var state: SongSearchState = .idle

    private let providers: [SongSearchProvider]
    private var requestTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    public init(providers: [SongSearchProvider]) {
        self.providers = providers
    }

    deinit {
        requestTask?.cancel()
    }

    public func search(query: SongSearchQuery) -> Task<Void, Never>? {
        generation &+= 1
        let requestGeneration = generation
        requestTask?.cancel()

        guard !query.isEmpty else {
            state = .idle
            requestTask = nil
            return nil
        }

        state = .searching(query)
        let providers = self.providers
        requestTask = Task { [weak self] in
            var results: [SongSearchResult] = []
            var errors: [String] = []

            for provider in providers {
                guard !Task.isCancelled else { return }
                do {
                    results.append(contentsOf: try await provider.search(query: query))
                } catch let error as SongSearchError {
                    errors.append(error.errorDescription ?? provider.name)
                } catch {
                    errors.append(error.localizedDescription)
                }
            }

            guard !Task.isCancelled else { return }
            let merged = Self.merge(results)
            guard let self,
                  self.generation == requestGeneration else { return }

            if !merged.isEmpty {
                self.state = .results(query, merged)
            } else if !errors.isEmpty {
                self.state = .failed(query, errors.joined(separator: "；"))
            } else {
                self.state = .noResults(query)
            }
        }
        return requestTask
    }

    public func cancel() {
        generation &+= 1
        requestTask?.cancel()
        requestTask = nil
        state = .idle
    }

    private static func merge(_ results: [SongSearchResult]) -> [SongSearchResult] {
        var merged: [String: SongSearchResult] = [:]
        for result in results {
            let key = result.searchMergeKey
            guard let existing = merged[key] else {
                merged[key] = result
                continue
            }

            if existing.lyrics == nil, result.lyrics != nil {
                merged[key] = result
            } else if result.confidence > existing.confidence {
                merged[key] = result
            }
        }
        return merged.values.sorted {
            if $0.confidence == $1.confidence { return $0.track.title < $1.track.title }
            return $0.confidence > $1.confidence
        }
    }
}
