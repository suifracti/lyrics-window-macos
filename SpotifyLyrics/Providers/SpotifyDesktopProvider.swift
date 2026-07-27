import AppKit
import Foundation

@MainActor
public final class SpotifyDesktopProvider: PlaybackProvider {
    public let displayName = "Spotify Desktop"

    private let applicationPath = "/Applications/Spotify.app"
    private let bundleIdentifier = "com.spotify.client"
    private let fieldSeparator = String(UnicodeScalar(30))

    public init() {}

    public func refresh() async -> PlaybackSnapshot {
        guard FileManager.default.fileExists(atPath: applicationPath) else {
            return PlaybackSnapshot(status: .notInstalled, track: nil, position: 0, isPlaying: false)
        }

        guard isRunning else {
            return PlaybackSnapshot(status: .notRunning, track: nil, position: 0, isPlaying: false)
        }

        do {
            guard let result = try await execute(script: readScript) else {
                return PlaybackSnapshot(status: .unavailable("Spotify 没有返回当前歌曲"), track: nil, position: 0, isPlaying: false)
            }
            return parseSnapshot(result)
        } catch let error as AppleScriptExecutionError {
            return PlaybackSnapshot(status: map(error: error), track: nil, position: 0, isPlaying: false)
        } catch {
            return PlaybackSnapshot(
                status: .unavailable(error.localizedDescription),
                track: nil,
                position: 0,
                isPlaying: false
            )
        }
    }

    public func play() async throws {
        try await executeCommand("tell application \"Spotify\" to play")
    }

    public func pause() async throws {
        try await executeCommand("tell application \"Spotify\" to pause")
    }

    public func previous() async throws {
        try await executeCommand("tell application \"Spotify\" to previous track")
    }

    public func next() async throws {
        try await executeCommand("tell application \"Spotify\" to next track")
    }

    public func seek(to position: TimeInterval) async throws {
        let seconds = max(0, position)
        try await executeCommand(
            "tell application \"Spotify\" to set player position to \(Self.appleScriptNumber(seconds))"
        )
    }

    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    private var readScript: String {
        """
        tell application "Spotify"
            set stateText to (player state as text)
            set separator to character id 30
            try
                set currentTrack to current track
                return stateText & separator & (player position as text) & separator & (name of currentTrack as text) & separator & (artist of currentTrack as text) & separator & (album of currentTrack as text) & separator & (duration of currentTrack as text) & separator & (artwork url of currentTrack as text) & separator & (spotify url of currentTrack as text) & separator & (id of currentTrack as text)
            on error
                return stateText & separator & (player position as text) & separator & separator & separator & separator & separator & separator & separator
            end try
        end tell
        """
    }

    private func executeCommand(_ script: String) async throws {
        _ = try await execute(script: script)
    }

    private func execute(script: String) async throws -> String? {
        try await Task.detached(priority: .userInitiated) {
            var errorInfo: NSDictionary?
            let appleScript = NSAppleScript(source: script)
            let descriptor = appleScript?.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let number = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue
                let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Apple Events 执行失败"
                throw AppleScriptExecutionError(number: number, message: message)
            }
            return descriptor?.stringValue
        }.value
    }

    private func parseSnapshot(_ value: String) -> PlaybackSnapshot {
        let fields = value.components(separatedBy: fieldSeparator)
        guard fields.count >= 9 else {
            return PlaybackSnapshot(status: .unavailable("Spotify 返回的数据格式无法识别"), track: nil, position: 0, isPlaying: false)
        }

        let state = fields[0].lowercased()
        let position = Self.parseNumber(fields[1]) ?? 0
        let title = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = fields[4].trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = Self.normalizedDuration(Self.parseNumber(fields[5]) ?? 0)
        let artworkURL = Self.parseURL(fields[6])
        let spotifyURL = Self.parseURL(fields[7])
        let id = fields[8].trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty, duration > 0 else {
            return PlaybackSnapshot(
                status: .noTrack,
                track: nil,
                position: 0,
                isPlaying: false
            )
        }

        let track = ProviderTrack(
            id: id.isEmpty ? nil : id,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            artworkURL: artworkURL,
            spotifyURL: spotifyURL
        )

        let isPlaying = state == "playing"
        let status: PlaybackProviderState = state == "stopped" && title.isEmpty ? .noTrack : .ready
        return PlaybackSnapshot(status: status, track: track, position: min(max(0, position), duration), isPlaying: isPlaying)
    }

    private func map(error: AppleScriptExecutionError) -> PlaybackProviderState {
        if error.number == -1743 || error.message.localizedCaseInsensitiveContains("not authorized") || error.message.localizedCaseInsensitiveContains("not allowed") || error.message.localizedCaseInsensitiveContains("permission") {
            return .permissionDenied
        }
        if error.number == -600 || error.message.localizedCaseInsensitiveContains("not running") {
            return .notRunning
        }
        return .unavailable(error.message)
    }

    private static func parseNumber(_ value: String) -> TimeInterval? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return TimeInterval(normalized)
    }

    private static func normalizedDuration(_ raw: TimeInterval) -> TimeInterval {
        raw > 10_000 ? raw / 1_000 : raw
    }

    private static func parseURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private static func appleScriptNumber(_ value: TimeInterval) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

private struct AppleScriptExecutionError: Error {
    let number: Int?
    let message: String
}
