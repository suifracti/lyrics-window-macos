import AppKit
import Combine
import SwiftUI

private final class CapsuleLyricsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the single top capsule panel.  It is a window lifecycle owner only:
/// playback, lyrics, translation and the current row remain in PlaybackState
/// and its shared session controllers.
@MainActor
final class CapsuleLyricsWindowController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isVisible = false
    @Published private(set) var presentationState: CapsulePresentationState = .collapsed

    private let persistence = CapsuleLyricsWindowPersistence.shared
    private var panel: CapsuleLyricsPanel?
    private weak var playbackState: PlaybackState?
    private var settings: AppSettingsStore?
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var screenChangeObserver: NSObjectProtocol?
    private var hoverCollapseTask: Task<Void, Never>?
    private var didRestore = false
    private var isApplyingFrame = false
#if DEBUG
    private var debugAnchor: CapsuleDebugAnchor = .topCenter
#else
    private let debugAnchor: CapsuleDebugAnchor = .topCenter
#endif

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
        hoverCollapseTask?.cancel()
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
        }
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
    }

    func toggle(state: PlaybackState, settings: AppSettingsStore) {
        configure(state: state, settings: settings)
        isVisible ? hide() : show()
    }

    func restoreIfConfigured(state: PlaybackState, settings: AppSettingsStore) {
        configure(state: state, settings: settings)
        guard !didRestore else { return }
        didRestore = true
        guard settings.restoreWindowState, settings.capsuleWindowWasVisible else { return }
        show()
    }

    func show(state: PlaybackState, settings: AppSettingsStore) {
        configure(state: state, settings: settings)
        show()
    }

    func hide() {
        hoverCollapseTask?.cancel()
        removeOutsideClickMonitors()
        savePosition()
        panel?.orderOut(nil)
        isVisible = false
        presentationState = .collapsed
        settings?.capsuleWindowWasVisible = false
        playbackState?.showCapsulePlayer = false
    }

    /// Temporary fullscreen orchestration keeps the user's persisted
    /// visibility and frame untouched.  It is deliberately separate from
    /// `hide()`, which is the user's explicit hide action.
    func temporarilyHideForFullScreen() {
        guard isVisible else { return }
        cancelHoverCollapse()
        removeOutsideClickMonitors()
        panel?.orderOut(nil)
        isVisible = false
        playbackState?.showCapsulePlayer = false
    }

    func restoreAfterFullScreen() {
        guard let panel, !isVisible else { return }
        if let settings {
            applyFrame(for: presentationState, settings: settings)
        }
        panel.isMovable = presentationState == .expanded
        panel.isMovableByWindowBackground = presentationState == .expanded
        if presentationState == .expanded {
            installOutsideClickMonitors()
        }
        panel.level = .floating
        panel.orderFrontRegardless()
        isVisible = true
        playbackState?.showCapsulePlayer = true
    }

    func expand() {
        guard isVisible else { return }
        cancelHoverCollapse()
        setPresentationState(.expanded)
        installOutsideClickMonitors()
    }

    func collapse() {
        guard isVisible else { return }
        cancelHoverCollapse()
        removeOutsideClickMonitors()
        setPresentationState(.collapsed)
    }

    func toggleExpanded() {
        presentationState == .expanded ? collapse() : expand()
    }

#if DEBUG
    /// Moves the existing panel for design comparison only. The transient
    /// anchor never writes the user's normal saved offset or screen ID.
    func setDebugAnchor(_ anchor: CapsuleDebugAnchor) {
        guard debugAnchor != anchor else { return }
        debugAnchor = anchor
        guard isVisible, let settings else { return }
        applyFrame(for: presentationState, settings: settings)
    }
