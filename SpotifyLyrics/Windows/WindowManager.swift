import SwiftUI
import AppKit

/// Window lifecycle façade for the auxiliary lyrics surfaces.  Each surface
/// has one retained controller, while PlaybackState remains the single owner
/// of playback, lyric, translation and current-line state.
@MainActor
public final class WindowManager: ObservableObject {
    public static let shared = WindowManager()

    private struct FullScreenAuxiliaryVisibilitySnapshot {
        let floatingWasVisible: Bool
        let capsuleWasVisible: Bool
    }

    private var floatingController: FloatingLyricsWindowController?
    private var capsuleController: CapsuleLyricsWindowController?
    private var fullScreenController: FullScreenLyricsWindowController?
    private var fullScreenAuxiliaryVisibilitySnapshot: FullScreenAuxiliaryVisibilitySnapshot?
    private var terminationObserver: NSObjectProtocol?

    private init() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Never resurrect auxiliary windows while the application is
            // terminating.  The snapshot is transient and never persisted.
            self?.fullScreenAuxiliaryVisibilitySnapshot = nil
            self?.fullScreenController?.onDidHide = nil
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    public func showFloatingLyrics(state: PlaybackState) {
        guard fullScreenController?.isVisible != true else { return }
        if floatingController == nil {
            floatingController = FloatingLyricsWindowController()
        }
        floatingController?.show(state: state, settings: AppSettingsStore.shared)
    }

    public func hideFloatingLyrics() {
        floatingController?.hide()
    }

    public func toggleFloatingLyrics(state: PlaybackState) {
        guard fullScreenController?.isVisible != true else { return }
        if floatingController == nil {
            floatingController = FloatingLyricsWindowController()
        }
        floatingController?.toggle(state: state, settings: AppSettingsStore.shared)
    }

    /// Compatibility entry point for callers outside the current production
    /// surface. New production call sites use `toggleFloatingLyrics`.
    public func toggleFloatingWindow(state: PlaybackState) {
        toggleFloatingLyrics(state: state)
    }

    public func restoreFloatingWindowIfConfigured(state: PlaybackState) {
        guard fullScreenController?.isVisible != true else { return }
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

    public func showCapsule(state: PlaybackState) {
        guard fullScreenController?.isVisible != true else { return }
        if capsuleController == nil {
            capsuleController = CapsuleLyricsWindowController()
        }
        capsuleController?.show(state: state, settings: AppSettingsStore.shared)
    }

    public func hideCapsule() {
        capsuleController?.hide()
    }

    public func toggleCapsule(state: PlaybackState) {
        guard fullScreenController?.isVisible != true else { return }
        if capsuleController == nil {
            capsuleController = CapsuleLyricsWindowController()
        }
        capsuleController?.toggle(state: state, settings: AppSettingsStore.shared)
    }

    /// Compatibility entry point for callers outside the current production
    /// surface. New production call sites use `toggleCapsule`.
    public func toggleCapsulePlayer(state: PlaybackState) {
        toggleCapsule(state: state)
    }

    public func restoreCapsuleWindowIfConfigured(state: PlaybackState) {
        guard fullScreenController?.isVisible != true else { return }
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

    public var fullScreenWindowIsVisible: Bool {
        fullScreenController?.isVisible == true
    }

    public func toggleFullScreen(state: PlaybackState) {
        if fullScreenController?.isVisible == true {
            hideFullScreen()
        } else {
            showFullScreen(state: state)
        }
    }

    public func showFullScreen(state: PlaybackState) {
        guard fullScreenController?.isVisible != true else { return }
        captureAndHideAuxiliaryWindows()

        let controller = makeFullScreenController()
        guard controller.show(state: state) else {
            restoreFloatingSurfacesAfterFullscreen()
            return
        }
    }

    public func hideFullScreen() {
        guard let controller = fullScreenController else {
            restoreFloatingSurfacesAfterFullscreen()
            return
        }
        controller.hide()
        // `hide()` normally invokes the callback.  This fallback also covers
        // a controller that had no visible panel but still held a snapshot.
        if !controller.isVisible {
            restoreFloatingSurfacesAfterFullscreen()
        }
    }

    private func makeFullScreenController() -> FullScreenLyricsWindowController {
        if let fullScreenController { return fullScreenController }
        let controller = FullScreenLyricsWindowController()
        controller.onDidHide = { [weak self] in
            self?.finishFullScreenHide()
        }
        fullScreenController = controller
        return controller
    }

    private func captureAndHideAuxiliaryWindows() {
        guard fullScreenAuxiliaryVisibilitySnapshot == nil else { return }
        let snapshot = FullScreenAuxiliaryVisibilitySnapshot(
            floatingWasVisible: floatingController?.isVisible == true,
            capsuleWasVisible: capsuleController?.isVisible == true
        )
        fullScreenAuxiliaryVisibilitySnapshot = snapshot
        floatingController?.temporarilyHideForFullScreen()
        capsuleController?.temporarilyHideForFullScreen()
    }

    private func finishFullScreenHide() {
        restoreFloatingSurfacesAfterFullscreen()
    }

    public func restoreFloatingSurfacesAfterFullscreen() {
        guard let snapshot = fullScreenAuxiliaryVisibilitySnapshot else { return }
        fullScreenAuxiliaryVisibilitySnapshot = nil

        if snapshot.floatingWasVisible {
            floatingController?.restoreAfterFullScreen()
        }
        if snapshot.capsuleWasVisible {
            capsuleController?.restoreAfterFullScreen()
        }
    }
}
