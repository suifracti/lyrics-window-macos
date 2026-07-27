import Foundation

/// Metadata-only track search hit. Must never carry lyrics body text.
public struct TrackSearchResult: Identifiable, Equatable {
    public let id: String
    public let source: SongSearchSource
    public let track: Track
    public let confidence: Double
    public let artworkURL: URL?

    public init(
        id: String,
        source: SongSearchSource,
        track: Track,
        confidence: Double,
        artworkURL: URL? = nil
    ) {
        self.id = id
        self.source = source
        self.track = track
        self.confidence = max(0, min(confidence, 1))
        self.artworkURL = artworkURL
    }

    public var metadataKey: String {
        TrackIdentity.metadataFingerprint(
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration
        )
    }

    /// Search-result de-duplication intentionally ignores album and duration:
    /// public lyric indexes often publish the same recording under slightly
    /// different release metadata or duration rounding.
    public var searchMergeKey: String {
        if let spotifyID = track.spotifyId, !spotifyID.isEmpty {
            return "spotify-id:\(spotifyID)"
        }
        if let uri = track.spotifyURL?.absoluteString, !uri.isEmpty {
            return "spotify-uri:\(uri)"
        }
        if let isrc = track.isrc, !isrc.isEmpty {
            return "isrc:\(isrc.lowercased())"
        }
        return [
            SongSearchQuery.normalizeSearchText(track.title),
            SongSearchQuery.normalizeSearchText(track.artist)
        ].joined(separator: "|")
    }

    /// Compatibility bridge used by existing UI/session code.
    public func asSongSearchResult(lyrics: LyricsDocument? = nil) -> SongSearchResult {
        SongSearchResult(
            id: id,
            source: source,
            track: track,
            confidence: confidence,
            lyrics: lyrics,
            artworkURL: artworkURL
        )
    }
}

public enum TrackSearchState: Equatable {
    case idle
    case searching(SongSearchQuery)
    case results(SongSearchQuery, [TrackSearchResult])
    case noResults(SongSearchQuery)
    case failed(SongSearchQuery, String)

    public var query: SongSearchQuery? {
        switch self {
        case .idle: return nil
        case .searching(let query), .results(let query, _), .noResults(let query), .failed(let query, _):
            return query
        }
    }

    public var songSearchState: SongSearchState {
        switch self {
        case .idle:
            return .idle
        case .searching(let query):
            return .searching(query)
        case .results(let query, let results):
            return .results(query, results.map { $0.asSongSearchResult() })
        case .noResults(let query):
            return .noResults(query)
        case .failed(let query, let message):
            return .failed(query, message)
        }
    }
}

public typealias TrackSearchQuery = SongSearchQuery
public typealias TrackSearchError = SongSearchError
