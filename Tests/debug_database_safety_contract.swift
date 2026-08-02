import Foundation

@main
struct DebugDatabaseSafetyContract {
    static func main() {
        let formal = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SpotifyLyrics/SpotifyLyrics.sqlite3")

        let noOverride = DebugDatabaseSafety.status(environment: [
            "SPOTIFYLYRICS_DATABASE_PATH": ""
        ])
        precondition(noOverride.configuredDatabaseURL == nil)
        precondition(!noOverride.isSafeForForcedPresentation)
        precondition(!noOverride.formalDatabaseOpened)
        precondition(noOverride.logLines.contains(where: { $0.contains("formal_database_opened=NO") }))
        precondition(noOverride.refusalMessage.contains("SPOTIFYLYRICS_DATABASE_PATH"))
        precondition(noOverride.refusalMessage.contains(DebugDatabaseSafety.forcedPresentationID))

        let temporary = URL(fileURLWithPath: "/tmp/spotifylyrics-debug-safety.sqlite3")
        let temporaryStatus = DebugDatabaseSafety.status(environment: [
            "SPOTIFYLYRICS_DATABASE_PATH": temporary.path
        ])
        precondition(temporaryStatus.configuredDatabaseURL == temporary.standardizedFileURL)
        precondition(temporaryStatus.isTemporaryCopy)
        precondition(temporaryStatus.isSafeForForcedPresentation)
        precondition(!temporaryStatus.formalDatabaseOpened)
        precondition(temporaryStatus.actualDatabaseURL == temporary.standardizedFileURL)
        precondition(temporaryStatus.logLines.contains(where: { $0.contains("temporary_copy=YES") }))

        let foundationTemporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("spotifylyrics-debug-safety.sqlite3")
        let foundationTemporaryStatus = DebugDatabaseSafety.status(environment: [
            "SPOTIFYLYRICS_DATABASE_PATH": foundationTemporary.path
        ])
        precondition(foundationTemporaryStatus.isSafeForForcedPresentation)

        let formalStatus = DebugDatabaseSafety.status(environment: [
            "SPOTIFYLYRICS_DATABASE_PATH": formal.path
        ])
        precondition(!formalStatus.isTemporaryCopy)
        precondition(!formalStatus.isSafeForForcedPresentation)
        precondition(!formalStatus.formalDatabaseOpened)
        precondition(formalStatus.refusalMessage.contains("temporary"))

        print("debug database safety contract: PASS")
    }
}
