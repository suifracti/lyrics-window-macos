import Foundation

/// The playback slice contract does not compile the capture/alignment graph.
/// Keep a protocol-shaped stand-in so PlaybackState can still be tested in
/// isolation when it notifies the product controller.
@MainActor
final class AutomaticAlignmentJobController {
    static let shared = AutomaticAlignmentJobController()

    func bind(playback: PlaybackState) {}
    func notePlaybackContextChanged() {}
    func notifySeek(from: TimeInterval, to: TimeInterval) {}
    func notifyTrackChanged(previousKey: String?, nextKey: String) {}
}

@MainActor
private final class ScriptedPlaybackProvider: PlaybackProvider {
    let displayName = "scripted-playback"
    private(set) var commandLog: [String] = []
    var snapshot: PlaybackSnapshot

    init(snapshot: PlaybackSnapshot) {
        self.snapshot = snapshot
    }

    func refresh() async -> PlaybackSnapshot {
        snapshot
    }

    func play() async throws {
        commandLog.append("play")
        snapshot = PlaybackSnapshot(
            status: snapshot.status,
            track: snapshot.track,
            position: snapshot.position,
            isPlaying: true
        )
    }

    func pause() async throws {
        commandLog.append("pause")
        snapshot = PlaybackSnapshot(
            status: snapshot.status,
            track: snapshot.track,
            position: snapshot.position,
            isPlaying: false
        )
    }

    func previous() async throws {
        commandLog.append("previous")
    }

    func next() async throws {
        commandLog.append("next")
    }

    func seek(to position: TimeInterval) async throws {
        commandLog.append("seek:\(Int(position))")
        snapshot = PlaybackSnapshot(
            status: snapshot.status,
            track: snapshot.track,
            position: position,
            isPlaying: snapshot.isPlaying
        )
    }
}

@MainActor
private final class DelayedRefreshProvider: PlaybackProvider {
    let displayName = "delayed-refresh"
    let staleSnapshot: PlaybackSnapshot
    var latestSnapshot: PlaybackSnapshot
    private var refreshCount = 0

    init(staleSnapshot: PlaybackSnapshot, latestSnapshot: PlaybackSnapshot) {
        self.staleSnapshot = staleSnapshot
        self.latestSnapshot = latestSnapshot
    }

    func refresh() async -> PlaybackSnapshot {
        refreshCount += 1
        if refreshCount == 1 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            return staleSnapshot
        }
        return latestSnapshot
    }

    func play() async throws {}
    func pause() async throws {}
    func previous() async throws {}
    func next() async throws {}
    func seek(to position: TimeInterval) async throws {}
}

private struct NoLyricsProvider: LyricsProvider {
    var name: String { "no-lyrics-test" }

    func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult {
        .noLyrics
    }
}

private struct NetworkFailureLyricsProvider: LyricsProvider {
    var name: String { "network-failure-test" }

    func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult {
        .failed(.networkUnavailable)
    }
}

