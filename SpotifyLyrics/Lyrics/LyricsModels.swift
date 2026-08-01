import Foundation

public enum LyricsSource: String, CaseIterable, Codable, Sendable {
    case local
    case lrclib
    case neteaseExperimental
    case qqExperimental
    case asrMachineGenerated
    case automaticAlignment
    case manualImport
    case manualCreate
    case manualEdit
    case mock

    public var displayName: String {
        switch self {
        case .local: return "本地 LRC"
        case .lrclib: return "LRCLIB"
        case .neteaseExperimental: return "网易云（实验）"
        case .qqExperimental: return "QQ音乐（实验）"
        case .asrMachineGenerated: return "ASR 草稿（待校正）"
        case .automaticAlignment: return "自动排轴"
        case .manualImport: return "手动导入"
        case .manualCreate: return "创建歌词"
        case .manualEdit: return "人工编辑"
        case .mock: return "Mock Preview"
        }
    }
}

public struct LyricsDocument: Equatable, Sendable {
    public let identity: TrackIdentity
    public let title: String?
    public let artist: String?
    public let album: String?
    public let duration: TimeInterval?
    public let lines: [LyricLine]
    public let isSynchronized: Bool
    public let source: LyricsSource
    public let confidence: Double
    /// Provider record identifier used for persistence de-duplication. It is
    /// optional to keep existing Provider/fixture initializers source-compatible.
    public let providerSourceID: String?
    /// Independent provider evidence. This is nil unless a Provider actually
    /// verified the identifier; the request TrackIdentity is not evidence.
    public let spotifyTrackID: String?
    public let isrc: String?

    public init(
        identity: TrackIdentity,
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval? = nil,
        lines: [LyricLine],
        isSynchronized: Bool = true,
        source: LyricsSource,
        confidence: Double = 1,
        providerSourceID: String? = nil,
        spotifyTrackID: String? = nil,
        isrc: String? = nil
    ) {
        self.identity = identity
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.lines = lines
        self.isSynchronized = isSynchronized
        self.source = source
        self.confidence = confidence
        self.providerSourceID = providerSourceID
        self.spotifyTrackID = spotifyTrackID
        self.isrc = isrc
    }
}

public struct LyricsCandidate: Identifiable, Equatable, Sendable {
    public let id: String
    public let identity: TrackIdentity
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval
    public let lines: [LyricLine]
    public let isSynchronized: Bool
    public let source: LyricsSource
    public let confidence: Double
    public let providerSourceID: String?
    /// These are optional independent identity claims from a Provider. They
    /// must never be populated from the caller's identity just to increase a
    /// match score.
    public let spotifyTrackID: String?
    public let isrc: String?

    public init(
        id: String,
        identity: TrackIdentity,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        lines: [LyricLine],
        isSynchronized: Bool = true,
        source: LyricsSource,
        confidence: Double,
        providerSourceID: String? = nil,
        spotifyTrackID: String? = nil,
        isrc: String? = nil
    ) {
        self.id = id
        self.identity = identity
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.lines = lines
        self.isSynchronized = isSynchronized
        self.source = source
        self.confidence = confidence
        self.providerSourceID = providerSourceID
        self.spotifyTrackID = spotifyTrackID
        self.isrc = isrc
    }
}

public enum LyricsFailure: Error, Equatable, Sendable {
    case networkUnavailable
    case timedOut
    case rateLimited(TimeInterval?)
    case serverError(Int)
    case parseFailure
    case cancelled
    case unknown(String)

    public var userFacingMessage: String {
        switch self {
        case .networkUnavailable:
            return "网络不可用"
        case .timedOut:
            return "歌词请求超时"
        case .rateLimited:
            return "歌词服务限流，请稍后重试"
        case .serverError(let statusCode):
            return "歌词服务错误（HTTP \(statusCode)）"
        case .parseFailure:
            return "歌词解析失败"
        case .cancelled:
            return "歌词请求已取消"
        case .unknown(let message):
            return message.isEmpty ? "未知歌词错误" : message
        }
    }
}

public enum LyricsLookupResult {
    case match(LyricsDocument)
    case candidates([LyricsCandidate])
    case noLyrics
    case noMatch
    case failed(LyricsFailure)
}

public protocol LyricsProvider: Sendable {
    var name: String { get }
    func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult
}

