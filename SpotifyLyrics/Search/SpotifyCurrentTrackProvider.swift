import Foundation

@MainActor
public final class SpotifyCurrentTrackProvider: SongSearchProvider {
    public let name = "Spotify Current Track"

    private let playbackProvider: PlaybackProvider

    public init(playbackProvider: PlaybackProvider) {
        self.playbackProvider = playbackProvider
    }

    public func search(query: SongSearchQuery) async throws -> [SongSearchResult] {
        let snapshot = await playbackProvider.refresh()
        guard snapshot.status.isReady, let providerTrack = snapshot.track else { return [] }

        let track = Track(
            id: providerTrack.id ?? "spotify-current-track",
            title: providerTrack.title,
            artist: providerTrack.artist,
            album: providerTrack.album,
            duration: providerTrack.duration,
            isrc: providerTrack.isrc,
            spotifyId: providerTrack.id,
            artworkURL: providerTrack.artworkURL,
            spotifyURL: providerTrack.spotifyURL
        )
        let score = SongSearchScoring.score(track: track, query: query)
        guard query.isEmpty || score >= 0.20 else { return [] }

        return [
            SongSearchResult(
                id: "spotify-current:\(TrackIdentity(track: track).stableKey)",
                source: .spotifyCurrentTrack,
                track: track,
                confidence: query.isEmpty ? 1 : score
            )
        ]
    }
}
