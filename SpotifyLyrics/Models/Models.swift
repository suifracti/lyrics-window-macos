// Shared/Models/Models.swift
import Foundation

public struct Track: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval
    public let artworkName: String
    public let isrc: String?
    public let spotifyId: String?
    public let artworkURL: URL?
    public let spotifyURL: URL?
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        artworkName: String = "music.note",
        isrc: String? = nil,
        spotifyId: String? = nil,
        artworkURL: URL? = nil,
        spotifyURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkName = artworkName
        self.isrc = isrc
        self.spotifyId = spotifyId
        self.artworkURL = artworkURL
        self.spotifyURL = spotifyURL
    }
}

/// A reading/base pair for SwiftUI ruby rendering.
///
/// `surface` is always copied from the original lyric. `ruby` is optional and
/// is only populated when the reading pipeline has a confirmed reading for a
/// token containing Han characters. This keeps unknown readings fail-closed
/// while allowing long readings to overhang their base text naturally.
public struct LyricRubyToken: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: Int
    public let surface: String
    public let ruby: String?
    public let romaji: String?
    public let confidence: Double

    public init(
        id: Int,
        surface: String,
        ruby: String?,
        romaji: String? = nil,
        confidence: Double = 0
    ) {
        self.id = id
        self.surface = surface
        self.ruby = ruby
        self.romaji = romaji
        self.confidence = confidence
    }

    public var isWhitespace: Bool {
        !surface.isEmpty && surface.unicodeScalars.allSatisfy {
            CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }

    public var hasRuby: Bool {
        guard let ruby, !ruby.isEmpty, !isWhitespace else { return false }
        return true
    }
}

public struct LyricLine: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var timestamp: TimeInterval
    public var originalText: String
    public var translationText: String?
    public var romajiText: String?
    public var kanaText: String?
    public var rubyTokens: [LyricRubyToken]?
    
    public init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        originalText: String,
        translationText: String? = nil,
        romajiText: String? = nil,
        kanaText: String? = nil,
        rubyTokens: [LyricRubyToken]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.originalText = originalText
        self.translationText = translationText
        self.romajiText = romajiText
        self.kanaText = kanaText
        self.rubyTokens = rubyTokens
    }
}

public enum LyricsDisplayMode: String, CaseIterable, Identifiable {
    case mainWindow = "主窗口"
    case floatingWindow = "悬浮歌词"
    case capsulePlayer = "顶部胶囊"
    case fullScreen = "全屏歌词"
    
    public var id: String { rawValue }
}

/// Controls how the confirmed kana layer is presented in the main lyrics view.
///
/// `showKana` remains as a source-compatible computed property for older
/// callers. Setting that property preserves the previous independent-line
/// behavior rather than silently changing the presentation style.
public enum KanaDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case independentLine = "independentLine"
    case inlineRuby = "inlineRuby"
    case hidden = "hidden"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .independentLine: return "独立行"
        case .inlineRuby: return "悬浮注音"
        case .hidden: return "隐藏"
        }
    }

    public var detail: String {
        switch self {
        case .independentLine: return "整行显示假名，适合初学者对照阅读"
        case .inlineRuby: return "假名贴在对应汉字上方，保持正文连续"
        case .hidden: return "不显示假名层"
        }
    }
}

public struct DisplayPreferences: Equatable {
    public var showOriginal: Bool = true
    public var showTranslation: Bool = true
    public var showRomaji: Bool = true
    public var kanaDisplayMode: KanaDisplayMode
    public var fontSize: CGFloat = 18
    public var opacity: Double = 0.85
    public var alwaysOnTop: Bool = true

    /// Compatibility bridge for the previous Boolean setting.
    public var showKana: Bool {
        get { kanaDisplayMode != .hidden }
        set { kanaDisplayMode = newValue ? .independentLine : .hidden }
    }

    public init(
        showOriginal: Bool = true,
        showTranslation: Bool = true,
        showRomaji: Bool = true,
        showKana: Bool = false,
        kanaDisplayMode: KanaDisplayMode? = nil,
        fontSize: CGFloat = 18,
        opacity: Double = 0.85,
        alwaysOnTop: Bool = true
    ) {
        self.showOriginal = showOriginal
        self.showTranslation = showTranslation
        self.showRomaji = showRomaji
        self.kanaDisplayMode = kanaDisplayMode ?? (showKana ? .independentLine : .hidden)
        self.fontSize = fontSize
        self.opacity = opacity
        self.alwaysOnTop = alwaysOnTop
    }
}
