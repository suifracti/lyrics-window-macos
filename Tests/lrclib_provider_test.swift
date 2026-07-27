import Foundation

private final class StubLRCLIBSession: LRCLIBSession {
    var requests: [URLRequest] = []
    let responseData: Data

    init(responseData: Data) {
        self.responseData = responseData
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return (
            responseData,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
        )
    }
}

private struct StubProvider: LyricsProvider {
    let result: LyricsLookupResult
    let name: String

    func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult {
        result
    }
}

@main
struct LRCLIBProviderContract {
    static func main() async {
        let payload = """
        {
          "id": 42,
          "trackName": "LRCLIB Song",
          "artistName": "LRCLIB Artist",
          "albumName": "LRCLIB Album",
          "duration": 201,
          "instrumental": false,
          "plainLyrics": "A lyric",
          "syncedLyrics": "[00:01.00]A lyric"
        }
        """.data(using: .utf8)!
        let session = StubLRCLIBSession(responseData: payload)
        let provider = LRCLIBLyricsProvider(
            session: session,
            baseURL: URL(string: "https://example.test/api")!
        )
        let track = Track(
            title: "LRCLIB Song",
            artist: "LRCLIB Artist",
            album: "LRCLIB Album",
            duration: 201
        )
        let identity = TrackIdentity(track: track)
        let result = await provider.lookup(track: track, identity: identity)
        guard case .match(let document) = result else {
            fatalError("expected LRCLIB match, got \(result)")
        }
        precondition(document.source == .lrclib)
        precondition(document.lines.first?.originalText == "A lyric")
        precondition(document.lines.first?.translationText == nil)
        precondition(session.requests.count == 1)
        let query = URLComponents(url: session.requests[0].url!, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? ""
        precondition(query.contains("track_name=LRCLIB%20Song"))
        precondition(query.contains("artist_name=LRCLIB%20Artist"))

        let composite = CompositeLyricsProvider(providers: [
            StubProvider(result: .noMatch, name: "empty"),
            StubProvider(result: result, name: "lrclib")
        ])
        let compositeResult = await composite.lookup(track: track, identity: identity)
        guard case .match = compositeResult else {
            fatalError("expected composite match")
        }
        print("LRCLIB provider contract passed")
    }
}
