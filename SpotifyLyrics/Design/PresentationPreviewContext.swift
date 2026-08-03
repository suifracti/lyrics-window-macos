import Foundation

public enum PresentationPreviewSource: String, CaseIterable, Sendable {
    case live
    case mock
}

public enum PresentationPreviewLyricsState: String, CaseIterable, Sendable {
    case idle
    case loading
    case synchronized
    case plainText
    case noLyrics
    case noSelection
    case noMatch
    case candidates
    case failed
    case preview

    public init(loadState: LyricsLoadState) {
        switch loadState {
        case .idle: self = .idle
        case .loading: self = .loading
        case .loaded: self = .synchronized
        case .alignmentQueued, .alignmentRunning: self = .plainText
        case .alignmentPreview: self = .preview
        case .noLyrics: self = .noLyrics
        case .noSelection: self = .noSelection
        case .noMatch: self = .noMatch
        case .candidates: self = .candidates
        case .failed: self = .failed
        case .mockPreview: self = .preview
        }
    }

    public var displayName: String {
        switch self {
        case .idle: return "等待歌曲"
        case .loading: return "正在加载"
        case .synchronized: return "同步歌词"
        case .plainText: return "纯文本 / 未排轴"
        case .noLyrics: return "暂无歌词"
        case .noSelection: return "未选择歌词"
        case .noMatch: return "无匹配"
        case .candidates: return "待选择候选"
        case .failed: return "加载失败"
        case .preview: return "预览"
        }
    }
}

public struct PresentationPreviewSize: Equatable, Hashable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = max(1, width)
        self.height = max(1, height)
    }
}

/// An immutable, value-only snapshot for a presentation preview.  It is
/// deliberately not an ObservableObject and has no commands, so a preview
/// cannot seek, switch tracks, write settings, or mutate a live session.
public struct PresentationPreviewContext: Equatable, Sendable {
    public let source: PresentationPreviewSource
    public let trackIdentity: TrackIdentity?
    public let track: Track
    public let currentTime: TimeInterval
    public let duration: TimeInterval
    public let isPlaying: Bool
    public let lyricsState: PresentationPreviewLyricsState
    public let lyricsAreSynchronized: Bool
    public let lyrics: [LyricLine]
    public let contextLineIndices: [Int]
    public let currentLineIndex: Int?
    public let showOriginal: Bool
    public let showTranslation: Bool
    public let showRomaji: Bool
    public let kanaDisplayMode: KanaDisplayMode
    public let hasTranslationSelection: Bool
    public let reduceMotion: Bool
    public let reduceTransparency: Bool
    public let increaseContrast: Bool
    public let windowSize: PresentationPreviewSize
    public let surface: PresentationSurface

    public init(
        source: PresentationPreviewSource,
        trackIdentity: TrackIdentity?,
        track: Track,
        currentTime: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool,
        lyricsState: PresentationPreviewLyricsState,
        lyricsAreSynchronized: Bool,
        lyrics: [LyricLine],
        contextLineIndices: [Int],
        currentLineIndex: Int?,
        showOriginal: Bool,
        showTranslation: Bool,
        showRomaji: Bool,
        kanaDisplayMode: KanaDisplayMode,
        hasTranslationSelection: Bool,
        reduceMotion: Bool,
        reduceTransparency: Bool,
        increaseContrast: Bool,
        windowSize: PresentationPreviewSize,
        surface: PresentationSurface
    ) {
        self.source = source
        self.trackIdentity = trackIdentity
        self.track = track
        self.currentTime = max(0, currentTime)
        self.duration = max(0, duration)
        self.isPlaying = isPlaying
        self.lyricsState = lyricsState
        self.lyricsAreSynchronized = lyricsAreSynchronized
        self.lyrics = lyrics
        self.contextLineIndices = contextLineIndices.filter { lyrics.indices.contains($0) }
        self.currentLineIndex = currentLineIndex.flatMap { lyrics.indices.contains($0) ? $0 : nil }
        self.showOriginal = showOriginal
        self.showTranslation = showTranslation
        self.showRomaji = showRomaji
        self.kanaDisplayMode = kanaDisplayMode
        self.hasTranslationSelection = hasTranslationSelection
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
        self.windowSize = windowSize
        self.surface = surface
    }

    /// Stable enough for an A/B preview comparison.  It intentionally uses
    /// track/artwork and the immutable source marker, never playback time.
    public var snapshotKey: String {
        let identity = trackIdentity?.stableKey ?? "no-track"
        let artwork = track.artworkURL?.absoluteString ?? track.artworkName
        return "\(source.rawValue)|\(identity)|\(artwork)|\(surface.rawValue)"
    }

    public static func mock(
        surface: PresentationSurface = .preview,
        windowSize: PresentationPreviewSize = PresentationPreviewSize(width: 960, height: 640),
        reduceMotion: Bool = false,
        reduceTransparency: Bool = false,
        increaseContrast: Bool = false
    ) -> PresentationPreviewContext {
        let track = Track(
            id: "presentation-preview-track",
            title: "水曜日の約束",
            artist: "Kawasaki.Rio",
            album: "Preview Snapshot",
            duration: 171.2,
            artworkName: "music.note"
        )
        let identity = TrackIdentity(track: track)
        let lines = [
            LyricLine(timestamp: 12, originalText: "夜の窓に雨が落ちる", translationText: "雨落在夜晚的窗边", romajiText: "yoru no mado ni ame ga ochiru", kanaText: "よるのまどにあめがおちる"),
            LyricLine(timestamp: 28, originalText: "遠い街の灯りを見ている", translationText: "望着远方城市的灯火", romajiText: "tooi machi no akari o mite iru", kanaText: "とおいまちのあかりをみている"),
            LyricLine(timestamp: 46, originalText: "名前のない風が通り過ぎる", translationText: "无名的风从身旁经过", romajiText: "namae no nai kaze ga toorisugiru", kanaText: "なまえのないかぜがとおりすぎる"),
            LyricLine(timestamp: 64, originalText: "まだ知らない朝を待っている", translationText: "等待尚未知晓的清晨", romajiText: "mada shiranai asa o matte iru", kanaText: "まだしらないあさをまっている")
        ]
        return PresentationPreviewContext(
            source: .mock,
            trackIdentity: identity,
            track: track,
            currentTime: 36,
            duration: track.duration,
            isPlaying: true,
            lyricsState: .synchronized,
            lyricsAreSynchronized: true,
            lyrics: lines,
            contextLineIndices: [0, 1, 2],
            currentLineIndex: 1,
            showOriginal: true,
            showTranslation: true,
            showRomaji: true,
            kanaDisplayMode: .inlineRuby,
            hasTranslationSelection: true,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            increaseContrast: increaseContrast,
            windowSize: windowSize,
            surface: surface
        )
    }
}
