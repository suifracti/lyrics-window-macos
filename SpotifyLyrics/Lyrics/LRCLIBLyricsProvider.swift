import Foundation

public protocol LRCLIBSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: LRCLIBSession {}

public final class LRCLIBLyricsProvider: LyricsProvider {
    public let name = "LRCLIB"

    private let session: LRCLIBSession
    private let baseURL: URL

    public init(
        session: LRCLIBSession = URLSession.shared,
        baseURL: URL? = nil
    ) {
        self.session = session
        self.baseURL = baseURL ?? Self.defaultBaseURL
    }

    public func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult {
        do {
            let direct = try await fetchRecords(path: "get", track: track)
            if let result = classify(records: direct, track: track, identity: identity) {
                return result
            }

            let search = try await fetchRecords(path: "search", track: track)
            return classify(records: search, track: track, identity: identity) ?? .noLyrics
        } catch let error as LRCLIBError {
            if case .notFound = error {
                do {
                    let search = try await fetchRecords(path: "search", track: track)
                    return classify(records: search, track: track, identity: identity) ?? .noLyrics
                } catch let nested as LRCLIBError {
                    if case .notFound = nested {
                        return .noMatch
                    }
                    return .failed(Self.failure(for: nested))
                } catch {
                    return .failed(Self.failure(for: error))
                }
            }
            return .failed(Self.failure(for: error))
        } catch {
            return .failed(Self.failure(for: error))
        }
    }

    private func fetchRecords(path: String, track: Track) async throws -> [LRCLIBRecord] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.duration.rounded())))
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SpotifyLyrics/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LRCLIBError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                throw LRCLIBError.notFound
            }
            throw LRCLIBError.httpStatus(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        do {
            if path == "search" {
                return try decoder.decode([LRCLIBRecord].self, from: data)
            }
            return [try decoder.decode(LRCLIBRecord.self, from: data)]
        } catch {
            throw LRCLIBError.parseFailure
        }
    }

    private func classify(
        records: [LRCLIBRecord],
        track: Track,
        identity: TrackIdentity
    ) -> LyricsLookupResult? {
        var candidates: [LyricsCandidate] = []

        for (index, record) in records.enumerated() {
            guard let parsed = parseLyrics(from: record), !parsed.lines.isEmpty else { continue }
            let candidate = LyricsCandidate(
                id: String(record.id ?? index),
                identity: identity,
                title: record.trackName ?? "",
                artist: record.artistName ?? "",
                album: record.albumName ?? "",
                duration: record.duration ?? track.duration,
                lines: parsed.lines,
                isSynchronized: parsed.isSynchronized,
                source: .lrclib,
                confidence: 0
            )
            let score = LyricsMatcher.score(track: track, candidate: candidate)
            candidates.append(
                LyricsCandidate(
                    id: candidate.id,
                    identity: candidate.identity,
                    title: candidate.title,
                    artist: candidate.artist,
                    album: candidate.album,
                    duration: candidate.duration,
                    lines: candidate.lines,
                    isSynchronized: candidate.isSynchronized,
                    source: candidate.source,
                    confidence: score
                )
            )
        }

        let sorted = candidates
            .filter { LyricsMatcher.isCandidate($0.confidence) }
            .sorted { $0.confidence > $1.confidence }
        guard let best = sorted.first else {
            return records.isEmpty ? .noMatch : .noLyrics
        }

        if LyricsMatcher.isHighConfidence(best.confidence),
           sorted.dropFirst().first.map({ best.confidence - $0.confidence >= 0.05 }) ?? true {
            return .match(
                LyricsDocument(
                    identity: identity,
                    title: best.title,
                    artist: best.artist,
                    album: best.album,
                    duration: best.duration,
                    lines: best.lines,
                    isSynchronized: best.isSynchronized,
                    source: .lrclib,
                    confidence: best.confidence
                )
            )
        }
        return .candidates(sorted)
    }

    private func parseLyrics(from record: LRCLIBRecord) -> ParsedLyrics? {
        if let syncedLyrics = record.syncedLyrics,
           let document = LRCParser.parse(
               syncedLyrics,
               identity: TrackIdentity(title: record.trackName ?? "", artist: record.artistName ?? "", album: record.albumName ?? "", duration: record.duration ?? 0),
               source: .lrclib
           ) {
            return ParsedLyrics(lines: document.lines, isSynchronized: true)
        }

        guard let plainLyrics = record.plainLyrics else { return nil }
        let lines = plainLyrics
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { LyricLine(timestamp: 0, originalText: $0) }
        return lines.isEmpty ? nil : ParsedLyrics(lines: lines, isSynchronized: false)
    }

    private static func failure(for error: LRCLIBError) -> LyricsFailure {
        switch error {
        case .notFound:
            return .unknown("LRCLIB 没有匹配结果")
        case .httpStatus(let status):
            return .serverError(status)
        case .invalidResponse:
            return .parseFailure
        case .parseFailure:
            return .parseFailure
        }
    }

    private static func failure(for error: Error) -> LyricsFailure {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed:
                return .networkUnavailable
            case .timedOut:
                return .timedOut
            default:
                break
            }
        }
        return .unknown(error.localizedDescription)
    }

    private static var defaultBaseURL: URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["SPOTIFYLYRICS_LRCLIB_BASE_URL"],
           let url = URL(string: override),
           url.scheme != nil,
           url.host != nil {
            return url
        }
        #endif
        return URL(string: "https://lrclib.net/api")!
    }
}

private enum LRCLIBError: Error {
    case notFound
    case httpStatus(Int)
    case invalidResponse
    case parseFailure
}

private struct LRCLIBRecord: Decodable {
    let id: Int?
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: TimeInterval?
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?
}

private struct ParsedLyrics {
    let lines: [LyricLine]
    let isSynchronized: Bool
}
