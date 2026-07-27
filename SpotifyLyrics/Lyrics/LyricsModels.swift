import Foundation

public enum LyricsSource: String, CaseIterable, Codable, Sendable {
    case local
    case lrclib
    case mock

    public var displayName: String {
        switch self {
        case .local: return "本地 LRC"
        case .lrclib: return "LRCLIB"
        case .mock: return "Mock Preview"
        }
    }
}

public struct LyricsDocument: Equatable {
    public let identity: TrackIdentity
    public let title: String?
    public let artist: String?
    public let album: String?
    public let lines: [LyricLine]
    public let source: LyricsSource
    public let confidence: Double

    public init(
        identity: TrackIdentity,
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        lines: [LyricLine],
        source: LyricsSource,
        confidence: Double = 1
    ) {
        self.identity = identity
        self.title = title
        self.artist = artist
        self.album = album
        self.lines = lines
        self.source = source
        self.confidence = confidence
    }
}

public struct LyricsCandidate: Identifiable, Equatable {
    public let id: String
    public let identity: TrackIdentity
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval
    public let lines: [LyricLine]
    public let source: LyricsSource
    public let confidence: Double

    public init(
        id: String,
        identity: TrackIdentity,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        lines: [LyricLine],
        source: LyricsSource,
        confidence: Double
    ) {
        self.id = id
        self.identity = identity
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.lines = lines
        self.source = source
        self.confidence = confidence
    }
}

public enum LyricsLookupResult {
    case match(LyricsDocument)
    case candidates([LyricsCandidate])
    case noLyrics
    case noMatch
    case failed(String)
}

public protocol LyricsProvider {
    var name: String { get }
    func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult
}

public enum LyricsLoadState: Equatable {
    case idle
    case loading(TrackIdentity)
    case loaded(LyricsDocument)
    case noLyrics(TrackIdentity)
    case candidates(TrackIdentity, [LyricsCandidate])
    case failed(TrackIdentity, String)
    case mockPreview

    public var identity: TrackIdentity? {
        switch self {
        case .idle, .mockPreview:
            return nil
        case .loading(let identity), .noLyrics(let identity), .failed(let identity, _):
            return identity
        case .loaded(let document):
            return document.identity
        case .candidates(let identity, _):
            return identity
        }
    }

    public var lines: [LyricLine] {
        switch self {
        case .loaded(let document):
            return document.lines
        case .mockPreview:
            return []
        default:
            return []
        }
    }

    public var userFacingMessage: String {
        switch self {
        case .idle:
            return "等待 Spotify 歌曲"
        case .loading:
            return "正在搜索歌词…"
        case .loaded:
            return ""
        case .noLyrics:
            return "暂未找到歌词"
        case .candidates:
            return "请选择匹配的歌词"
        case .failed(_, let message):
            return "歌词搜索失败：\(message)"
        case .mockPreview:
            return "Mock Preview"
        }
    }

    public var isShowingRows: Bool {
        switch self {
        case .loaded, .mockPreview:
            return !lines.isEmpty
        default:
            return false
        }
    }
}