@main
@MainActor
struct PlaybackStateContract {
    static func main() async {
        let trackA = ProviderTrack(
            id: "spotify:track:a",
            title: "Track A",
            artist: "Artist A",
            album: "Album A",
            duration: 240,
            artworkURL: URL(string: "https://example.test/a.jpg")
        )
        let trackB = ProviderTrack(
            id: "spotify:track:b",
            title: "Track B",
            artist: "Artist B",
            album: "Album B",
            duration: 300,
            artworkURL: URL(string: "https://example.test/b.jpg")
        )
        let provider = ScriptedPlaybackProvider(
            snapshot: PlaybackSnapshot(status: .ready, track: trackA, position: 12, isPlaying: true)
        )
        let state = PlaybackState(provider: provider, lyricsProvider: NoLyricsProvider())
        state.startProvider()
        try? await Task.sleep(nanoseconds: 60_000_000)

        precondition(state.hasLiveTrack)
        precondition(state.currentTrack.title == "Track A")
        precondition(state.currentTrackIdentity?.stableKey.contains("spotify-id:a") == true)
        precondition(state.currentTime >= 12)

        state.togglePlayPause()
        try? await Task.sleep(nanoseconds: 320_000_000)
        precondition(provider.commandLog.contains("pause"))
        precondition(!state.isPlaying)

        state.togglePlayPause()
        try? await Task.sleep(nanoseconds: 320_000_000)
        precondition(provider.commandLog.contains("play"))
        precondition(state.isPlaying)

        state.seek(to: 88)
        try? await Task.sleep(nanoseconds: 320_000_000)
        precondition(provider.commandLog.contains("seek:88"))
        precondition(abs(state.currentTime - 88) < 2)

        let timeBeforeInvalidSeek = state.currentTime
        state.seek(to: .nan, source: "invalid-test")
        state.seek(to: 999, source: "invalid-test")
        try? await Task.sleep(nanoseconds: 120_000_000)
        precondition(abs(state.currentTime - timeBeforeInvalidSeek) < 1)

        let recoveryState = PlaybackState(provider: provider, lyricsProvider: NetworkFailureLyricsProvider())
        recoveryState.startProvider()
        try? await Task.sleep(nanoseconds: 80_000_000)
        let recoveryTime = recoveryState.currentTime
        precondition(recoveryState.lyricsState.identity == recoveryState.currentTrackIdentity)
        recoveryState.retryLyrics()
        try? await Task.sleep(nanoseconds: 30_000_000)
        precondition(abs(recoveryState.currentTime - recoveryTime) < 1)

        provider.snapshot = PlaybackSnapshot(status: .ready, track: trackB, position: 4, isPlaying: false)
        state.nextTrack()
        try? await Task.sleep(nanoseconds: 320_000_000)
        precondition(provider.commandLog.contains("next"))
        precondition(state.currentTrack.title == "Track B")
        precondition(state.currentTrackIdentity?.stableKey.contains("spotify-id:b") == true)
        precondition(state.currentTime == 4)
        precondition(state.lyrics.isEmpty)

        provider.snapshot = PlaybackSnapshot(status: .ready, track: trackA, position: 3, isPlaying: false)
        state.previousTrack()
        try? await Task.sleep(nanoseconds: 320_000_000)
        precondition(provider.commandLog.contains("previous"))
        precondition(state.currentTrack.title == "Track A")

        provider.snapshot = PlaybackSnapshot(status: .notRunning, track: nil, position: 0, isPlaying: false)
        state.reconnectSpotify()
        precondition(!state.hasLiveTrack)
        precondition(state.lyrics.isEmpty)
        try? await Task.sleep(nanoseconds: 80_000_000)
        precondition(!state.hasLiveTrack)
        precondition(state.lyrics.isEmpty)

        provider.snapshot = PlaybackSnapshot(status: .ready, track: trackB, position: 9, isPlaying: true)
        state.reconnectSpotify()
        try? await Task.sleep(nanoseconds: 80_000_000)
        precondition(state.hasLiveTrack)
        precondition(state.currentTrack.title == "Track B")
        precondition(state.currentTime >= 9)

        let raceProvider = DelayedRefreshProvider(
            staleSnapshot: PlaybackSnapshot(status: .ready, track: trackA, position: 1, isPlaying: false),
            latestSnapshot: PlaybackSnapshot(status: .ready, track: trackB, position: 7, isPlaying: false)
        )
        let raceState = PlaybackState(provider: raceProvider, lyricsProvider: NoLyricsProvider())
        raceState.startProvider()
        try? await Task.sleep(nanoseconds: 20_000_000)
        raceProvider.latestSnapshot = PlaybackSnapshot(status: .ready, track: trackB, position: 7, isPlaying: false)
        raceState.reconnectSpotify()
        try? await Task.sleep(nanoseconds: 450_000_000)
        precondition(raceState.currentTrack.title == "Track B")
        precondition(raceState.currentTime == 7)

        print("playback state contract passed")
    }
}
