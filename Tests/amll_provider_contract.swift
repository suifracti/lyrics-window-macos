import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class StubAMLLSession: AMLLSession, @unchecked Sendable {
    let data: Data
    let statusCode: Int
    private(set) var requests: [URLRequest] = []

    init(body: String, statusCode: Int) {
        self.data = Data(body.utf8)
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

@main
struct AMLLProviderContract {
    static func main() async {
        let lrc = """
        [ti:AMLL Song]
        [ar:AMLL Artist]
        [00:01.00]first line
        [00:02.50]second line
        """
        let session = StubAMLLSession(body: lrc, statusCode: 200)
        let provider = AMLLLyricsProvider(
            session: session,
            baseURL: URL(string: "https://example.invalid/spotify-lyrics")!
        )
        let track = Track(
            title: "AMLL Song",
            artist: "AMLL Artist",
            album: "Album",
            duration: 180,
            spotifyId: "AbC123xYz"
        )
        let identity = TrackIdentity(track: track)

        let first = await provider.lookup(track: track, identity: identity)
        guard case .match(let document) = first else {
            fatalError("expected AMLL exact-ID match")
        }
        precondition(document.source == .amll)
        precondition(document.isSynchronized)
        precondition(document.lines.map(\.originalText) == ["first line", "second line"])
        precondition(document.spotifyTrackID == "AbC123xYz")
        precondition(session.requests.first?.url?.lastPathComponent == "AbC123xYz.lrc")

        _ = await provider.lookup(track: track, identity: identity)
        precondition(session.requests.count == 1, "same Spotify ID should be served from provider cache")

        let missingID = Track(title: "No ID", artist: "Artist", album: "", duration: 10)
        let missing = await provider.lookup(track: missingID, identity: TrackIdentity(track: missingID))
        guard case .noMatch = missing else { fatalError("missing Spotify ID must not use fuzzy lookup") }

        let notFoundSession = StubAMLLSession(body: "", statusCode: 404)
        let notFoundProvider = AMLLLyricsProvider(
            session: notFoundSession,
            baseURL: URL(string: "https://example.invalid/spotify-lyrics")!
        )
        let notFound = await notFoundProvider.lookup(track: track, identity: identity)
        guard case .noMatch = notFound else { fatalError("AMLL 404 should be noMatch") }

        print("AMLL provider contract passed")
    }
}
