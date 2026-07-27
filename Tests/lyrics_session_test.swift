import Foundation

private struct DelayedLyricsProvider: LyricsProvider {
    let delays: [String: UInt64]

    var name: String { "delayed-test" }

    func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult {
        try? await Task.sleep(nanoseconds: delays[track.title] ?? 10_000_000)
        let line = LyricLine(timestamp: 0, originalText: "歌词：\(track.title)")
        return .match(
            LyricsDocument(
                identity: identity,
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: track.duration,
                lines: [line],
                source: .local,
                confidence: 1
            )
        )
    }
}

@main
@MainActor
struct LyricsSessionContract {
    static func main() async {
        let provider = DelayedLyricsProvider(
            delays: [
                "Track A": 250_000_000,
                "Track B": 50_000_000
            ]
        )
        let controller = LyricsSessionController(provider: provider)
        let trackA = Track(title: "Track A", artist: "Artist", album: "Album", duration: 180)
        let trackB = Track(title: "Track B", artist: "Artist", album: "Album", duration: 180)

        precondition(controller.lyrics.isEmpty)
        controller.begin(track: trackA, identity: TrackIdentity(track: trackA))
        guard case .loading = controller.state else { fatalError("expected loading A") }
        try? await Task.sleep(nanoseconds: 20_000_000)
        controller.begin(track: trackB, identity: TrackIdentity(track: trackB))
        try? await Task.sleep(nanoseconds: 350_000_000)

        guard let document = controller.state.document else { fatalError("expected loaded/alignmentQueued B") }
        precondition(document.identity == TrackIdentity(track: trackB))
        precondition(controller.lyrics.first?.originalText == "歌词：Track B")

        controller.enterMockPreview(lines: [LyricLine(timestamp: 0, originalText: "Mock only")])
        guard case .mockPreview = controller.state else { fatalError("expected explicit mock preview") }
        precondition(controller.lyrics.first?.originalText == "Mock only")
        controller.begin(track: trackB, identity: TrackIdentity(track: trackB))
        guard case .loading = controller.state else { fatalError("expected real session after mock") }
        print("lyrics session contract passed")
    }
}
