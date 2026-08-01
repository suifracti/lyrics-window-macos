import SwiftUI
import AppKit

// Window mode compatibility façade. Floating lyrics owns its lifecycle in a
// dedicated NSPanel controller; capsule and full-screen remain unchanged.
@MainActor
public final class WindowManager: ObservableObject {
    public static let shared = WindowManager()

    private var floatingController: FloatingLyricsWindowController?
    private var capsuleWindow: NSWindow?
    private var fullScreenWindow: NSWindow?

    public func toggleFloatingWindow(state: PlaybackState) {
        if floatingController == nil {
            floatingController = FloatingLyricsWindowController()
        }
        floatingController?.toggle(state: state, settings: AppSettingsStore.shared)
    }

    public func restoreFloatingWindowIfConfigured(state: PlaybackState) {
        if floatingController == nil {
            floatingController = FloatingLyricsWindowController()
        }
        floatingController?.restoreIfConfigured(state: state, settings: AppSettingsStore.shared)
    }

    public var floatingWindowIsVisible: Bool {
        floatingController?.isVisible == true
    }

    public var floatingInteractionMode: FloatingLyricsInteractionMode {
        floatingController?.interactionMode ?? AppSettingsStore.shared.floatingWindowInteractionMode
    }

    public func setFloatingInteractionMode(_ mode: FloatingLyricsInteractionMode, state: PlaybackState) {
        let settings = AppSettingsStore.shared
        settings.floatingWindowInteractionMode = mode
        if floatingController == nil {
            floatingController = FloatingLyricsWindowController()
        }
        floatingController?.setInteractionMode(mode)
        state.showFloatingWindow = floatingController?.isVisible == true
    }

    public func restoreFloatingInteractiveMode(state: PlaybackState) {
        setFloatingInteractionMode(.interactive, state: state)
    }

    public func toggleCapsulePlayer(state: PlaybackState) {
        if let window = capsuleWindow, window.isVisible {
            window.orderOut(nil)
            state.showCapsulePlayer = false
        } else {
            if capsuleWindow == nil {
                guard let mainScreen = NSScreen.main else { return }
                let screenFrame = mainScreen.visibleFrame
                let width: CGFloat = 380
                let height: CGFloat = 46
                let x = screenFrame.midX - (width / 2)
                let y = screenFrame.maxY - height - 10
                
                let window = NSWindow(
                    contentRect: NSRect(x: x, y: y, width: width, height: height),
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.isOpaque = false
                window.backgroundColor = .clear
                window.level = .statusBar
                window.isMovableByWindowBackground = true
                window.hasShadow = true
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                window.contentView = NSHostingView(rootView: CapsulePlayerView().environmentObject(state))
                capsuleWindow = window
            }
            capsuleWindow?.makeKeyAndOrderFront(nil)
            state.showCapsulePlayer = true
        }
    }

    public func toggleFullScreen(state: PlaybackState) {
        if let window = fullScreenWindow, window.isVisible {
            window.orderOut(nil)
            state.showFullScreen = false
        } else {
            if fullScreenWindow == nil {
                guard let mainScreen = NSScreen.main else { return }
                let window = NSWindow(
                    contentRect: mainScreen.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                window.isOpaque = true
                window.backgroundColor = .black
                window.level = .modalPanel
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                window.contentView = NSHostingView(rootView: FullScreenLyricsView().environmentObject(state))
                fullScreenWindow = window
            }
            fullScreenWindow?.makeKeyAndOrderFront(nil)
            state.showFullScreen = true
        }
    }
}
