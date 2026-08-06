#if DEBUG
import SwiftUI
import AppKit

/// DEBUG experimental product host — binds real PlaybackState + AutoAlign into Direction D.
/// Not the default main window. No Preview Matrix tabs.
struct DirectionDExperimentalProductHost: View {
    @EnvironmentObject private var playback: PlaybackState
    @StateObject private var adapter = DirectionDProductStateAdapter()
    @State private var router: DirectionDActionRouter

    init() {
        // Placeholder router; rebuilt on appear with playback.
        _router = State(initialValue: DirectionDActionRouter())
    }

    var body: some View {
        DirectionDProductStateHostView(adapter: adapter, router: router)
            .onAppear {
                router = Self.makeRouter(playback: playback)
                adapter.forcedPresentationOverride =
                    ProcessInfo.processInfo.environment["SPOTIFYLYRICS_DIRECTION_D_HOST_STATE"]
                adapter.bind(playback: playback)
            }
            .onChange(of: playback.hasLiveTrack) { _, _ in
                adapter.refreshFromProduct()
            }
            .frame(minWidth: 900, minHeight: 620)
            .preferredColorScheme(.dark)
            .accessibilityIdentifier("directionD.experimentalProductHost")
    }

    static func makeRouter(playback: PlaybackState) -> DirectionDActionRouter {
        DirectionDActionRouter(
            onOpenSpotify: {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            },
            onOpenSystemSettings: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            },
            onRetryPlaybackDetection: {
                playback.startProvider(connectSpotify: true)
            },
            onRetryLyricsSearch: {
                playback.retryLyrics()
            },
            onOpenManualLyricsSearch: {
                playback.retryLyrics()
            },
            onImportLyrics: {
                _ = playback.prepareManualLyricsFromTXT()
            },
            onOpenSongWorkbench: {
                // Inspector toggle is local UI; no second business owner.
            },
            onRetryAutomaticAlignment: {
                AutomaticAlignmentJobController.shared.retry()
            },
            onStopAutomaticAlignment: {
                AutomaticAlignmentJobController.shared.cancelCurrentJob(userInitiated: true)
            }
        )
    }
}
#endif
