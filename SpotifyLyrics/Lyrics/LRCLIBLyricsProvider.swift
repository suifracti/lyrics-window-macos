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
        baseURL: URL = URL(string: "https://lrclib.net/api")!
    ) {
        self.session = session
        self.baseURL = baseURL
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
                    return .failed(Self.userFacingMessage(for: nested))
                } catch {
                    return .failed(error.localizedDescription)
                }
            }
            return .failed(Self.userFacingMessage(for: error))
        } catch {
            return .failed(error.localizedDescription)
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
        if path == "search" {
            return try decoder.decode([LRCLIBRecord].self, from: data)
        }
        return [try decoder.decode(LRCLIBRecord.self, from: data)]
    }

    private func classify(
        records: [LRCLIBRecord],
        track: Track,
        identity: TrackIdentity
    ) -> LyricsLookupResult? {
        var candidates: [LyricsCandidate] = []

        for (index, record) in records.enumerated() {
            guard let lines = parseLines(from: record), !lines.isEmpty else { continue }
            let candidate = LyricsCandidate(
                id: String(record.id ?? index),
                identity: identity,
                title: record.trackName ?? "",
                artist: record.artistName ?? "",
                album: record.albumName ?? "",
                duration: record.duration ?? track.duration,
                lines: lines,
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
                    source: .lrclib,
                    confidence: best.confidence
                )
            )
        }
        return .candidates(sorted)
    }

    private func parseLines(from record: LRCLIBRecord) -> [LyricLine]? {
        if let syncedLyrics = record.syncedLyrics,
           let document = LRCParser.parse(
               syncedLyrics,
               identity: TrackIdentity(title: record.trackName ?? "", artist: record.artistName ?? "", album: record.albumName ?? "", duration: record.duration ?? 0),
               source: .lrclib
           ) {
            return document.lines
        }

        guard let plainLyrics = record.plainLyrics else { return nil }
        let lines = plainLyrics
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { LyricLine(timestamp: 0, originalText: $0) }
        return lines.isEmpty ? nil : lines
    }

    private static func userFacingMessage(for error: LRCLIBError) -> String {
        switch error {
        case .notFound:
            return "LRCLIB 没有匹配结果"
        case .httpStatus(let status):
            return "LRCLIB 返回 HTTP \(status)"
        case .invalidResponse:
            return "LRCLIB 返回格式无法识别"
        }
    }
}

private enum LRCLIBError: Error {
    case notFound
    case httpStatus(Int)
    case invalidResponse
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
