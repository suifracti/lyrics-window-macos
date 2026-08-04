// Shared/Models/Models.swift
import Foundation

public struct TrackArtistLink: Identifiable, Equatable, Hashable, Sendable {
    public let name: String
    public let url: URL?

    public var id: String { url?.absoluteString ?? "name:\(name)" }

    public init(name: String, url: URL? = nil) {
        self.name = name
        self.url = url
    }
}

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
    /// Structured identities are present for catalog results only. Desktop
    /// playback metadata may legitimately leave these empty.
    public let artistLinks: [TrackArtistLink]
    public let albumURL: URL?
    
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
        spotifyURL: URL? = nil,
        artistLinks: [TrackArtistLink] = [],
        albumURL: URL? = nil
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
        self.artistLinks = artistLinks
        self.albumURL = albumURL
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
    /// The confirmed kana text that replaces `surface` in the kana-primary
    /// presentation. This is separate from `ruby`: for a token such as
    /// `々`, there may be replacement kana without an annotation to show.
    public let kanaSurface: String?
    public let romaji: String?
    public let confidence: Double

    private enum CodingKeys: String, CodingKey {
        case id
        case surface
        case ruby
        case kanaSurface
        case romaji
        case confidence
    }

    public init(
        id: Int,
        surface: String,
        ruby: String?,
        kanaSurface: String? = nil,
        romaji: String? = nil,
        confidence: Double = 0
    ) {
        self.id = id
        self.surface = surface
        self.ruby = ruby
        self.kanaSurface = kanaSurface
        self.romaji = romaji
        self.confidence = confidence
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        surface = try values.decode(String.self, forKey: .surface)
        ruby = try values.decodeIfPresent(String.self, forKey: .ruby)
        // Older saved token payloads do not have this key.
        kanaSurface = try values.decodeIfPresent(String.self, forKey: .kanaSurface)
        romaji = try values.decodeIfPresent(String.self, forKey: .romaji)
        confidence = try values.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(surface, forKey: .surface)
        try values.encodeIfPresent(ruby, forKey: .ruby)
        try values.encodeIfPresent(kanaSurface, forKey: .kanaSurface)
        try values.encodeIfPresent(romaji, forKey: .romaji)
        try values.encode(confidence, forKey: .confidence)
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

    /// Kana-primary text for the third display mode. It never falls back to
    /// a guessed reading; callers only receive a ruby value when the reading
    /// pipeline confirmed one.
    public var kanaReplacementText: String {
        if let kanaSurface, !kanaSurface.isEmpty {
            return kanaSurface
        }
        if hasRuby, let ruby, !ruby.isEmpty {
            return ruby
        }
        return surface
    }
}

public struct LyricLine: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var timestamp: TimeInterval
    public var endTime: TimeInterval?
    public var originalText: String
    public var translationText: String?
    public var romajiText: String?
    public var kanaText: String?
    public var rubyTokens: [LyricRubyToken]?
    /// Runtime-only reading projection fields. They are never written back
    /// into the source lyric version; the shared ReadingSessionController
    /// uses them to distinguish pinyin/script-converted display from legacy
    /// Japanese columns.
    public var readingRepresentationID: String?
    public var readingSurfaceText: String?
    
    public init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        originalText: String,
        endTime: TimeInterval? = nil,
        translationText: String? = nil,
        romajiText: String? = nil,
        kanaText: String? = nil,
        rubyTokens: [LyricRubyToken]? = nil,
        readingRepresentationID: String? = nil,
        readingSurfaceText: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.endTime = endTime
        self.originalText = originalText
        self.translationText = translationText
        self.romajiText = romajiText
        self.kanaText = kanaText
        self.rubyTokens = rubyTokens
        self.readingRepresentationID = readingRepresentationID
        self.readingSurfaceText = readingSurfaceText
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
/// callers. Turning the layer off/on preserves the last selected visible
/// mode, while choosing a mode directly never depends on that Boolean.
public enum KanaDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case independentLine = "independentLine"
    case inlineRuby = "inlineRuby"
    case kanaReplacement = "kanaReplacement"
    case hidden = "hidden"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .independentLine: return "独立行"
        case .inlineRuby: return "悬浮注音"
        case .kanaReplacement: return "假名替换"
        case .hidden: return "隐藏"
        }
    }

    public var detail: String {
        switch self {
        case .independentLine: return "整行显示假名，适合初学者对照阅读"
        case .inlineRuby: return "假名贴在对应汉字上方，保持正文连续"
        case .kanaReplacement: return "假名替换汉字，原汉字置于上方作为辅助标注"
        case .hidden: return "不显示假名层"
        }
    }
}

public struct DisplayPreferences: Equatable {
    public var showOriginal: Bool = true
    public var showTranslation: Bool = true
    public var showRomaji: Bool = true
    public var showPinyin: Bool = true
    private var storedKanaDisplayMode: KanaDisplayMode
    private var lastVisibleKanaDisplayMode: KanaDisplayMode
    public var fontSize: CGFloat = 18
    public var opacity: Double = 0.85
    public var alwaysOnTop: Bool = true
    public var assistantFontSize: CGFloat = 14
    public var rubyFontSize: CGFloat = 10
    public var hideDistantAuxiliary: Bool = true

    public var kanaDisplayMode: KanaDisplayMode {
        get { storedKanaDisplayMode }
        set {
            storedKanaDisplayMode = newValue
            if newValue != .hidden {
                lastVisibleKanaDisplayMode = newValue
            }
        }
    }

    /// Compatibility bridge for the previous Boolean setting. It is only a
    /// visibility switch; it does not choose between the three presentations.
    public var showKana: Bool {
        get { kanaDisplayMode != .hidden }
        set {
            if newValue {
                if storedKanaDisplayMode == .hidden {
                    storedKanaDisplayMode = lastVisibleKanaDisplayMode
                }
            } else {
                if storedKanaDisplayMode != .hidden {
                    lastVisibleKanaDisplayMode = storedKanaDisplayMode
                }
                storedKanaDisplayMode = .hidden
            }
        }
    }

    public init(
        showOriginal: Bool = true,
        showTranslation: Bool = true,
        showRomaji: Bool = true,
        showPinyin: Bool = true,
        showKana: Bool = false,
        kanaDisplayMode: KanaDisplayMode? = nil,
        fontSize: CGFloat = 18,
        opacity: Double = 0.85,
        alwaysOnTop: Bool = true,
        assistantFontSize: CGFloat = 14,
        rubyFontSize: CGFloat = 10,
        hideDistantAuxiliary: Bool = true
    ) {
        self.showOriginal = showOriginal
        self.showTranslation = showTranslation
        self.showRomaji = showRomaji
        self.showPinyin = showPinyin
        let selectedMode = kanaDisplayMode ?? (showKana ? .independentLine : .hidden)
        self.storedKanaDisplayMode = selectedMode
        self.lastVisibleKanaDisplayMode = selectedMode == .hidden
            ? .independentLine
            : selectedMode
        self.fontSize = fontSize
        self.opacity = opacity
        self.alwaysOnTop = alwaysOnTop
        self.assistantFontSize = assistantFontSize
        self.rubyFontSize = rubyFontSize
        self.hideDistantAuxiliary = hideDistantAuxiliary
    }
}
