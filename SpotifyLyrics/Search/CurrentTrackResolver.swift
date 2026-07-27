import Foundation

/// Resolves the currently playing Spotify Desktop track for search matching.
/// This is not a free-text catalog search provider.
public final class CurrentTrackResolver: TrackSearchProvider {
    public let name = "Spotify Current Track"

    private let playbackProvider: PlaybackProvider

    public init(playbackProvider: PlaybackProvider) {
        self.playbackProvider = playbackProvider
    }

    public func search(query: TrackSearchQuery) async throws -> [TrackSearchResult] {
        guard !query.isEmpty else { return [] }
        let snapshot = await playbackProvider.refresh()
        guard snapshot.status.isReady, let providerTrack = snapshot.track else { return [] }

        let track = Track(
            id: providerTrack.id ?? UUID().uuidString,
            title: providerTrack.title,
            artist: providerTrack.artist,
            album: providerTrack.album,
            duration: providerTrack.duration,
            artworkName: "music.note",
            isrc: providerTrack.isrc,
            spotifyId: providerTrack.id,
            artworkURL: providerTrack.artworkURL,
            spotifyURL: providerTrack.spotifyURL
        )

        let score = SongSearchScoring.score(track: track, query: query)
        guard score >= 0.35 else { return [] }

        return [
            TrackSearchResult(
                id: "spotify-current:\(TrackIdentity(track: track).stableKey)",
                source: .spotifyCurrentTrack,
                track: track,
                confidence: max(score, 0.85),
                artworkURL: providerTrack.artworkURL
            )
        ]
    }
}

/// Compatibility name retained for older call sites and contracts.
public typealias SpotifyCurrentTrackProvider = CurrentTrackResolver
