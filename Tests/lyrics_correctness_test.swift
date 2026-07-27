import Foundation

private final class OutcomeSession: LRCLIBSession {
    enum Outcome {
        case response(Data, Int)
        case failure(Error)
    }

    let outcome: Outcome
    private(set) var requestCount = 0

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestCount += 1
        switch outcome {
        case .response(let data, let statusCode):
            return (
                data,
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
            )
        case .failure(let error):
            throw error
        }
    }
}

private final class SequenceLyricsProvider: LyricsProvider {
    let results: [LyricsLookupResult]
    private(set) var calls = 0

    init(results: [LyricsLookupResult]) {
        self.results = results
    }

    var name: String { "sequence-test" }

    func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult {
        defer { calls += 1 }
        return results[min(calls, results.count - 1)]
    }
}

@main
@MainActor
struct LyricsCorrectnessContract {
    static func main() async {
        let track = Track(
            title: "Error Song",
            artist: "Error Artist",
            album: "Error Album",
            duration: 180
        )
        let identity = TrackIdentity(track: track)
        let baseURL = URL(string: "https://example.test/api")!

        let network = LRCLIBLyricsProvider(
            session: OutcomeSession(outcome: .failure(URLError(.notConnectedToInternet))),
            baseURL: baseURL
        )
        guard case .failed(.networkUnavailable) = await network.lookup(track: track, identity: identity) else {
            fatalError("expected networkUnavailable")
        }

        let timeout = LRCLIBLyricsProvider(
            session: OutcomeSession(outcome: .failure(URLError(.timedOut))),
            baseURL: baseURL
        )
        guard case .failed(.timedOut) = await timeout.lookup(track: track, identity: identity) else {
            fatalError("expected timedOut")
        }

        let server = LRCLIBLyricsProvider(
            session: OutcomeSession(outcome: .response(Data("{}".utf8), 503)),
            baseURL: baseURL
        )
        guard case .failed(.serverError(503)) = await server.lookup(track: track, identity: identity) else {
            fatalError("expected serverError")
        }

        let parse = LRCLIBLyricsProvider(
            session: OutcomeSession(outcome: .response(Data("not-json".utf8), 200)),
            baseURL: baseURL
        )
        guard case .failed(.parseFailure) = await parse.lookup(track: track, identity: identity) else {
            fatalError("expected parseFailure")
        }

        let noMatch = LRCLIBLyricsProvider(
            session: OutcomeSession(outcome: .response(Data("{}".utf8), 404)),
            baseURL: baseURL
        )
        guard case .noMatch = await noMatch.lookup(track: track, identity: identity) else {
            fatalError("expected noMatch after direct and search 404")
        }

        let plainLines = [
            LyricLine(timestamp: 0, originalText: "第一行"),
            LyricLine(timestamp: 0, originalText: "第二行")
        ]
        precondition(LyricsTimeline.activeLineIndex(
            lines: plainLines,
            time: 30,
            isSynchronized: false
        ) == nil)
        let timedLines = [
            LyricLine(timestamp: 10, originalText: "第一行"),
            LyricLine(timestamp: 20, originalText: "第二行")
        ]
        precondition(LyricsTimeline.activeLineIndex(
            lines: timedLines,
            time: 25,
            isSynchronized: true
        ) == 1)
        precondition(LyricsTimeline.presentationDistance(
            index: 0,
            currentIndex: nil,
            isSynchronized: false
        ) == 0)
        precondition(LyricsTimeline.validSeekTimestamp(
            for: LyricLine(timestamp: 12.5, originalText: "可跳转"),
            isSynchronized: true,
            duration: 180
        ) == 12.5)
        precondition(LyricsTimeline.validSeekTimestamp(
            for: LyricLine(timestamp: 0, originalText: "纯文本"),
            isSynchronized: false,
            duration: 180
        ) == nil)
        precondition(LyricsTimeline.validSeekTimestamp(
            for: LyricLine(timestamp: -.infinity, originalText: "负无穷"),
            isSynchronized: true,
            duration: 180
        ) == nil)
        precondition(LyricsTimeline.validSeekTimestamp(
            for: LyricLine(timestamp: .nan, originalText: "非数字"),
            isSynchronized: true,
            duration: 180
        ) == nil)
        precondition(LyricsTimeline.validSeekTimestamp(
            for: LyricLine(timestamp: 181, originalText: "超出歌曲"),
            isSynchronized: true,
            duration: 180
        ) == nil)

        let trackA = Track(title: "Track A", artist: "Artist", album: "Album", duration: 180)
        let trackB = Track(title: "Track B", artist: "Artist", album: "Album", duration: 180)
        let candidateB = LyricsCandidate(
            id: "candidate-b",
            identity: TrackIdentity(track: trackB),
            title: trackB.title,
            artist: trackB.artist,
            album: trackB.album,
            duration: trackB.duration,
            lines: [LyricLine(timestamp: 0, originalText: "B")],
            source: .lrclib,
            confidence: 0.55
        )
        let retryDocument = LyricsDocument(
            identity: TrackIdentity(track: trackA),
            title: trackA.title,
            artist: trackA.artist,
            album: trackA.album,
            duration: trackA.duration,
            lines: [LyricLine(timestamp: 0, originalText: "A")],
            source: .local
        )
        let sequence = SequenceLyricsProvider(results: [
            .candidates([candidateB]),
            .match(retryDocument)
        ])
        let controller = LyricsSessionController(provider: sequence)
        controller.begin(track: trackB, identity: TrackIdentity(track: trackB))
        try? await Task.sleep(nanoseconds: 10_000_000)
        guard case .candidates(_, let candidates) = controller.state,
              candidates.count == 1,
              controller.lyrics.isEmpty else {
            fatalError("expected explicit candidates state without auto adoption")
        }
        let wrongCandidate = LyricsCandidate(
            id: "wrong",
            identity: TrackIdentity(track: trackA),
            title: trackA.title,
            artist: trackA.artist,
            album: trackA.album,
            duration: trackA.duration,
            lines: retryDocument.lines,
            source: .local,
            confidence: 0.9
        )
        controller.adopt(candidate: wrongCandidate)
        guard case .candidates = controller.state else {
            fatalError("candidate from another identity must be ignored")
        }
        controller.adopt(candidate: candidateB)
        guard case .loaded(let adopted) = controller.state,
              adopted.identity == TrackIdentity(track: trackB) else {
            fatalError("expected manually adopted candidate")
        }

        let recoveryDocument = LyricsDocument(
            identity: TrackIdentity(track: trackB),
            title: trackB.title,
            artist: trackB.artist,
            album: trackB.album,
            duration: trackB.duration,
            lines: [LyricLine(timestamp: 2, originalText: "恢复后歌词")],
            source: .lrclib
        )
        let recoveryProvider = SequenceLyricsProvider(results: [
            .failed(.networkUnavailable),
            .match(recoveryDocument),
            .match(recoveryDocument)
        ])
        let recoveryController = LyricsSessionController(provider: recoveryProvider)
        let recoveryIdentity = TrackIdentity(track: trackB)
        recoveryController.begin(track: trackB, identity: recoveryIdentity)
        try? await Task.sleep(nanoseconds: 10_000_000)
        guard case .failed(let failedIdentity, .networkUnavailable) = recoveryController.state,
              failedIdentity == recoveryIdentity else {
            fatalError("expected network failure before recovery retry")
        }
        precondition(recoveryController.retryAfterNetworkRecovery(track: trackB, identity: recoveryIdentity))
        precondition(!recoveryController.retryAfterNetworkRecovery(track: trackB, identity: recoveryIdentity))
        try? await Task.sleep(nanoseconds: 10_000_000)
        guard case .loaded = recoveryController.state,
              recoveryProvider.calls == 2 else {
            fatalError("network recovery retry must be bounded to one automatic attempt")
        }

        controller.begin(track: trackA, identity: TrackIdentity(track: trackA))
        try? await Task.sleep(nanoseconds: 10_000_000)
        guard case .match = sequence.results[1], case .loaded = controller.state else {
            fatalError("expected retry lookup to load the current identity")
        }

        print("lyrics correctness contract passed")
    }
}
