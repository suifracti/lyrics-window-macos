import Foundation

public final class LocalLyricsProvider: LyricsProvider, @unchecked Sendable {
    // Default directories are owned by LocalLyricsIndex:
    // ~/Music/SpotifyLyrics/Lyrics
    // ~/Library/Application Support/SpotifyLyrics/Lyrics
    public let name = "Local LRC"
    public let executionLane: LyricsProviderExecutionLane = .local
    public let timeoutInterval: TimeInterval = 2

    private let index: LocalLyricsIndex

    public init(searchDirectories: [URL]? = nil, index: LocalLyricsIndex? = nil) {
        if let index {
            self.index = index
        } else if let searchDirectories {
            self.index = LocalLyricsIndex(searchDirectories: searchDirectories)
        } else {
            self.index = .shared
        }
    }

    public func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult {
        if Task.isCancelled {
            return .failed(.unknown("歌词请求已取消"))
        }

        guard let document = index.bestMatch(for: track, identity: identity) else {
            return .noMatch
        }

        if Task.isCancelled {
            return .failed(.unknown("歌词请求已取消"))
        }

        if document.lines.isEmpty {
            return .noLyrics
        }
        if LyricsMatcher.isHighConfidence(document.confidence) {
            return .match(document)
        }

        let candidate = LyricsCandidate(
            id: "local:\(document.title ?? track.title):\(document.artist ?? track.artist)",
            identity: identity,
            title: document.title ?? track.title,
            artist: document.artist ?? track.artist,
            album: document.album ?? track.album,
            duration: document.duration ?? track.duration,
            lines: document.lines,
            isSynchronized: document.isSynchronized,
            source: .local,
            confidence: document.confidence,
            providerSourceID: document.providerSourceID
        )
        return .candidates([candidate])
    }
}
