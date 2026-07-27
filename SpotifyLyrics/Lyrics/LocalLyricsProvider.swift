import Foundation

public final class LocalLyricsProvider: LyricsProvider {
    public let name = "Local Lyrics"

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

    public func lookup(track: Track, identity: TrackIdentity) async -> LyricsLookupResult {
        let files = lyricFiles()
        guard !files.isEmpty else { return .noMatch }

        var exactMatches: [LyricsDocument] = []
        var candidates: [LyricsCandidate] = []

        for file in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8),
                  let document = LRCParser.parse(content, identity: identity, source: .local) else {
                continue
            }

            let exact = identity.lookupKeys.contains { key in
                TrackIdentity.normalizedComponent(file.deletingPathExtension().lastPathComponent)
                    == TrackIdentity.normalizedComponent(key)
            }
            if exact {
                exactMatches.append(document)
                continue
            }

            let candidate = LyricsCandidate(
                id: file.path,
                identity: identity,
                title: document.title ?? track.title,
                artist: document.artist ?? track.artist,
                album: document.album ?? track.album,
                duration: document.duration ?? track.duration,
                lines: document.lines,
                source: .local,
                confidence: 0
            )
            let score = LyricsMatcher.score(track: track, candidate: candidate)
            candidates.append(
                LyricsCandidate(
                    id: candidate.id,
                    identity: candidate.identity,
                    title: candidate.title,
                    artist: candidate.artist,
                    album: candidate.album,
                    duration: candidate.duration,
                    lines: candidate.lines,
                    source: candidate.source,
                    confidence: score
                )
            )
        }

        if let exact = exactMatches.first {
            return .match(exact)
        }

        let sorted = candidates
            .filter { LyricsMatcher.isCandidate($0.confidence) }
            .sorted { $0.confidence > $1.confidence }
        guard let best = sorted.first else { return .noMatch }

        if LyricsMatcher.isHighConfidence(best.confidence),
           sorted.dropFirst().first.map({ best.confidence - $0.confidence >= 0.05 }) ?? true {
            return .match(
                LyricsDocument(
                    identity: identity,
                    title: best.title,
                    artist: best.artist,
                    album: best.album,
                    duration: best.duration,
                    lines: best.lines,
                    source: .local,
                    confidence: best.confidence
                )
            )
        }
        return .candidates(sorted)
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
            files.append(contentsOf: entries.filter { url in
                url.pathExtension.caseInsensitiveCompare("lrc") == .orderedSame
            })
        }
        return files
    }
}
