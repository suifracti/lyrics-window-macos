import SwiftUI
import AppKit

@main
struct SpotifyLyricsApp: App {
    @StateObject private var appSettings: AppSettingsStore
    @StateObject private var playbackState: PlaybackState
    @StateObject private var settingsData: SettingsDataController

    init() {
#if DEBUG
        // This must run before any StateObject can construct a repository.
        // A command-line v4 run without a temporary database exits here,
        // before the formal Application Support database can be opened.
        DebugDatabaseSafety.failClosedForCommandLineV4IfNeeded()
#endif
        let settings = AppSettingsStore.shared
        _appSettings = StateObject(wrappedValue: settings)
        _playbackState = StateObject(wrappedValue: PlaybackState(settings: settings))
        _settingsData = StateObject(wrappedValue: SettingsDataController())
    }

    var body: some Scene {
        WindowGroup {
            MainLyricsWindowView()
                .environmentObject(playbackState)
                .environmentObject(appSettings)
#if DEBUG
                .onAppear {
                    // A command-line v4 run is a controlled visual harness.
                    // Showing the existing capsule after the main scene is
                    // ready keeps the harness deterministic without adding a
                    // second window, timer or business-state owner.
                    if DebugDatabaseSafety.isForcedPresentationArgument {
                        WindowManager.shared.setCapsuleDebugPresentation(
                            .dynamicIslandDarkV4,
                            state: playbackState
                        )
                    }
                    // Touch DEBUG capture singletons so env-driven spikes can start.
                    LiveCaptureCoordinator.shared.bind(playback: playbackState)
                    _ = SpotifyScreenCaptureAudioSpike.shared
                }
#endif
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

#if DEBUG
        Window("Presentation Preview Lab", id: "presentation-preview-lab") {
            PresentationPreviewLabView()
                .environmentObject(playbackState)
                .environmentObject(appSettings)
        }
        .defaultSize(width: 1_060, height: 680)
#endif

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
                    WindowManager.shared.toggleFloatingLyrics(state: playbackState)
                }
                .keyboardShortcut("f", modifiers: [.command, .option])

                Button("显示/隐藏顶部胶囊") {
                    WindowManager.shared.toggleCapsule(state: playbackState)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])

                Button("显示/隐藏全屏歌词") {
                    WindowManager.shared.toggleFullScreen(state: playbackState)
                }
                .keyboardShortcut("g", modifiers: [.command, .option])

                Button("收起顶部胶囊") {
                    WindowManager.shared.collapseCapsulePlayer()
                }
                Button("展开顶部胶囊") {
                    WindowManager.shared.expandCapsulePlayer()
                }

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
#if DEBUG
            CommandMenu("胶囊锚点（调试）") {
                Button("左上") {
                    WindowManager.shared.setCapsuleDebugAnchor(.topLeft)
                }
                Button("顶部居中") {
                    WindowManager.shared.setCapsuleDebugAnchor(.topCenter)
                }
                Button("右上") {
                    WindowManager.shared.setCapsuleDebugAnchor(.topRight)
                }
            }
            CommandMenu("胶囊呈现（调试）") {
                Button("验证 v4 外壳与尺寸") {
                    activateDebugCapsuleV4()
                }
                Button("恢复当前正式呈现") {
                    WindowManager.shared.setCapsuleDebugPresentation(
                        nil,
                        state: playbackState
                    )
                }
            }
            CommandMenu("排轴捕获 Spike（调试）") {
                Button("开始 Spotify 音频 Spike (S1)") {
                    Task { await SpotifyScreenCaptureAudioSpike.shared.start(autoStopAfter: 25) }
                }
                Button("停止 Spotify 音频 Spike (S1)") {
                    Task { await SpotifyScreenCaptureAudioSpike.shared.stop(reason: "menu") }
                }
                Divider()
                Button("开始 Live Capture (S2)") {
                    LiveCaptureCoordinator.shared.bind(playback: playbackState)
                    Task { await LiveCaptureCoordinator.shared.start(autoStopAfter: 90, runPartialAlignment: false) }
                }
                Button("开始 Partial 对齐 (S3A)") {
                    LiveCaptureCoordinator.shared.bind(playback: playbackState)
                    Task { await LiveCaptureCoordinator.shared.start(autoStopAfter: 75, runPartialAlignment: true) }
                }
                Button("停止 Live Capture / S3A") {
                    Task { await LiveCaptureCoordinator.shared.stop(reason: .userStop) }
                }
            }
#endif
        }
#if DEBUG
        .commands {
            PresentationPreviewCommands()
        }
#endif
    }

#if DEBUG
    private func activateDebugCapsuleV4() {
        if let refusal = DebugDatabaseSafety.menuActivationRefusalMessage() {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "已阻止 v4 调试呈现"
            alert.informativeText = refusal + "\n\n请使用临时数据库路径重新启动 Debug App。"
            alert.addButton(withTitle: "知道了")
            alert.runModal()
            return
        }

        WindowManager.shared.setCapsuleDebugPresentation(
            .dynamicIslandDarkV4,
            state: playbackState
        )
    }
#endif
}

#if DEBUG
private struct PresentationPreviewCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("预览实验室") {
            Button("打开 Presentation Preview Lab") {
                openWindow(id: "presentation-preview-lab")
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
        }
    }
}
#endif
