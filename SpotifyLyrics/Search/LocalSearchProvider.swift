import Foundation

public final class LocalSearchProvider: SongSearchProvider {
    public let name = "Local Search"

    private let searchDirectories: [URL]

    public init(searchDirectories: [URL]? = nil) {
        if let searchDirectories {
            self.searchDirectories = searchDirectories
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            var defaults = [
                home.appendingPathComponent("Music/SpotifyLyrics/Lyrics", isDirectory: true),
                home.appendingPathComponent("Library/Application Support/SpotifyLyrics/Lyrics", isDirectory: true)
            ]
            #if DEBUG
            defaults.append(
                URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                    .appendingPathComponent("Lyrics", isDirectory: true)
            )
            #endif
            self.searchDirectories = defaults
        }
    }

    public func search(query: SongSearchQuery) async throws -> [SongSearchResult] {
        guard !query.isEmpty else { return [] }

        var results: [SongSearchResult] = []
        for file in lyricFiles() {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let fallbackTitle = file.deletingPathExtension().lastPathComponent
            let fallbackTrack = Track(
                id: "local:\(file.path)",
                title: fallbackTitle,
                artist: query.artist ?? "",
                album: query.album ?? "",
                duration: query.duration ?? 0
            )
            let fallbackIdentity = TrackIdentity(track: fallbackTrack)
            guard let document = LRCParser.parse(content, identity: fallbackIdentity, source: .local) else { continue }

            let track = Track(
                id: "local:\(file.path)",
                title: document.title?.isEmpty == false ? document.title! : fallbackTitle,
                artist: document.artist ?? query.artist ?? "",
                album: document.album ?? query.album ?? "",
                duration: document.duration ?? query.duration ?? 0,
                artworkName: "music.note"
            )
            let score = SongSearchScoring.score(track: track, query: query)
            guard score >= 0.20 else { continue }

            let identity = TrackIdentity(track: track)
            let boundDocument = LyricsDocument(
                identity: identity,
                title: document.title,
                artist: document.artist,
                album: document.album,
                duration: document.duration,
                lines: document.lines,
                isSynchronized: document.isSynchronized,
                source: .local,
                confidence: score
            )
            results.append(
                SongSearchResult(
                    id: "local:\(file.path)",
                    source: .local,
                    track: track,
                    confidence: score,
                    lyrics: boundDocument
                )
            )
        }

        return results.sorted {
            if $0.confidence == $1.confidence { return $0.track.title < $1.track.title }
            return $0.confidence > $1.confidence
        }
    }

    private func lyricFiles() -> [URL] {
        let fileManager = FileManager.default
        var files: [URL] = []
        for directory in searchDirectories {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            files.append(contentsOf: entries.filter { $0.pathExtension.caseInsensitiveCompare("lrc") == .orderedSame })
        }
        return files
    }
}
