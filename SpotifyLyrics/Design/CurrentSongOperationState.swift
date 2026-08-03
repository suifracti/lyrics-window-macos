import Foundation

/// A small value projection for the current-song popover.  It keeps the
/// presentation vocabulary independent from PlaybackState while the actual
/// commands remain on the shared PlaybackState instance.
public enum CurrentSongPrimaryAction: String, Sendable {
    case none
    case edit
    case chooseVersion
    case importOrCreate
}

public enum CurrentSongLyricsState: String, Equatable, Sendable {
    case idle
    case loading
    case synchronized
    case plainText
    case alignmentPreview
    case noLyrics
    case noSelection
    case noMatch
    case candidates
    case failed
    case mockPreview

    public init(loadState: LyricsLoadState) {
        switch loadState {
        case .idle: self = .idle
        case .loading: self = .loading
        case .loaded: self = .synchronized
        case .alignmentQueued, .alignmentRunning: self = .plainText
        case .alignmentPreview: self = .alignmentPreview
        case .noLyrics: self = .noLyrics
        case .noSelection: self = .noSelection
        case .noMatch: self = .noMatch
        case .candidates: self = .candidates
        case .failed: self = .failed
        case .mockPreview: self = .mockPreview
        }
    }
}

public struct CurrentSongOperationSnapshot: Equatable {
    public let title: String
    public let artist: String
    public let lyricsState: CurrentSongLyricsState
    public let lyricsSource: LyricsSource?
    public let lyricsVersionID: UUID?
    public let isSynchronized: Bool
    public let isLyricsNoSelection: Bool
    public let hasTranslationSelection: Bool
    public let translationVersionCount: Int

    public init(
        title: String,
        artist: String,
        lyricsState: CurrentSongLyricsState,
        lyricsSource: LyricsSource?,
        lyricsVersionID: UUID?,
        isSynchronized: Bool,
        isLyricsNoSelection: Bool,
        hasTranslationSelection: Bool,
        translationVersionCount: Int
    ) {
        self.title = title
        self.artist = artist
        self.lyricsState = lyricsState
        self.lyricsSource = lyricsSource
        self.lyricsVersionID = lyricsVersionID
        self.isSynchronized = isSynchronized
        self.isLyricsNoSelection = isLyricsNoSelection
        self.hasTranslationSelection = hasTranslationSelection
        self.translationVersionCount = max(0, translationVersionCount)
    }

    public var lyricsStatusLabel: String {
        if isLyricsNoSelection || isNoSelectionState { return "本次播放不使用" }
        switch lyricsState {
        case .idle: return "等待歌曲"
        case .loading: return "正在搜索歌词"
        case .synchronized: return isSynchronized ? "已加载 · 同步歌词" : "已加载 · 纯文本"
        case .plainText: return "已加载 · 未排轴"
        case .alignmentPreview: return "排轴预览"
        case .noLyrics, .noSelection, .noMatch: return "暂无歌词"
        case .candidates: return "待选择候选"
        case .failed: return "歌词加载失败"
        case .mockPreview: return "预览"
        }
    }

    public var lyricsSourceLabel: String {
        lyricsSource?.displayName ?? "暂无来源"
    }

    public var translationStatusLabel: String {
        hasTranslationSelection ? "已选择翻译" : "无翻译版本"
    }

    public var primaryLyricsAction: CurrentSongPrimaryAction {
        if isLyricsNoSelection || isNoSelectionState { return .chooseVersion }
        switch lyricsState {
        case .synchronized, .plainText, .alignmentPreview:
            return lyricsVersionID == nil ? .importOrCreate : .edit
        case .noSelection, .candidates:
            return .chooseVersion
        case .noLyrics, .noMatch, .failed:
            return .importOrCreate
        case .idle, .loading, .mockPreview:
            return .none
        }
    }

    private var isNoSelectionState: Bool {
        lyricsState == .noSelection
    }
}
