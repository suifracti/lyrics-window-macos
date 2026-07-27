import Foundation

public struct SongSearchQuery: Equatable, Hashable {
    public let text: String
    public let title: String?
    public let artist: String?
    public let album: String?
    public let duration: TimeInterval?

    public init(
        text: String = "",
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval? = nil
    ) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.artist = artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.album = album?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.duration = duration
    }

    public init(track: Track) {
        self.init(
            text: "\(track.title) \(track.artist)",
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration
        )
    }

    public var normalizedText: String {
        Self.normalizeSearchText(text)
    }

    public var tokens: [String] {
        normalizedText.split(separator: " ").map(String.init)
    }

    public var isEmpty: Bool {
        normalizedText.isEmpty && [title, artist, album].compactMap { $0 }.allSatisfy {
            Self.normalizeSearchText($0).isEmpty
        }
    }

    public static func normalizeSearchText(_ value: String) -> String {
        value
            .precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split { $0.isWhitespace || $0.isNewline }
            .joined(separator: " ")
            .lowercased()
    }
}

public enum SongSearchSource: String, CaseIterable, Identifiable {
    case local
    case spotifyCurrentTrack
    case lrclib

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .local: return "本地歌词"
        case .spotifyCurrentTrack: return "Spotify 当前歌曲"
        case .lrclib: return "LRCLIB"
        }
    }
}

public struct SongSearchResult: Identifiable, Equatable {
    public let id: String
    public let source: SongSearchSource
    public let track: Track
    public let confidence: Double
    public let lyrics: LyricsDocument?

    public init(
        id: String,
        source: SongSearchSource,
        track: Track,
        confidence: Double,
        lyrics: LyricsDocument? = nil
    ) {
        self.id = id
        self.source = source
        self.track = track
        self.confidence = confidence
        self.lyrics = lyrics
    }

    public var metadataKey: String {
        TrackIdentity.metadataFingerprint(
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration
        )
    }

    /// Search-result de-duplication intentionally ignores album and duration:
    /// public lyric indexes often publish the same recording under slightly
    /// different release metadata or duration rounding.
    public var searchMergeKey: String {
        [
            SongSearchQuery.normalizeSearchText(track.title),
            SongSearchQuery.normalizeSearchText(track.artist)
        ].joined(separator: "|")
    }
}

public enum SongSearchState: Equatable {
    case idle
    case searching(SongSearchQuery)
    case results(SongSearchQuery, [SongSearchResult])
    case noResults(SongSearchQuery)
    case failed(SongSearchQuery, String)

    public var query: SongSearchQuery? {
        switch self {
        case .idle: return nil
        case .searching(let query), .results(let query, _), .noResults(let query), .failed(let query, _):
            return query
        }
    }
}

public enum SongSearchError: LocalizedError, Equatable {
    case networkUnavailable
    case timedOut
    case serverError(Int)
    case parseFailure
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .networkUnavailable: return "网络不可用"
        case .timedOut: return "搜索请求超时"
        case .serverError(let code): return "搜索服务错误（HTTP \(code)）"
        case .parseFailure: return "搜索结果解析失败"
        case .unknown(let message): return message.isEmpty ? "未知搜索错误" : message
        }
    }
}

enum SongSearchScoring {
    static func score(track: Track, query: SongSearchQuery) -> Double {
        let titleScore = fieldScore(track.title, explicit: query.title, query: query)
        let artistScore = fieldScore(track.artist, explicit: query.artist, query: query)
        let albumScore = fieldScore(track.album, explicit: query.album, query: query)

        let metadataScore = (titleScore * 0.52) + (artistScore * 0.28) + (albumScore * 0.10)
        let durationScore: Double
        if let duration = query.duration, duration > 0, track.duration > 0 {
            let delta = abs(duration - track.duration)
            durationScore = delta < 2 ? 1 : delta < 6 ? 0.65 : delta < 12 ? 0.25 : 0
        } else {
            durationScore = 0
        }

        if query.title == nil, query.artist == nil, query.album == nil {
            let tokens = query.tokens
            guard !tokens.isEmpty else { return 1 }
            let haystack = SongSearchQuery.normalizeSearchText("\(track.title) \(track.artist) \(track.album)")
            let matched = tokens.filter { haystack.contains($0) }.count
            return Double(matched) / Double(tokens.count)
        }

        return min(1, metadataScore + (durationScore * 0.10))
    }

    private static func fieldScore(_ value: String, explicit: String?, query: SongSearchQuery) -> Double {
        let normalizedValue = SongSearchQuery.normalizeSearchText(value)
        if let explicit, !explicit.isEmpty {
            let normalizedExplicit = SongSearchQuery.normalizeSearchText(explicit)
            if normalizedValue == normalizedExplicit { return 1 }
            if normalizedValue.contains(normalizedExplicit) || normalizedExplicit.contains(normalizedValue) { return 0.72 }
        }
        let tokens = query.tokens
        guard !tokens.isEmpty else { return 0 }
        let matched = tokens.filter { normalizedValue.contains($0) }.count
        return min(1, Double(matched) / Double(tokens.count))
    }
}
