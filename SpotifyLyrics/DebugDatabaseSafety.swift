#if DEBUG
import Foundation
import Darwin

/// Fail-closed database boundary for Debug-only presentation experiments.
///
/// Release builds do not compile this type. A forced capsule experiment must
/// explicitly point at a database under a temporary directory; the formal
/// Application Support database is never an acceptable Debug experiment input.
enum DebugDatabaseSafety {
    static let forcedPresentationID = "capsule.dynamicIslandDark.v4"
    static let forcedPresentationArgument = "--debug-capsule-v4"
    static let databaseEnvironmentKey = "SPOTIFYLYRICS_DATABASE_PATH"

    struct Status: Equatable {
        let configuredDatabaseURL: URL?
        let actualDatabaseURL: URL?
        let formalDatabaseURL: URL
        let isTemporaryCopy: Bool
        let isSafeForForcedPresentation: Bool
        /// This is the open status for the forced activation itself. It is
        /// always false before repository construction; repository opens are
        /// logged separately through `logRepositoryOpen`.
        let formalDatabaseOpened: Bool
        let logLines: [String]
        let refusalMessage: String
    }

    static func status(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Status {
        let formalURL = formalDatabaseURL
        let configuredPath = environment[databaseEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let configuredURL: URL? = configuredPath.flatMap { path in
            guard !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path).standardizedFileURL
        }

        let resolvedConfiguredURL = configuredURL?.resolvingSymlinksInPath()
        let resolvedFormalURL = formalURL.resolvingSymlinksInPath()
        let isFormalPath = if let resolvedConfiguredURL {
            samePath(resolvedConfiguredURL, resolvedFormalURL)
        } else {
            false
        }
        let isTemporary = if let resolvedConfiguredURL, !isFormalPath {
            isTemporaryURL(resolvedConfiguredURL)
        } else {
            false
        }
        let safe = configuredURL != nil && isTemporary && !isFormalPath
        let actualPath = configuredURL?.path ?? "<none; launch refused before repository init>"
        let lines = [
            "[SpotifyLyrics][DebugSafety] event=forced_presentation",
            "[SpotifyLyrics][DebugSafety] forced_presentation_id=\(forcedPresentationID)",
            "[SpotifyLyrics][DebugSafety] database_path=\(actualPath)",
            "[SpotifyLyrics][DebugSafety] formal_database_path=\(formalURL.path)",
            "[SpotifyLyrics][DebugSafety] temporary_copy=\(isTemporary ? "YES" : "NO")",
            "[SpotifyLyrics][DebugSafety] formal_database_opened=NO"
        ]
        let refusal = safe ? "" : refusalMessage(
            configuredURL: configuredURL,
            formalURL: formalURL
        )

        return Status(
            configuredDatabaseURL: configuredURL,
            actualDatabaseURL: configuredURL,
            formalDatabaseURL: formalURL,
            isTemporaryCopy: isTemporary,
            isSafeForForcedPresentation: safe,
            formalDatabaseOpened: false,
            logLines: lines,
            refusalMessage: refusal
        )
    }

    /// Called before any StateObject that can construct a repository.
    /// Command-line v4 runs therefore cannot even initialize the app against
    /// the formal database.
    static func failClosedForCommandLineV4IfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains(forcedPresentationArgument) else {
            return
        }

        let current = status()
        emit(current.logLines)
        guard current.isSafeForForcedPresentation else {
            emit(["[SpotifyLyrics][DebugSafety] refusal=\(current.refusalMessage)"])
            exit(78)
        }
    }

    /// Returns nil only when the Debug menu may activate v4. A normal Debug
    /// app launch may already have opened its configured repository; this
    /// guard prevents the menu action from forcing v4 without an explicit,
    /// temporary database and reports that fact instead of silently falling
    /// back to the formal database.
    static func menuActivationRefusalMessage() -> String? {
        let current = status()
        emit(current.logLines.map { $0.replacingOccurrences(of: "event=forced_presentation", with: "event=menu_activation") })
        guard current.isSafeForForcedPresentation else {
            let message = "[SpotifyLyrics][DebugSafety] menu_refusal=\(current.refusalMessage)"
            emit([message])
            return current.refusalMessage
        }
        return nil
    }

    /// Debug-only repository telemetry. This is intentionally limited to
    /// paths and safety classification; it never logs lyrics or credentials.
    static func logRepositoryOpen(databaseURL: URL) {
        let actual = databaseURL.standardizedFileURL
        let formal = samePath(actual.resolvingSymlinksInPath(), formalDatabaseURL.resolvingSymlinksInPath())
        let temporary = !formal && isTemporaryURL(actual.resolvingSymlinksInPath())
        emit([
            "[SpotifyLyrics][DebugSafety] event=repository_open",
            "[SpotifyLyrics][DebugSafety] forced_presentation_id=\(ProcessInfo.processInfo.arguments.contains(forcedPresentationArgument) ? forcedPresentationID : "none")",
            "[SpotifyLyrics][DebugSafety] database_path=\(actual.path)",
            "[SpotifyLyrics][DebugSafety] temporary_copy=\(temporary ? "YES" : "NO")",
            "[SpotifyLyrics][DebugSafety] formal_database_opened=\(formal ? "YES" : "NO")"
        ])
    }

    private static var formalDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3")
            .standardizedFileURL
    }

    private static func refusalMessage(configuredURL: URL?, formalURL: URL) -> String {
        let configured = configuredURL?.path ?? "<missing>"
        return "Refusing forced Debug presentation \(forcedPresentationID): \(databaseEnvironmentKey) must point to a temporary database copy under /tmp or the system temporary directory (configured=\(configured)); formal database was not opened (\(formalURL.path))."
    }

    private static func isTemporaryURL(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let temporaryRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let roots = [temporaryRoot, "/tmp", "/private/tmp"]
        return roots.contains { root in
            path == root || path.hasPrefix(root + "/")
        }
    }

    private static func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    private static func emit(_ lines: [String]) {
        let output = lines.joined(separator: "\n") + "\n"
        FileHandle.standardError.write(Data(output.utf8))
    }
}
#endif
