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

        Window("歌词编辑", id: "lyrics-editor") {
            LyricsEditorWindowView()
                .environmentObject(playbackState)
                .environmentObject(appSettings)
        }
        .defaultSize(width: 1100, height: 720)

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
            CommandMenu("窗口") {
                Button("显示/隐藏悬浮歌词") {
                    WindowManager.shared.toggleFloatingWindow(state: playbackState)
                }
                .keyboardShortcut("f", modifiers: [.command, .option])

                Button("解除悬浮歌词鼠标穿透") {
                    WindowManager.shared.restoreFloatingInteractiveMode(state: playbackState)
                }
                .keyboardShortcut("l", modifiers: [.command, .option])

                Divider()

                Button("锁定悬浮歌词") {
                    WindowManager.shared.setFloatingInteractionMode(.locked, state: playbackState)
                }
                Button("启用悬浮歌词鼠标穿透") {
                    WindowManager.shared.setFloatingInteractionMode(.passThrough, state: playbackState)
                }
                Button("恢复悬浮歌词可编辑") {
                    WindowManager.shared.setFloatingInteractionMode(.interactive, state: playbackState)
                }
            }
        }
    }
}
