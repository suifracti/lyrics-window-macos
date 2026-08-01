import Foundation

public enum SpotifyTrackMapper {
    static func metadata(from dto: SpotifyTrackDTO) -> TrackSearchMetadata {
        let artists = dto.artists.map {
            TrackArtistMetadata(id: $0.id, name: $0.name, uri: $0.uri)
        }
        let display = artists.map(\.name).joined(separator: ", ")
        return TrackSearchMetadata(
            spotifyID: dto.id,
            spotifyURI: dto.uri,
            title: dto.name,
            artists: artists,
            artistDisplay: display,
            album: dto.album.name,
            albumID: dto.album.id,
            albumURI: dto.album.uri,
            duration: TimeInterval(dto.durationMS) / 1_000,
            artworkURL: artworkURL(from: dto.album.images),
            isrc: dto.externalIDs?.isrc,
            explicit: dto.explicit,
            releaseDate: dto.album.releaseDate,
            popularity: dto.popularity
        )
    }

    static func track(from dto: SpotifyTrackDTO) -> Track {
        let metadata = metadata(from: dto)
        return Track(
            id: dto.id,
            title: metadata.title,
            artist: metadata.artistDisplay,
            album: metadata.album,
            duration: metadata.duration,
            artworkName: "music.note",
            isrc: metadata.isrc,
            spotifyId: metadata.spotifyID,
            artworkURL: metadata.artworkURL,
            spotifyURL: URL(string: metadata.spotifyURI ?? "spotify:track:\(dto.id)"),
            artistLinks: metadata.artists.map {
                TrackArtistLink(name: $0.name, url: spotifyURL(uri: $0.uri, id: $0.id, kind: "artist"))
            },
            albumURL: spotifyURL(uri: metadata.albumURI, id: metadata.albumID, kind: "album")
        )
    }

    static func result(from dto: SpotifyTrackDTO, confidence: Double = 0.9) -> TrackSearchResult {
        let metadata = metadata(from: dto)
        return TrackSearchResult(
            id: dto.id,
            source: .spotifyCatalog,
            track: track(from: dto),
            confidence: confidence,
            artworkURL: metadata.artworkURL,
            catalogMetadata: metadata
        )
    }

    private static func artworkURL(from images: [SpotifyImageDTO]) -> URL? {
        images
            .sorted { ($0.width ?? 0) > ($1.width ?? 0) }
            .compactMap { URL(string: $0.url) }
            .first
    }

    private static func spotifyURL(uri: String?, id: String?, kind: String) -> URL? {
        if let uri, !uri.isEmpty, let url = URL(string: uri) {
            return url
        }
        guard let id, !id.isEmpty else { return nil }
        return URL(string: "spotify:\(kind):\(id)")
    }
}

public extension TrackMetadata {
    /// Builds persistence/search aliases from Spotify's structured artist
    /// metadata without mutating the canonical display string.
    static func bootstrap(from track: Track, catalogMetadata: TrackSearchMetadata?) -> TrackMetadata {
        var metadata = TrackMetadata.bootstrap(from: track)
        guard let catalogMetadata else { return metadata }

        var aliases = metadata.aliases
        for (index, artist) in catalogMetadata.artists.enumerated() {
            guard !artist.name.isEmpty,
                  TrackIdentity.normalizedComponent(artist.name) != TrackIdentity.normalizedComponent(track.artist) else {
                continue
            }
            aliases.append(
                TrackAlias(
                    id: "spotify-artist-\(index)-\(TrackIdentity.normalizedComponent(artist.name))",
                    field: .artist,
                    kind: .alternativeTitle,
                    value: artist.name,
                    language: ScriptDetector.guessLanguage(artist.name),
                    script: ScriptDetector.detect(artist.name),
                    source: .spotifyMetadata,
                    confidence: 1,
                    isOfficial: true
                )
            )
        }
        metadata.aliases = aliases
        return metadata
    }
}
