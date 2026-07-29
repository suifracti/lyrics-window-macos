import Foundation

/// Spotify Web API catalog provider. It is intentionally separate from
/// CurrentTrackResolver and returns metadata only; lyric lookup remains in the
/// existing LyricsSearchManager chain.
@MainActor
public final class SpotifySearchProvider: TrackSearchProvider {
    public let name = "Spotify Web Catalog"

    private let authorization: SpotifyAuthorizationManager
    private let service: SpotifyCatalogService
    private let firstPageSize: Int

    public init(
        authorization: SpotifyAuthorizationManager,
        service: SpotifyCatalogService = SpotifyCatalogService(),
        firstPageSize: Int = 10
    ) {
        self.authorization = authorization
        self.service = service
        self.firstPageSize = min(10, max(1, firstPageSize))
    }

    public func search(query: TrackSearchQuery) async throws -> [TrackSearchResult] {
        guard !query.isEmpty else { return [] }
        guard authorization.isConfigured else { throw SongSearchError.notConfigured }

        let token: String
        do {
            token = try await authorization.accessToken()
        } catch let error as SpotifyAuthorizationError {
            throw Self.map(error)
        }

        do {
            if let id = query.spotifyTrackID {
                let dto = try await service.fetchTrack(id: id, accessToken: token)
                return [SpotifyTrackMapper.result(from: dto, confidence: 1)]
            }

            let items = try await searchItems(query: query, accessToken: token)
            return results(from: items, query: query)
        } catch let error as SpotifyCatalogError where error == .unauthorized {
            // One and only one refresh/retry protects against a token revoked
            // between accessToken() and the API request. It cannot loop.
            do {
                let refreshed = try await authorization.refreshNow()
                if let id = query.spotifyTrackID {
                    let dto = try await service.fetchTrack(id: id, accessToken: refreshed.accessToken)
                    return [SpotifyTrackMapper.result(from: dto, confidence: 1)]
                }
                let items = try await searchItems(query: query, accessToken: refreshed.accessToken)
                return results(from: items, query: query)
            } catch let retryError as SpotifyAuthorizationError {
                throw Self.map(retryError)
            } catch let retryError as SpotifyCatalogError {
                throw Self.map(retryError)
            }
        } catch let error as SpotifyCatalogError {
            throw Self.map(error)
        }
    }

    private func score(dto: SpotifyTrackDTO, query: TrackSearchQuery) -> Double {
        let track = SpotifyTrackMapper.track(from: dto)
        let score = SongSearchScoring.score(track: track, query: query)
        // Popularity is deliberately not part of identity matching. It only
        // provides a small tie-breaker for otherwise similar catalog hits.
        let popularityBoost = Double(min(max(dto.popularity ?? 0, 0), 100)) / 2_000
        return min(0.99, max(0.35, score + popularityBoost))
    }

    private func searchItems(
        query: TrackSearchQuery,
        accessToken: String
    ) async throws -> [SpotifyTrackDTO] {
        var items = try await service.searchTracks(
            query: query.spotifyQueryText,
            accessToken: accessToken,
            limit: firstPageSize
        ).tracks.items

        // A plain "title artist" input is common in the UI. Spotify's search
        // ranking can spend the whole first page on remixes, live versions,
        // or karaoke entries when both words are sent as one free-text query.
        // Add a title-only recall query, then let the normal metadata scoring
        // rank the exact artist/title match. This expands recall only; it does
        // not prove identity or bypass version matching.
        if let titleQuery = inferredTitleQuery(from: query) {
            let fallbackItems = try await service.searchTracks(
                query: titleQuery,
                accessToken: accessToken,
                limit: firstPageSize
            ).tracks.items
            items.append(contentsOf: fallbackItems)
        }

        var unique: [String: SpotifyTrackDTO] = [:]
        for item in items {
            unique[item.id] = item
        }
        return Array(unique.values)
    }

    private func results(
        from items: [SpotifyTrackDTO],
        query: TrackSearchQuery
    ) -> [TrackSearchResult] {
        let scoringQuery = inferredTitleArtistQuery(from: query) ?? query
        return items
            .map { SpotifyTrackMapper.result(from: $0, confidence: score(dto: $0, query: scoringQuery)) }
            .sorted {
                if $0.confidence == $1.confidence { return $0.track.title < $1.track.title }
                return $0.confidence > $1.confidence
            }
    }

    private func inferredTitleQuery(from query: TrackSearchQuery) -> String? {
        guard inferredTitleArtistQuery(from: query) != nil else { return nil }
        let parts = query.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard parts.count >= 2 else { return nil }
        return parts.dropLast().joined(separator: " ")
    }

    private func inferredTitleArtistQuery(from query: TrackSearchQuery) -> TrackSearchQuery? {
        guard query.title == nil, query.artist == nil, query.album == nil,
              query.spotifyTrackID == nil else { return nil }
        let parts = query.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard parts.count >= 2 else { return nil }
        let title = parts.dropLast().joined(separator: " ")
        let artist = String(parts[parts.index(before: parts.endIndex)])
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        return SongSearchQuery(text: query.text, title: title, artist: artist)
    }

    private static func map(_ error: SpotifyAuthorizationError) -> SongSearchError {
        switch error {
        case .notConfigured: return .notConfigured
        case .notAuthorized: return .unauthorized
        case .tokenExchange(let error): return map(error)
        case .stateMismatch, .invalidCallback, .denied, .tokenStore, .randomGenerationFailed:
            return .unauthorized
        }
    }

    private static func map(_ error: SpotifyCatalogError) -> SongSearchError {
        switch error {
        case .unauthorized: return .unauthorized
        case .forbidden: return .forbidden
        case .badRequest: return .badRequest
        case .notFound: return .notFound
        case .rateLimited(let retryAfter): return .rateLimited(retryAfter)
        case .networkUnavailable: return .networkUnavailable
        case .timedOut: return .timedOut
        case .serverError(let status): return .serverError(status)
        case .parseFailure: return .parseFailure
        case .cancelled: return .cancelled
        case .invalidURL: return .unknown("Spotify 请求 URL 无效")
        case .unknown(let message): return .unknown(message)
        }
    }
}
