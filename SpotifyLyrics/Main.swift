import SwiftUI
import AppKit

@main
struct SpotifyLyricsApp: App {
    @StateObject private var appSettings = AppSettingsStore.shared
    @StateObject private var playbackState = PlaybackState(settings: AppSettingsStore.shared)
    @StateObject private var settingsData = SettingsDataController()

    var body: some Scene {
        WindowGroup {
            MainLyricsWindowView()
                .environmentObject(playbackState)
                .environmentObject(appSettings)
        }
        .defaultSize(width: 1152, height: 720)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsRootView()
                .environmentObject(appSettings)
                .environmentObject(playbackState)
                .environmentObject(settingsData)
        }
        .defaultSize(width: 860, height: 580)

        // Settings scenes do not always add an app-menu item when the app is
        // hosted by a custom SwiftUI window configuration. Keep a stable,
        // native macOS entry point in addition to SettingsLink controls.
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("设置…")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
