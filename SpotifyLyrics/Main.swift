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
        .defaultSize(width: 1152, height: 720)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}
