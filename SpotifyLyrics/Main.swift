import SwiftUI
import AppKit

@main
struct SpotifyLyricsApp: App {
    @StateObject private var playbackState = PlaybackState()

    var body: some Scene {
        WindowGroup {
            MainLyricsWindowView()
                .environmentObject(playbackState)
        }
        .defaultSize(width: 1040, height: 680)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}
