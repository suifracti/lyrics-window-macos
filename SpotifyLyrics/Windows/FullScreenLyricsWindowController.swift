import AppKit
import Combine
import SwiftUI

private final class FullScreenLyricsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            WindowManager.shared.hideFullScreen()
            return
        }
        super.keyDown(with: event)
    }
}

/// Owns the single retained fullscreen panel.  Playback, lyric selection,
/// translation and the current row remain owned by the shared PlaybackState.
@MainActor
final class FullScreenLyricsWindowController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isVisible = false
    @Published private(set) var controlsVisible = false
    /// Extra bottom space occupied by a visible Dock. The panel still covers
    /// the full screen frame, but controls stay in the screen's visible area.
    @Published private(set) var extraBottomContentInset: CGFloat = 0

    private var panel: FullScreenLyricsPanel?
    private weak var playbackState: PlaybackState?
    private var screenChangeObserver: NSObjectProtocol?
    private var localKeyMonitor: Any?
    private var controlsHideTask: Task<Void, Never>?

    /// WindowManager installs this weakly-capturing callback so Esc, a close
    /// request, and a menu hide all restore only the auxiliaries that were
    /// visible before fullscreen opened.
    var onDidHide: (() -> Void)?

    override init() {
        super.init()
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.repositionForCurrentScreen()
            }
        }
    }

    deinit {
        controlsHideTask?.cancel()
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
    }

    func toggle(state: PlaybackState) {
        if isVisible {
            hide()
        } else {
            _ = show(state: state)
        }
    }

    @discardableResult
    func show(state: PlaybackState) -> Bool {
        playbackState = state
        if panel == nil {
            panel = makePanel(state: state)
        }

        guard let panel, let screen = targetScreen() else { return false }
        panel.setFrame(screen.frame, display: true)
        updateContentInset(for: screen)
        panel.level = .floating
        panel.orderFrontRegardless()
        isVisible = true
        controlsVisible = true
        state.showFullScreen = true
        installLocalKeyMonitor()
        scheduleControlsHide()
        return true
    }

    func hide() {
        controlsHideTask?.cancel()
        controlsHideTask = nil
        removeLocalKeyMonitor()

        let hadVisibleSurface = isVisible || playbackState?.showFullScreen == true
        panel?.orderOut(nil)
        isVisible = false
        controlsVisible = false
        extraBottomContentInset = 0
        playbackState?.showFullScreen = false

        if hadVisibleSurface {
            onDidHide?()
        }
    }

    func revealControls() {
        guard isVisible else { return }
        controlsHideTask?.cancel()
        controlsHideTask = nil
        if !controlsVisible {
            controlsVisible = true
        }
        scheduleControlsHide()
    }

    func scheduleControlsHide() {
        guard isVisible else { return }
        controlsHideTask?.cancel()
        controlsHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.controlsVisible = false
        }
    }

    private func makePanel(state: PlaybackState) -> FullScreenLyricsPanel {
        let panel = FullScreenLyricsPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.acceptsMouseMovedEvents = true
        panel.contentView = NSHostingView(
            rootView: FullScreenLyricsView(
                state: state,
                windowController: self
            )
        )
        return panel
    }

    private func targetScreen() -> NSScreen? {
        WindowStatePersistence.shared.attachedMainWindow?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func repositionForCurrentScreen() {
        guard isVisible, let panel, let screen = targetScreen() else { return }
        panel.setFrame(screen.frame, display: true)
        updateContentInset(for: screen)
    }

    private func updateContentInset(for screen: NSScreen) {
        // `visibleFrame.minY` rises when the Dock is visible at the bottom;
        // menu-bar space is at the opposite edge and does not affect the
        // bottom controls. Keep the extra value separate from the view's
        // normal rhythm so auto-hidden Dock behavior remains stable.
        extraBottomContentInset = max(0, screen.visibleFrame.minY - screen.frame.minY)
    }

    private func installLocalKeyMonitor() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            if event.keyCode == 53 {
                self.hide()
                return nil
            }
            return event
        }
    }

    private func removeLocalKeyMonitor() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        hide()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
