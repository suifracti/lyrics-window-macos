import Foundation

public protocol LRCLIBSearchSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: LRCLIBSearchSession {}

public final class LRCLIBProvider: SongSearchProvider {
    public let name = "LRCLIB"

    private let session: LRCLIBSearchSession
    private let baseURL: URL

    public init(
        session: LRCLIBSearchSession = URLSession.shared,
        baseURL: URL? = nil
    ) {
        self.session = session
        self.baseURL = baseURL ?? Self.defaultBaseURL
    }

    public func search(query: SongSearchQuery) async throws -> [SongSearchResult] {
        guard !query.isEmpty else { return [] }
        var components = URLComponents(
            url: baseURL.appendingPathComponent("search"),
            resolvingAgainstBaseURL: false
        )!
        var items = [URLQueryItem(name: "q", value: query.text)]
        if let title = query.title, !title.isEmpty { items.append(URLQueryItem(name: "track_name", value: title)) }
        if let artist = query.artist, !artist.isEmpty { items.append(URLQueryItem(name: "artist_name", value: artist)) }
        if let album = query.album, !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if let duration = query.duration, duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SpotifyLyrics/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw SongSearchError.parseFailure }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw SongSearchError.serverError(httpResponse.statusCode)
            }

            let records: [LRCLIBSearchRecord]
            do {
                records = try JSONDecoder().decode([LRCLIBSearchRecord].self, from: data)
            } catch {
                throw SongSearchError.parseFailure
            }

            return records.compactMap { record in
                makeResult(record: record, query: query)
            }
            .sorted {
                if $0.confidence == $1.confidence { return $0.track.title < $1.track.title }
                return $0.confidence > $1.confidence
            }
        } catch let error as SongSearchError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    private func makeResult(record: LRCLIBSearchRecord, query: SongSearchQuery) -> SongSearchResult? {
        let title = record.trackName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = record.artistName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        let album = record.albumName ?? ""
        let duration = record.duration ?? query.duration ?? 0
        let track = Track(
            id: "lrclib:\(record.id.map(String.init) ?? UUID().uuidString)",
            title: title,
            artist: artist,
            album: album,
            duration: duration
        )
        let score = SongSearchScoring.score(track: track, query: query)
        guard score >= 0.20 else { return nil }

        let identity = TrackIdentity(track: track)
        let lyrics: LyricsDocument?
        if let syncedLyrics = record.syncedLyrics,
           let parsed = LRCParser.parse(syncedLyrics, identity: identity, source: .lrclib) {
            lyrics = parsed
        } else if let plainLyrics = record.plainLyrics {
            let lines = plainLyrics
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { LyricLine(timestamp: 0, originalText: $0) }
            lyrics = lines.isEmpty ? nil : LyricsDocument(
                identity: identity,
                title: title,
                artist: artist,
                album: album,
                duration: duration,
                lines: lines,
                isSynchronized: false,
                source: .lrclib,
                confidence: score
            )
        } else {
            lyrics = nil
        }

        return SongSearchResult(
            id: "lrclib:\(record.id.map(String.init) ?? identity.metadataFingerprint)",
            source: .lrclib,
            track: track,
            confidence: score,
            lyrics: lyrics
        )
    }

    private static func map(_ error: Error) -> SongSearchError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed:
                return .networkUnavailable
            case .timedOut:
                return .timedOut
            default: break
            }
        }
        return .unknown(error.localizedDescription)
    }

    private static var defaultBaseURL: URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["SPOTIFYLYRICS_LRCLIB_BASE_URL"],
           let url = URL(string: override), url.scheme != nil, url.host != nil {
            return url
        }
        #endif
        return URL(string: "https://lrclib.net/api")!
    }
}

private struct LRCLIBSearchRecord: Decodable {
    let id: Int?
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: TimeInterval?
    let plainLyrics: String?
    let syncedLyrics: String?
}
