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

public struct DisplayPreferences: Equatable {
    public var showOriginal: Bool = true
    public var showTranslation: Bool = true
    public var showRomaji: Bool = true
    public var showKana: Bool = false
    public var fontSize: CGFloat = 18
    public var opacity: Double = 0.85
    public var alwaysOnTop: Bool = true
}
