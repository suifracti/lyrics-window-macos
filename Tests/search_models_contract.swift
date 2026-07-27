import Foundation

@main
struct SearchModelsContract {
    static func main() async {
        // Track search results must never carry lyrics bodies.
        let track = Track(title: "Isolation Song", artist: "Isolation Artist", album: "Album", duration: 200)
        let trackResult = TrackSearchResult(
            id: "track-1",
            source: .local,
            track: track,
            confidence: 0.9
        )
        let bridged = trackResult.asSongSearchResult()
        precondition(bridged.lyrics == nil, "track search bridge must drop lyrics bodies")
        precondition(bridged.track.title == track.title)

        // Local track search returns metadata only.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("search-models-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("Isolation Song.lrc")
        let original = """
        [ti:Isolation Song]
        [ar:Isolation Artist]
        [al:Album]
        [00:01.00]line one
        [00:02.00]line two
        """
        try! original.write(to: file, atomically: true, encoding: .utf8)
        let originalData = try! Data(contentsOf: file)

        let index = LocalLyricsIndex(searchDirectories: [root])
        let local = LocalSearchProvider(index: index)
        let localTrackResults = try! await local.search(query: SongSearchQuery(text: "Isolation Song"))
        precondition(localTrackResults.count == 1)
        precondition(localTrackResults[0].source == .local)
        precondition(localTrackResults[0].track.title == "Isolation Song")
        precondition(localTrackResults[0].asSongSearchResult().lyrics == nil)

        // Shared index is read-only and scanned once.
        _ = index.entries()
        precondition(index.hasScanned)
        let second = index.entries()
        precondition(second.count == 1)
        precondition(index.fileBytesUnchanged(relativeTo: [file: originalData]))
        let after = try! String(contentsOf: file, encoding: .utf8)
        precondition(after == original)

        // Local lyrics provider reuses the same index without rewriting files.
        let lyricsProvider = LocalLyricsProvider(index: index)
        let identity = TrackIdentity(track: track)
        let lookup = await lyricsProvider.lookup(track: track, identity: identity)
        guard case .match(let document) = lookup else {
            fatalError("expected local lyrics match, got \(lookup)")
        }
        precondition(document.identity == identity)
        precondition(document.lines.count == 2)
        precondition(index.fileBytesUnchanged(relativeTo: [file: originalData]))

        // CurrentTrackResolver is not a free-text catalog; it only mirrors playback.
        let playback = FixedPlaybackProvider(
            track: Track(
                title: "Now Playing",
                artist: "Live Artist",
                album: "Live Album",
                duration: 180,
                spotifyId: "spotify:track:live"
            )
        )
        let resolver = CurrentTrackResolver(playbackProvider: playback)
        let hit = try! await resolver.search(query: SongSearchQuery(text: "Live Artist"))
        precondition(hit.count == 1)
        precondition(hit[0].source == .spotifyCurrentTrack)
        let miss = try! await resolver.search(query: SongSearchQuery(text: "totally unrelated query zzqq"))
        precondition(miss.isEmpty)

        // Deprecated LRCLIB track-search adapter stays empty.
        let disabled = LRCLIBProvider()
        let lrclibTrackResults = (try? await disabled.search(query: SongSearchQuery(text: "Isolation Song"))) ?? []
        precondition(lrclibTrackResults.isEmpty)

        // TrackSearchManager isolates provider failures and cancels stale requests.
        let slow = DelayedTrackProvider(
            name: "slow-local",
            delay: 200_000_000,
            acceptedQuery: "old",
            result: TrackSearchResult(
                id: "old",
                source: .local,
                track: Track(title: "Old", artist: "A", album: "B", duration: 100),
                confidence: 0.5
            )
        )
        let fast = DelayedTrackProvider(
            name: "fast-local",
            delay: 10_000_000,
            acceptedQuery: "latest",
            result: TrackSearchResult(
                id: "latest",
                source: .local,
                track: Track(title: "Latest", artist: "A", album: "B", duration: 100),
                confidence: 0.9
            )
        )
        let failing = FailingTrackProvider(name: "broken", error: .networkUnavailable)
        let manager = TrackSearchManager(providers: [slow, fast, failing])
        let first = manager.search(query: SongSearchQuery(text: "old"))
        _ = manager.search(query: SongSearchQuery(text: "latest"))
        await first?.value
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard case .results(_, let results) = manager.state else {
            fatalError("expected latest results despite partial provider failure: \(manager.state)")
        }
        precondition(results.map(\.id) == ["latest"])
        precondition(results.allSatisfy { _ in true })

        // Compatibility SongSearchManager mirrors track manager without lyrics payloads.
        let songManager = SongSearchManager(providers: [local as TrackSearchProvider])
        let task = songManager.search(query: SongSearchQuery(text: "Isolation"))
        await task?.value
        guard case .results(_, let songResults) = songManager.state else {
            fatalError("expected song manager results")
        }
        precondition(songResults.allSatisfy { $0.lyrics == nil })

        print("search models contract passed")
    }
}

@MainActor
private final class FixedPlaybackProvider: PlaybackProvider {
    let displayName = "fixed-playback"
    let track: Track
    init(track: Track) { self.track = track }
    func refresh() async -> PlaybackSnapshot {
        PlaybackSnapshot(
            status: .ready,
            track: ProviderTrack(
                id: track.spotifyId,
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: track.duration,
                artworkURL: track.artworkURL,
                spotifyURL: track.spotifyURL,
                isrc: track.isrc
            ),
            position: 1,
            isPlaying: true
        )
    }
    func play() async throws {}
    func pause() async throws {}
    func previous() async throws {}
    func next() async throws {}
    func seek(to position: TimeInterval) async throws {}
}

private struct DelayedTrackProvider: TrackSearchProvider {
    let name: String
    let delay: UInt64
    let acceptedQuery: String
    let result: TrackSearchResult

    func search(query: TrackSearchQuery) async throws -> [TrackSearchResult] {
        try await Task.sleep(nanoseconds: delay)
        try Task.checkCancellation()
        guard query.text == acceptedQuery else { return [] }
        return [result]
    }
}

private struct FailingTrackProvider: TrackSearchProvider {
    let name: String
    let error: SongSearchError
    func search(query: TrackSearchQuery) async throws -> [TrackSearchResult] {
        throw error
    }
}
