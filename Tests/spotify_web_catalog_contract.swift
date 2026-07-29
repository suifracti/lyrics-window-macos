import Foundation

#if DEBUG
private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, [String: String], Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler,
              let client,
              let url = request.url else { return }
        let (status, headers, data) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: data)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class CountingSpotifyTokenStore: SpotifyTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: SpotifyTokenRecord?
    private(set) var loadCount = 0

    init(record: SpotifyTokenRecord?) {
        stored = record
    }

    func load() throws -> SpotifyTokenRecord? {
        lock.lock(); defer { lock.unlock() }
        loadCount += 1
        return stored
    }

    func save(_ record: SpotifyTokenRecord) throws {
        lock.lock(); defer { lock.unlock() }
        stored = record
    }

    func delete() throws {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}
#endif

@main
struct SpotifyWebCatalogContract {
    static func main() async throws {
        precondition(SpotifyOAuthConfiguration.redirectURI == "http://127.0.0.1:49153/callback")
        precondition(SongSearchQuery(text: "https://open.spotify.com/track/0123456789012345678901?si=x").spotifyTrackID == "0123456789012345678901")
        precondition(SongSearchQuery(text: "spotify:track:0123456789012345678901").spotifyTrackID == "0123456789012345678901")
        precondition(SongSearchQuery(text: "not-a-track-id").spotifyTrackID == nil)

#if DEBUG
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let base = URL(string: "https://api.example.test/v1")!
        let tokenEndpoint = URL(string: "https://accounts.example.test/api/token")!
        let service = SpotifyCatalogService(
            session: session,
            baseURL: base,
            authorizationEndpoint: URL(string: "https://accounts.example.test/authorize")!,
            tokenEndpoint: tokenEndpoint
        )
        let accessFixture = String(repeating: "a", count: 24)
        let refreshedFixture = String(repeating: "b", count: 24)

        let payload = """
        {
          "tracks": {
            "href": "https://api.example.test/v1/search",
            "limit": 20,
            "next": null,
            "offset": 0,
            "previous": null,
            "total": 1,
            "items": [{
              "album": {
                "album_type": "single",
                "artists": [{"id":"artist-1","name":"yama","uri":"spotify:artist:artist-1"}],
                "images": [{"height":640,"url":"https://i.scdn.co/test.jpg","width":640}],
                "name": "春を告げる",
                "release_date": "2020-02-28"
              },
              "artists": [
                {"id":"artist-1","name":"yama","uri":"spotify:artist:artist-1"},
                {"id":"artist-2","name":"Guest","uri":"spotify:artist:artist-2"}
              ],
              "duration_ms": 180123,
              "explicit": false,
              "external_ids": {"isrc":"JP-TEST-0001"},
              "id": "0123456789012345678901",
              "name": "春を告げる",
              "popularity": 71,
              "uri": "spotify:track:0123456789012345678901"
            }]
          }
        }
        """.data(using: .utf8)!

        StubURLProtocol.handler = { request in
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(accessFixture)")
            precondition(request.url?.path == "/v1/search")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            precondition(query.first(where: { $0.name == "limit" })?.value == "10")
            return (200, ["Content-Type": "application/json"], payload)
        }
        let response = try await service.searchTracks(query: "春を告げる yama", accessToken: accessFixture)
        let result = SpotifyTrackMapper.result(from: response.tracks.items[0])
        precondition(result.source == .spotifyCatalog)
        precondition(result.catalogMetadata?.artists.count == 2)
        precondition(result.catalogMetadata?.isrc == "JP-TEST-0001")
        precondition(result.catalogMetadata?.releaseDate == "2020-02-28")
        precondition(result.catalogMetadata?.popularity == 71)
        precondition(result.track.duration == 180.123)
        precondition(result.track.spotifyId == "0123456789012345678901")
        precondition(result.asSongSearchResult().lyrics == nil)

        let rawSearchPayload = String(data: payload, encoding: .utf8)!
            .replacingOccurrences(of: "春を告げる", with: "春を告げる - From THE FIRST TAKE")
            .replacingOccurrences(of: "0123456789012345678901", with: "1111111111111111111111")
            .data(using: .utf8)!

        let authURL = try service.authorizationURL(
            clientID: "client-id",
            state: "state-value",
            codeChallenge: "challenge-value",
            redirectURI: "http://127.0.0.1:43210/callback"
        )
        let authComponents = URLComponents(url: authURL, resolvingAgainstBaseURL: false)!
        let authItems = Dictionary(uniqueKeysWithValues: (authComponents.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        precondition(authItems["code_challenge_method"] == "S256")
        precondition(authItems["redirect_uri"] == "http://127.0.0.1:43210/callback")
        precondition(authItems["state"] == "state-value")

        let tokenJSON = "{\"access_token\":\"\(refreshedFixture)\",\"token_type\":\"Bearer\",\"expires_in\":3600,\"refresh_token\":\"\(refreshedFixture)\",\"scope\":\"\"}".data(using: .utf8)!
        let tokenStore = InMemorySpotifyTokenStore(record: SpotifyTokenRecord(
            accessToken: accessFixture,
            refreshToken: accessFixture,
            expiresAt: Date().addingTimeInterval(5),
            scope: nil
        ))
        StubURLProtocol.handler = { request in
            guard request.url?.path == tokenEndpoint.path else {
                fatalError("unexpected token refresh request")
            }
            return (200, ["Content-Type": "application/json"], tokenJSON)
        }
        let manager = await MainActor.run {
            SpotifyAuthorizationManager(
                configuration: SpotifyOAuthConfiguration(clientID: "client-id"),
                tokenStore: tokenStore,
                catalogService: service
            )
        }
        let refreshed = try await manager.accessToken()
        precondition(refreshed == refreshedFixture)
        let saved = try tokenStore.load()
        precondition(saved?.refreshToken == refreshedFixture)
        precondition(manager.state.isAuthorized)

        let providerStore = InMemorySpotifyTokenStore(record: SpotifyTokenRecord(
            accessToken: accessFixture,
            refreshToken: accessFixture,
            expiresAt: Date().addingTimeInterval(3600),
            scope: nil
        ))
        let providerManager = await MainActor.run {
            SpotifyAuthorizationManager(
                configuration: SpotifyOAuthConfiguration(clientID: "client-id"),
                tokenStore: providerStore,
                catalogService: service
            )
        }
        StubURLProtocol.handler = { request in
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(accessFixture)")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let searchQuery = query.first(where: { $0.name == "q" })?.value
            if searchQuery == "春を告げる yama" {
                return (200, ["Content-Type": "application/json"], rawSearchPayload)
            }
            if searchQuery == "春を告げる" {
                return (200, ["Content-Type": "application/json"], payload)
            }
            fatalError("unexpected catalog query: \(searchQuery ?? "nil")")
        }
        let provider = await MainActor.run {
            SpotifySearchProvider(authorization: providerManager, service: service)
        }
        let recovered = try await provider.search(query: SongSearchQuery(text: "春を告げる yama"))
        precondition(recovered.first?.track.title == "春を告げる")
        precondition(recovered.first?.catalogMetadata?.artists.first?.name == "yama")

        let cachedStore = CountingSpotifyTokenStore(record: SpotifyTokenRecord(
            accessToken: accessFixture,
            refreshToken: accessFixture,
            expiresAt: Date().addingTimeInterval(3600),
            scope: nil
        ))
        let cachedManager = await MainActor.run {
            SpotifyAuthorizationManager(
                configuration: SpotifyOAuthConfiguration(clientID: "client-id"),
                tokenStore: cachedStore,
                catalogService: service
            )
        }
        _ = try await cachedManager.accessToken()
        _ = try await cachedManager.accessToken()
        precondition(cachedStore.loadCount == 1, "token store must be loaded once per authorization manager")

        let keychainService = "com.spotifylyrics.contract.\(UUID().uuidString)"
        let keychainStore = KeychainSpotifyTokenStore(service: keychainService, account: "contract")
        let keychainFixture = SpotifyTokenRecord(
            accessToken: "contract-access",
            refreshToken: "contract-refresh",
            expiresAt: Date().addingTimeInterval(3600),
            scope: nil
        )
        do {
            try keychainStore.save(keychainFixture)
            let loadedKeychainFixture = try keychainStore.load()
            precondition(loadedKeychainFixture == keychainFixture)
            try keychainStore.delete()
        } catch {
            fatalError("data protection keychain contract failed: \(error)")
        }

        StubURLProtocol.handler = { _ in (429, ["Retry-After": "7"], Data()) }
        do {
            _ = try await service.searchTracks(query: "rate", accessToken: accessFixture)
            fatalError("429 must throw")
        } catch let error as SpotifyCatalogError {
            guard case .rateLimited(let retryAfter) = error else { fatalError("wrong 429 error: \(error)") }
            precondition(retryAfter == 7)
        }

        print("spotify web catalog contract passed")
#endif
    }
}
