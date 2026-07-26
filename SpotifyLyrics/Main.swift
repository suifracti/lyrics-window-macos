import SwiftUI
import AppKit

@main
struct SpotifyLyricsApp: App {
    @StateObject private var playbackState = PlaybackState()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(playbackState)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
