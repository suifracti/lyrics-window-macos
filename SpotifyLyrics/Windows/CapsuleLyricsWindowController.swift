import AppKit
import Combine
import SwiftUI

private final class CapsuleLyricsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Fixed-envelope host used only by the Debug top-attached prototype. The
/// AppKit window remains transparent outside the internal island; returning
/// nil here keeps the host from producing an interactive hit target in that
/// region. A second global mouse monitor below toggles `ignoresMouseEvents`
/// so the event is delivered to the application underneath as well.
private final class CapsuleEnvelopeHostingView: NSView {
    private let hostedView: NSView
    var interactiveFrameProvider: (() -> NSRect)?

    init(hostedView: NSView) {
        self.hostedView = hostedView
        super.init(frame: .zero)
        addSubview(hostedView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        hostedView.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactiveFrameProvider?().contains(point) == true else {
            return nil
        }
        return super.hitTest(point)
    }
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
    private var debugGlobalMouseMonitor: Any?
    private var debugLocalMouseMonitor: Any?
    private var envelopeHostingView: CapsuleEnvelopeHostingView?
    private var screenChangeObserver: NSObjectProtocol?
    private var hoverCollapseTask: Task<Void, Never>?
    private var didRestore = false
    private var isApplyingFrame = false
#if DEBUG
    private var debugAnchor: CapsuleDebugAnchor = .topCenter
    private(set) var debugTopAttachedEnvelope = ProcessInfo.processInfo.arguments.contains(
        "--debug-capsule-v4-top-attached"
    )
    @Published private(set) var debugPresentation: CapsuleLyricsPresentationVersion? =
        ProcessInfo.processInfo.arguments.contains("--debug-capsule-v4")
            || ProcessInfo.processInfo.arguments.contains("--debug-capsule-v4-top-attached")
        ? .dynamicIslandDarkV4
        : nil
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
        if let debugGlobalMouseMonitor {
            NSEvent.removeMonitor(debugGlobalMouseMonitor)
        }
        if let debugLocalMouseMonitor {
            NSEvent.removeMonitor(debugLocalMouseMonitor)
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
        removeDebugMouseMonitors()
        savePosition()
        panel?.ignoresMouseEvents = false
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
        removeDebugMouseMonitors()
        panel?.ignoresMouseEvents = false
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
#if DEBUG
        if debugTopAttachedEnvelope {
            panel.isMovable = false
            panel.isMovableByWindowBackground = false
            installDebugMouseMonitors()
        }
#endif
        if presentationState == .expanded {
            installOutsideClickMonitors()
        }
        panel.level = effectivePanelLevel
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

    /// Selects a renderer only for a Debug verification session. This is an
    /// injection into the existing controller, not a persisted presentation
    /// preference or a second window path.
    func setDebugPresentation(_ presentation: CapsuleLyricsPresentationVersion?) {
        guard debugPresentation != presentation else { return }
        debugPresentation = presentation
        guard isVisible, let settings else { return }
        applyFrame(for: presentationState, settings: settings)
    }
#endif

    var activePresentation: CapsuleLyricsPresentationVersion {
#if DEBUG
        if let debugPresentation { return debugPresentation }
#endif
        let raw = UserDefaults.standard.string(
            forKey: PresentationSelectionStore.runtimeKey(for: .capsule)
        )
        return raw.flatMap(CapsuleLyricsPresentationVersion.init(rawValue:))
            ?? CapsuleLyricsPresentationVersion.current
    }

    private var isDebugTopAttachedEnvelope: Bool {
#if DEBUG
        debugTopAttachedEnvelope
#else
        false
#endif
    }

    private var effectivePanelLevel: NSWindow.Level {
        // `.floating` cannot draw through the menu bar on this machine: the
        // window is clamped to visibleFrame even when its requested frame
        // uses screen.frame. The Debug prototype therefore opts into the
        // lowest public level that can actually touch the physical top edge;
        // production v2/v3 remain `.floating`.
#if DEBUG
        if isDebugTopAttachedEnvelope {
            return .statusBar
        }
#endif
        return .floating
    }

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
#if DEBUG
            if debugTopAttachedEnvelope {
                installDebugMouseMonitors()
            }
#endif
        }
    }

    private func makePanel(state: PlaybackState) -> CapsuleLyricsPanel {
        let frame: NSRect
#if DEBUG
        if debugTopAttachedEnvelope {
            frame = topAttachedEnvelopeFrame()
        } else {
            frame = restoredFrame(
                for: .collapsed,
                settings: settings ?? AppSettingsStore.shared
            )
        }
#else
        frame = restoredFrame(
            for: .collapsed,
            settings: settings ?? AppSettingsStore.shared
        )
#endif
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
        panel.hasShadow = !isDebugTopAttachedEnvelope
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = effectivePanelLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        let hostedView = NSHostingView(
            rootView: CapsuleLyricsView(state: state, windowController: self)
        )
#if DEBUG
        if debugTopAttachedEnvelope {
            let envelopeView = CapsuleEnvelopeHostingView(hostedView: hostedView)
            envelopeView.interactiveFrameProvider = { [weak self] in
                self?.debugIslandFrameInEnvelope() ?? .zero
            }
            envelopeHostingView = envelopeView
            panel.contentView = envelopeView
        } else {
            panel.contentView = hostedView
        }
#else
        panel.contentView = hostedView
#endif
        return panel
    }

    private func show() {
        guard let panel, let settings else { return }
        cancelHoverCollapse()
        removeOutsideClickMonitors()
        presentationState = .collapsed
        applyFrame(for: .collapsed, settings: settings)
        panel.level = effectivePanelLevel
        // A nonactivating panel may be ordered behind the main SwiftUI window
        // when it is created from a menu command.  Ordering it regardless
        // does not make it key or activate another application.
        panel.orderFrontRegardless()
        isVisible = true
#if DEBUG
        if debugTopAttachedEnvelope {
            installDebugMouseMonitors()
            updateDebugMousePassThrough()
        }
#endif
        settings.capsuleWindowWasVisible = true
        playbackState?.showCapsulePlayer = true
    }

