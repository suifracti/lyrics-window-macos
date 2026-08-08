import Foundation

public protocol AMLLSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: AMLLSession {}

/// Exact-identity reader for the CC0 AMLL TTML database's Spotify LRC mirror.
/// It deliberately performs no title search: an absent Spotify ID or a 404
/// falls through to the next provider without weakening identity matching.
public final class AMLLLyricsProvider: LyricsProvider, @unchecked Sendable {
    public let name = "AMLL"

    private enum CacheEntry {
        case match(LyricsDocument)
        case noMatch
    }

    private let session: AMLLSession
    private let baseURL: URL
    private let timeout: TimeInterval
    private let cacheLock = NSLock()
    private var cache: [String: CacheEntry] = [:]

    public init(
        session: AMLLSession = URLSession.shared,
        baseURL: URL = URL(
            string: "https://raw.githubusercontent.com/amll-dev/amll-ttml-db/main/spotify-lyrics"
        )!,
        timeout: TimeInterval = 8
    ) {
        self.session = session
        self.baseURL = baseURL
        self.timeout = timeout
    }

    public func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult {
        guard !Task.isCancelled else { return .failed(.cancelled) }
        guard let spotifyID = Self.casePreservingSpotifyTrackID(from: track, fallback: identity) else {
            return .noMatch
        }

        if let cached = cachedResult(for: spotifyID) {
            return cached
        }

        var request = URLRequest(
            url: baseURL.appendingPathComponent(spotifyID + ".lrc")
        )
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("text/plain, application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("SpotifyLyrics/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled else { return .failed(.cancelled) }
            guard let response = response as? HTTPURLResponse else {
                return .failed(.parseFailure)
            }

            if response.statusCode == 404 {
                store(.noMatch, for: spotifyID)
                return .noMatch
            }
            guard (200..<300).contains(response.statusCode) else {
                return .failed(.serverError(response.statusCode))
            }
            guard let content = String(data: data, encoding: .utf8),
                  let parsed = LRCParser.parse(content, identity: identity, source: .amll),
                  !parsed.lines.isEmpty else {
                return .failed(.parseFailure)
            }

            let document = LyricsDocument(
                identity: identity,
                title: parsed.title ?? track.title,
                artist: parsed.artist ?? track.artist,
                album: parsed.album ?? track.album,
                duration: parsed.duration ?? track.duration,
                lines: parsed.lines,
                isSynchronized: parsed.isSynchronized,
                source: .amll,
                confidence: 1,
                providerSourceID: "amll:\(spotifyID)",
                spotifyTrackID: spotifyID
            )
            store(.match(document), for: spotifyID)
            return .match(document)
        } catch is CancellationError {
            return .failed(.cancelled)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                return .failed(.timedOut)
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed:
                return .failed(.networkUnavailable)
            case .cancelled:
                return .failed(.cancelled)
            default:
                return .failed(.unknown(error.localizedDescription))
            }
        } catch {
            return .failed(.unknown(error.localizedDescription))
        }
    }

    private func cachedResult(for spotifyID: String) -> LyricsLookupResult? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        switch cache[spotifyID] {
        case .match(let document): return .match(document)
        case .noMatch: return .noMatch
        case nil: return nil
        }
    }

    private func store(_ entry: CacheEntry, for spotifyID: String) {
        cacheLock.lock()
        cache[spotifyID] = entry
        if cache.count > 256, let firstKey = cache.keys.first {
            cache.removeValue(forKey: firstKey)
        }
        cacheLock.unlock()
    }

    /// Spotify IDs are base62 and case-sensitive. TrackIdentity currently
    /// normalizes IDs for comparison, so the request path must prefer the
    /// original Track representation and preserve its case.
    private static func casePreservingSpotifyTrackID(
        from track: Track,
        fallback identity: TrackIdentity
    ) -> String? {
        if let id = parseCasePreservingSpotifyID(track.spotifyId) { return id }
        if let id = parseCasePreservingSpotifyID(track.spotifyURL?.absoluteString) { return id }
        return identity.spotifyTrackID
    }

    private static func parseCasePreservingSpotifyID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("spotify:track:") {
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }
            return validBareID(String(parts[2]))
        }
        if let url = URL(string: trimmed),
           url.host?.lowercased() == "open.spotify.com" {
            let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            guard parts.count == 2, parts[0].lowercased() == "track" else { return nil }
            return validBareID(String(parts[1]))
        }
        return validBareID(trimmed)
    }

    private static func validBareID(_ value: String) -> String? {
        guard (1...64).contains(value.utf8.count),
              value.unicodeScalars.allSatisfy({
                  (0x30...0x39).contains($0.value)
                      || (0x41...0x5A).contains($0.value)
                      || (0x61...0x7A).contains($0.value)
              }) else { return nil }
        return value
    }
}
