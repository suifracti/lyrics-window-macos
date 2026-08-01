import SwiftUI
import AppKit

// Window mode compatibility façade. Floating lyrics owns its lifecycle in a
// dedicated NSPanel controller; capsule and full-screen remain unchanged.
@MainActor
public final class WindowManager: ObservableObject {
    public static let shared = WindowManager()

    private var floatingController: FloatingLyricsWindowController?
    private var capsuleController: CapsuleLyricsWindowController?
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
        if capsuleController == nil {
            capsuleController = CapsuleLyricsWindowController()
        }
        capsuleController?.toggle(state: state, settings: AppSettingsStore.shared)
    }

    public func restoreCapsuleWindowIfConfigured(state: PlaybackState) {
        if capsuleController == nil {
            capsuleController = CapsuleLyricsWindowController()
        }
        capsuleController?.restoreIfConfigured(state: state, settings: AppSettingsStore.shared)
    }

    public func collapseCapsulePlayer() {
        capsuleController?.collapse()
    }

    public func expandCapsulePlayer() {
        capsuleController?.expand()
    }

    public var capsuleWindowIsVisible: Bool {
        capsuleController?.isVisible == true
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