public enum LyricsLoadState: Equatable {
    case idle
    case loading(TrackIdentity)
    case loaded(LyricsDocument)
    /// Lyrics body available but without a trustworthy timeline (no fake sync).
    case alignmentQueued(TrackIdentity, LyricsDocument)
    /// Force-align in progress; keep plain document for identity.
    case alignmentRunning(TrackIdentity, LyricsDocument, Double)
    /// Preview timed result before user confirms (does not replace locked lyrics until confirm).
    case alignmentPreview(TrackIdentity, plain: LyricsDocument, timed: LyricsDocument, report: AlignmentReport)
    case noLyrics(TrackIdentity)
    case noMatch(TrackIdentity)
    case candidates(TrackIdentity, [LyricsCandidate])
    case failed(TrackIdentity, LyricsFailure)
    case mockPreview

    public var identity: TrackIdentity? {
        switch self {
        case .idle, .mockPreview:
            return nil
        case .loading(let identity), .noLyrics(let identity), .noMatch(let identity), .failed(let identity, _):
            return identity
        case .loaded(let document), .alignmentQueued(_, let document), .alignmentRunning(_, let document, _):
            return document.identity
        case .alignmentPreview(let identity, _, _, _):
            return identity
        case .candidates(let identity, _):
            return identity
        }
    }

    public var lines: [LyricLine] {
        switch self {
        case .loaded(let document), .alignmentQueued(_, let document), .alignmentRunning(_, let document, _):
            return document.lines
        case .alignmentPreview(_, _, let timed, _):
            return timed.lines
        case .mockPreview:
            return []
        default:
            return []
        }
    }

    public var document: LyricsDocument? {
        switch self {
        case .loaded(let document), .alignmentQueued(_, let document), .alignmentRunning(_, let document, _):
            return document
        case .alignmentPreview(_, _, let timed, _):
            return timed
        default:
            return nil
        }
    }

    public var plainDocument: LyricsDocument? {
        switch self {
        case .alignmentQueued(_, let document), .alignmentRunning(_, let document, _):
            return document
        case .alignmentPreview(_, let plain, _, _):
            return plain
        case .loaded(let document):
            return document
        default:
            return nil
        }
    }

    public var alignmentProgressValue: Double? {
        if case .alignmentRunning(_, _, let p) = self { return p }
        return nil
    }

    public var alignmentReport: AlignmentReport? {
        if case .alignmentPreview(_, _, _, let report) = self { return report }
        return nil
    }

    public var needsAlignment: Bool {
        if case .alignmentQueued = self { return true }
        return false
    }

    public var userFacingMessage: String {
        switch self {
        case .idle:
            return "等待 Spotify 歌曲"
        case .loading:
            return "正在自动补全歌词…"
        case .loaded:
            return ""
        case .alignmentQueued:
            return "已获取歌词，待对齐时间轴"
        case .alignmentRunning:
            return "正在自动排轴…"
        case .alignmentPreview:
            return "排轴预览（未确认）"
        case .noLyrics:
            return "暂未找到歌词"
        case .noMatch:
            return "自动补全未找到可用歌词"
        case .candidates:
            return "请选择匹配的歌词"
        case .failed(_, let failure):
            return "歌词搜索失败：\(failure.userFacingMessage)"
        case .mockPreview:
            return "Mock Preview"
        }
    }

    public var isShowingRows: Bool {
        switch self {
        case .loaded, .alignmentQueued, .alignmentRunning, .alignmentPreview, .mockPreview:
            return !lines.isEmpty
        default:
            return false
        }
    }
}

public enum LyricsTimeline {
    /// Returns a seek position only for a synchronized row whose timestamp is
    /// finite and inside the current track. Plain-text rows intentionally
    /// return nil because their zero placeholder is not a real seek target.
    public static func validSeekTimestamp(
        for line: LyricLine,
        isSynchronized: Bool,
        duration: TimeInterval
    ) -> TimeInterval? {
        guard isSynchronized,
              duration.isFinite,
              duration > 0,
              line.timestamp.isFinite,
              line.timestamp >= 0,
              line.timestamp <= duration else {
            return nil
        }
        return line.timestamp
    }

    public static func activeLineIndex(
        lines: [LyricLine],
        time: TimeInterval,
        isSynchronized: Bool
    ) -> Int? {
        guard isSynchronized, !lines.isEmpty, time.isFinite else { return nil }

        // Lyrics are ordered by the persisted line index.  A binary search
        // keeps the high-frequency playback tick independent of document
        // length while preserving the existing "last timestamp <= time"
        // semantics, including repeated timestamps.
        var lower = 0
        var upper = lines.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if lines[middle].timestamp <= time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower == 0 ? nil : lower - 1
    }

    public static func presentationDistance(
        index: Int,
        currentIndex: Int?,
        isSynchronized: Bool
    ) -> Int {
        guard isSynchronized, let currentIndex else { return 0 }
        return abs(index - currentIndex)
    }
}