    private func setPresentationState(_ newState: CapsulePresentationState) {
        guard newState != presentationState else { return }
        presentationState = newState
        if let settings {
            applyFrame(for: newState, settings: settings)
        }
        panel?.isMovable = isDebugTopAttachedEnvelope ? false : newState == .expanded
        panel?.isMovableByWindowBackground = isDebugTopAttachedEnvelope ? false : newState == .expanded
#if DEBUG
        if debugTopAttachedEnvelope {
            updateDebugMousePassThrough()
        }
#endif
    }

    private func applyFrame(for state: CapsulePresentationState, settings: AppSettingsStore) {
        guard let panel else { return }
#if DEBUG
        if debugTopAttachedEnvelope {
            let frame = topAttachedEnvelopeFrame()
            guard !panel.frame.equalTo(frame) else { return }
            isApplyingFrame = true
            panel.setFrame(frame, display: true, animate: false)
            isApplyingFrame = false
            return
        }
#endif
        let frame = restoredFrame(for: state, settings: settings)
        isApplyingFrame = true
        panel.setFrame(frame, display: true, animate: isVisible)
        isApplyingFrame = false
    }

#if DEBUG
    private func topAttachedEnvelopeFrame() -> NSRect {
        let screen = persistence.targetScreen(
            mainWindow: WindowStatePersistence.shared.attachedMainWindow
        ) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            return NSRect(origin: .zero, size: CapsuleDynamicIslandDarkV4.debugEnvelopeSize)
        }
        // Deliberately use screen.frame rather than visibleFrame. The
        // prototype's host window touches the physical top edge exactly.
        return CapsuleDynamicIslandDarkV4.topAttachedEnvelopeFrame(
            screenFrame: screen.frame
        )
    }

    private func debugIslandFrameInEnvelope() -> NSRect {
        let contentSize = panel?.contentView?.bounds.size ?? .zero
        let envelopeSize = contentSize.width > 0 && contentSize.height > 0
            ? contentSize
            : CapsuleDynamicIslandDarkV4.debugEnvelopeSize
        return CapsuleDynamicIslandDarkV4.topAttachedIslandFrame(
            for: presentationState,
            envelopeSize: envelopeSize
        )
    }

    private func debugIslandFrameInScreen() -> NSRect {
        guard let panel else { return .zero }
        let localFrame = debugIslandFrameInEnvelope()
        return panel.convertToScreen(localFrame)
    }

    private func installDebugMouseMonitors() {
        guard debugTopAttachedEnvelope else { return }
        if debugGlobalMouseMonitor == nil {
            debugGlobalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: .mouseMoved
            ) { [weak self] _ in
                self?.updateDebugMousePassThrough()
            }
        }
        if debugLocalMouseMonitor == nil {
            debugLocalMouseMonitor = NSEvent.addLocalMonitorForEvents(
                matching: .mouseMoved
            ) { [weak self] event in
                self?.updateDebugMousePassThrough()
                return event
            }
        }
    }

    private func removeDebugMouseMonitors() {
        if let debugGlobalMouseMonitor {
            NSEvent.removeMonitor(debugGlobalMouseMonitor)
            self.debugGlobalMouseMonitor = nil
        }
        if let debugLocalMouseMonitor {
            NSEvent.removeMonitor(debugLocalMouseMonitor)
            self.debugLocalMouseMonitor = nil
        }
    }

    private func updateDebugMousePassThrough() {
        guard debugTopAttachedEnvelope, let panel, isVisible else { return }
        let insideIsland = debugIslandFrameInScreen().contains(NSEvent.mouseLocation)
        if insideIsland {
            cancelHoverCollapse()
            if presentationState == .collapsed {
                pointerEntered()
            }
            panel.ignoresMouseEvents = false
        } else {
            if presentationState == .expanded {
                // The prototype demonstrates the continuous island morph on
                // pointer exit without changing the production controller's
                // outside-click semantics. The next mouse move over the
                // island can cancel the normal hover debounce.
                removeOutsideClickMonitors()
                setPresentationState(.hover)
            }
            if presentationState == .hover {
                pointerExited()
            }
            panel.ignoresMouseEvents = true
        }
    }
#endif

    private func restoredFrame(
        for state: CapsulePresentationState,
        settings: AppSettingsStore
    ) -> NSRect {
#if DEBUG
        return persistence.restoreFrame(
            for: state,
            settings: settings,
            mainWindow: WindowStatePersistence.shared.attachedMainWindow,
            debugAnchor: debugAnchor,
            presentation: activePresentation
        )
#else
        return persistence.restoreFrame(
            for: state,
            settings: settings,
            mainWindow: WindowStatePersistence.shared.attachedMainWindow,
            presentation: activePresentation
        )
#endif
    }

    private func savePosition() {
        guard let panel, let settings else { return }
#if DEBUG
        guard !debugTopAttachedEnvelope else { return }
        // Do not turn a comparison anchor's derived frame into the user's
        // normal centered horizontal offset.
        guard debugAnchor == .topCenter else { return }
#endif
        let screen = panel.screen
            ?? persistence.targetScreen(mainWindow: WindowStatePersistence.shared.attachedMainWindow)
        guard let screen else { return }
        let safe = persistence.clampTopFrame(panel.frame, screen: screen)
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
#if DEBUG
        if debugTopAttachedEnvelope {
            updateDebugMousePassThrough()
            return
        }
#endif
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