#endif

    func pointerEntered() {
        cancelHoverCollapse()
        guard isVisible, presentationState != .expanded else { return }
        setPresentationState(.hover)
    }

    func pointerExited() {
        guard presentationState == .hover else { return }
        cancelHoverCollapse()
        hoverCollapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.collapse()
        }
    }

    private func configure(state: PlaybackState, settings: AppSettingsStore) {
        playbackState = state
        self.settings = settings
        if panel == nil {
            let panel = makePanel(state: state)
            self.panel = panel
        }
    }

    private func makePanel(state: PlaybackState) -> CapsuleLyricsPanel {
        let frame = persistence.restoreFrame(
            for: .collapsed,
            settings: settings ?? AppSettingsStore.shared,
            mainWindow: WindowStatePersistence.shared.attachedMainWindow,
            debugAnchor: debugAnchor
        )
        let panel = CapsuleLyricsPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.contentView = NSHostingView(
            rootView: CapsuleLyricsView(state: state, windowController: self)
        )
        return panel
    }

    private func show() {
        guard let panel, let settings else { return }
        cancelHoverCollapse()
        removeOutsideClickMonitors()
        presentationState = .collapsed
        applyFrame(for: .collapsed, settings: settings)
        panel.level = .floating
        // A nonactivating panel may be ordered behind the main SwiftUI window
        // when it is created from a menu command.  Ordering it regardless
        // does not make it key or activate another application.
        panel.orderFrontRegardless()
        isVisible = true
        settings.capsuleWindowWasVisible = true
        playbackState?.showCapsulePlayer = true
    }

    private func setPresentationState(_ newState: CapsulePresentationState) {
        guard newState != presentationState else { return }
        presentationState = newState
        if let settings {
            applyFrame(for: newState, settings: settings)
        }
        panel?.isMovable = newState == .expanded
        panel?.isMovableByWindowBackground = newState == .expanded
    }

    private func applyFrame(for state: CapsulePresentationState, settings: AppSettingsStore) {
        guard let panel else { return }
        let frame = persistence.restoreFrame(
            for: state,
            settings: settings,
            mainWindow: WindowStatePersistence.shared.attachedMainWindow,
            debugAnchor: debugAnchor
        )
        isApplyingFrame = true
        panel.setFrame(frame, display: true, animate: isVisible)
        isApplyingFrame = false
    }

    private func savePosition() {
        guard let panel, let settings else { return }
#if DEBUG
        // Do not turn a comparison anchor's derived frame into the user's
        // normal centered horizontal offset.
        guard debugAnchor == .topCenter else { return }
#endif
        let screen = panel.screen
            ?? persistence.targetScreen(mainWindow: WindowStatePersistence.shared.attachedMainWindow)
        guard let screen else { return }
        let safe = persistence.clampTopFrame(panel.frame, to: screen.visibleFrame)
        if safe != panel.frame {
            isApplyingFrame = true
            panel.setFrame(safe, display: false)
            isApplyingFrame = false
        }
        settings.capsuleWindowHorizontalOffset = Double(
            persistence.horizontalOffset(for: safe, screen: screen)
        )
        settings.capsuleWindowScreenID = persistence.screenIdentifier(screen)
    }

    private func repositionForCurrentScreen() {
        guard isVisible, let settings else { return }
        applyFrame(for: presentationState, settings: settings)
        savePosition()
    }

    private func installOutsideClickMonitors() {
        guard outsideClickMonitor == nil, localClickMonitor == nil else { return }
        let handler: (NSEvent) -> NSEvent? = { [weak self] event in
            guard let self, self.presentationState == .expanded else { return event }
            if event.window !== self.panel {
                self.collapse()
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] event in
                guard let self, self.presentationState == .expanded else { return }
                if event.window !== self.panel { self.collapse() }
            }
        )
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: handler
        )
    }

    private func removeOutsideClickMonitors() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    private func cancelHoverCollapse() {
        hoverCollapseTask?.cancel()
        hoverCollapseTask = nil
    }

    func windowDidMove(_ notification: Notification) {
        guard !isApplyingFrame, presentationState == .expanded else { return }
        savePosition()
        // The capsule is a top window, not a freely movable desktop panel.
        if let settings { applyFrame(for: presentationState, settings: settings) }
    }

    func windowWillClose(_ notification: Notification) {
        hide()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
