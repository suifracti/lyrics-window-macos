import Foundation

private final class StubSearchSession: LRCLIBSearchSession {
    private(set) var requests: [URLRequest] = []
    let dataToReturn: Data

    init(dataToReturn: Data) {
        self.dataToReturn = dataToReturn
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return (
            dataToReturn,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
        )
    }
}

@MainActor
private final class StubPlaybackProvider: PlaybackProvider {
    let displayName = "stub playback"
    var snapshot: PlaybackSnapshot

    init(snapshot: PlaybackSnapshot) {
        self.snapshot = snapshot
    }

    func refresh() async -> PlaybackSnapshot { snapshot }
    func play() async throws {}
    func pause() async throws {}
    func previous() async throws {}
    func next() async throws {}
    func seek(to position: TimeInterval) async throws {}
}

private struct DelayedSearchProvider: SongSearchProvider {
    let name: String
    let delay: UInt64
    let acceptedQuery: String
    let result: SongSearchResult

    func search(query: SongSearchQuery) async throws -> [SongSearchResult] {
        try await Task.sleep(nanoseconds: delay)
        return query.normalizedText == acceptedQuery ? [result] : []
    }
}

private struct FixedSearchProvider: SongSearchProvider {
    let name: String
    let results: [SongSearchResult]

    func search(query: SongSearchQuery) async throws -> [SongSearchResult] { results }
}

@main
@MainActor
struct SongSearchContract {
    static func main() async {
        let track = Track(
            id: "spotify-track-search",
            title: "Search Song",
            artist: "Search Artist",
            album: "Search Album",
            duration: 201,
            spotifyId: "spotify-track-search"
        )
        let query = SongSearchQuery(text: "Search Song  Search Artist")
        precondition(query.normalizedText == "search song search artist")
        precondition(!query.isEmpty)

        let localRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spotifylyrics-song-search-(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: localRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: localRoot) }
        let localFile = localRoot.appendingPathComponent("Search Song.lrc")
        try! "[ti:Search Song]\n[ar:Search Artist]\n[al:Search Album]\n[00:01.00]Local line\n"
            .write(to: localFile, atomically: true, encoding: .utf8)

        let local = LocalSearchProvider(searchDirectories: [localRoot])
        let localResults = try! await local.search(query: SongSearchQuery(text: "Search Artist"))
        precondition(localResults.count == 1)
        precondition(localResults[0].source == .local)
        precondition(localResults[0].lyrics?.lines.first?.originalText == "Local line")

        let payload = """
        [{
          "id": 7,
          "trackName": "Search Song",
          "artistName": "Search Artist",
          "albumName": "Search Album",
          "duration": 201,
          "plainLyrics": "Plain line",
          "syncedLyrics": "[00:02.00]Synced line"
        }]
        """.data(using: .utf8)!
        let session = StubSearchSession(dataToReturn: payload)
        let lrclib = LRCLIBProvider(
            session: session,
            baseURL: URL(string: "https://example.test/api")!
        )
        let lrclibResults = try! await lrclib.search(query: SongSearchQuery(text: "Search Song"))
        precondition(lrclibResults.count == 1)
        precondition(lrclibResults[0].source == .lrclib)
        precondition(lrclibResults[0].lyrics?.isSynchronized == true)
        precondition(session.requests.count == 1)

        let playback = StubPlaybackProvider(
            snapshot: PlaybackSnapshot(
                status: .ready,
                track: ProviderTrack(
                    id: "spotify-track-search",
                    title: "Search Song",
                    artist: "Search Artist",
                    album: "Search Album",
                    duration: 201
                ),
                position: 42,
                isPlaying: false
            )
        )
        let current = SpotifyCurrentTrackProvider(playbackProvider: playback)
        let currentResults = try! await current.search(query: SongSearchQuery(text: "Search Artist"))
        precondition(currentResults.count == 1)
        precondition(currentResults[0].source == .spotifyCurrentTrack)
        precondition(currentResults[0].track.title == "Search Song")

        let duplicateManager = SongSearchManager(providers: [
            FixedSearchProvider(name: "duplicates", results: [
                lrclibResults[0],
                SongSearchResult(
                    id: "same-song-different-release",
                    source: .lrclib,
                    track: Track(
                        title: "Search Song",
                        artist: "Search Artist",
                        album: "Alternate Release",
                        duration: 199
                    ),
                    confidence: 0.4
                )
            ])
        ])
        let duplicateTask = duplicateManager.search(query: SongSearchQuery(text: "Search Song"))
        await duplicateTask?.value
        guard case .results(_, let deduplicatedResults) = duplicateManager.state else {
            fatalError("expected de-duplicated search results")
        }
        precondition(deduplicatedResults.count == 1)

        let old = SongSearchResult(
            id: "old",
            source: .local,
            track: track,
            confidence: 0.5,
            lyrics: nil
        )
        let latestTrack = Track(title: "Latest", artist: "Artist", album: "Album", duration: 180)
        let latest = SongSearchResult(
            id: "latest",
            source: .local,
            track: latestTrack,
            confidence: 0.9,
            lyrics: nil
        )
        let manager = SongSearchManager(providers: [
            DelayedSearchProvider(name: "slow", delay: 250_000_000, acceptedQuery: "old", result: old),
            DelayedSearchProvider(name: "fast", delay: 20_000_000, acceptedQuery: "latest", result: latest)
        ])
        let firstTask = manager.search(query: SongSearchQuery(text: "old"))
        _ = manager.search(query: SongSearchQuery(text: "latest"))
        await firstTask?.value
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard case .results(_, let results) = manager.state else {
            fatalError("expected manager results")
        }
        precondition(results.map(\.id) == ["latest"])

        print("song search contract passed")
    }
}
