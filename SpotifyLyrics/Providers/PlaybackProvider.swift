import Foundation

public enum PlaybackProviderState: Equatable, Sendable {
    case mockPreview
    case connecting
    case ready
    case notInstalled
    case notRunning
    case permissionDenied
    case noTrack
    case unavailable(String)

    public var userFacingMessage: String {
        switch self {
        case .mockPreview:
            return "Mock 预览"
        case .connecting:
            return "正在连接 Spotify Desktop"
        case .ready:
            return "Spotify Desktop 已连接"
        case .notInstalled:
            return "未安装 Spotify.app"
        case .notRunning:
            return "Spotify.app 未运行"
        case .permissionDenied:
            return "未获得控制 Spotify 的权限"
        case .noTrack:
            return "Spotify 当前没有播放歌曲"
        case .unavailable(let message):
            return "Spotify 不可用：\(message)"
        }
    }

    public var isReady: Bool {
        self == .ready
    }
}

public struct ProviderTrack: Equatable, Sendable {
    /// Spotify's stable track identifier when the provider can read one.
    /// It is optional so identity can correctly fall back to metadata when
    /// Spotify does not expose an ID/URI/ISRC.
    public let id: String?
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval
    public let artworkURL: URL?
    public let spotifyURL: URL?
    public let isrc: String?

    public init(
        id: String? = nil,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        artworkURL: URL? = nil,
        spotifyURL: URL? = nil,
        isrc: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkURL = artworkURL
        self.spotifyURL = spotifyURL
        self.isrc = isrc
    }
}

public struct PlaybackSnapshot: Equatable, Sendable {
    public let status: PlaybackProviderState
    public let track: ProviderTrack?
    public let position: TimeInterval
    public let isPlaying: Bool

    public init(
        status: PlaybackProviderState,
        track: ProviderTrack? = nil,
        position: TimeInterval = 0,
        isPlaying: Bool = false
    ) {
        self.status = status
        self.track = track
        self.position = position
        self.isPlaying = isPlaying
    }
}

public enum PlaybackProviderError: LocalizedError, Equatable, Sendable {
    case notInstalled
    case notRunning
    case permissionDenied
    case noTrack
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            return PlaybackProviderState.notInstalled.userFacingMessage
        case .notRunning:
            return PlaybackProviderState.notRunning.userFacingMessage
        case .permissionDenied:
            return PlaybackProviderState.permissionDenied.userFacingMessage
        case .noTrack:
            return PlaybackProviderState.noTrack.userFacingMessage
        case .commandFailed(let message):
            return message
        }
    }
}

@MainActor
public protocol PlaybackProvider: AnyObject {
    var displayName: String { get }

    func refresh() async -> PlaybackSnapshot
    func play() async throws
    func pause() async throws
    func previous() async throws
    func next() async throws
    func seek(to position: TimeInterval) async throws
}
