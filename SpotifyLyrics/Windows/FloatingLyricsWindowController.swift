import AppKit
import Combine
import SwiftUI

private final class FloatingLyricsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns exactly one retained floating panel. Hiding orders it out instead of
/// closing or releasing the panel, so repeated toggles cannot create a second
/// window or a second SwiftUI state tree.
@MainActor
final class FloatingLyricsWindowController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isVisible = false
    @Published private(set) var interactionMode: FloatingLyricsInteractionMode = .interactive

    private let persistence = FloatingLyricsWindowPersistence.shared
    private var panel: FloatingLyricsPanel?
    private weak var playbackState: PlaybackState?
    private var settings: AppSettingsStore?
    private var settingsCancellables: Set<AnyCancellable> = []
    private var screenChangeObserver: NSObjectProtocol?
    private var didRestore = false

    override init() {
        super.init()
        observeScreenChanges()
    }

    deinit {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
        settingsCancellables.forEach { $0.cancel() }
    }

    func toggle(state: PlaybackState, settings: AppSettingsStore) {
        configure(state: state, settings: settings)
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func restoreIfConfigured(state: PlaybackState, settings: AppSettingsStore) {
        configure(state: state, settings: settings)
        guard !didRestore else { return }
        didRestore = true
        guard settings.restoreWindowState, settings.floatingWindowWasVisible else { return }
        show()
    }

    func setInteractionMode(_ mode: FloatingLyricsInteractionMode) {
        interactionMode = mode
        settings?.floatingWindowInteractionMode = mode
        applyInteractionMode()
    }

    func toggleInteractionMode() {
        switch interactionMode {
        case .interactive: setInteractionMode(.locked)
        case .locked, .passThrough: setInteractionMode(.interactive)
        }
    }

    func close() {
        panel?.orderOut(nil)
        isVisible = false
        settings?.floatingWindowWasVisible = false
        playbackState?.showFloatingWindow = false
    }

    func restoreInteractiveMode() {
        setInteractionMode(.interactive)
    }

    private func configure(state: PlaybackState, settings: AppSettingsStore) {
        playbackState = state
        self.settings = settings

        if panel == nil {
            let panel = makePanel(state: state, settings: settings)
            self.panel = panel
            interactionMode = settings.floatingWindowInteractionMode
            applyInteractionMode()
        }

        if settingsCancellables.isEmpty {
            settings.$floatingWindowAlwaysOnTop
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.applyWindowLevel() }
                .store(in: &settingsCancellables)
            settings.$floatingWindowInteractionModeRawValue
                .receive(on: RunLoop.main)
                .sink { [weak self] rawValue in
                    guard let self,
                          let mode = FloatingLyricsInteractionMode(rawValue: rawValue),
                          mode != self.interactionMode else { return }
                    self.interactionMode = mode
                    self.applyInteractionMode()
                }
                .store(in: &settingsCancellables)
            settings.$floatingWindowOpacity
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.applyOpacity() }
                .store(in: &settingsCancellables)
        }
    }

    private func makePanel(state: PlaybackState, settings: AppSettingsStore) -> FloatingLyricsPanel {
        let frame = persistence.restoreFrame(settings: settings)
        let panel = FloatingLyricsPanel(
            contentRect: frame,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = persistence.minimumSize
        panel.maxSize = persistence.maximumSize
        panel.contentView = NSHostingView(
            rootView: FloatingLyricsView(state: state, windowController: self)
        )
        applyWindowLevel(to: panel, settings: settings)
        panel.alphaValue = CGFloat(min(1, max(0.45, settings.floatingWindowOpacity)))
        return panel
    }

    private func show() {
        guard let panel else { return }
        if let settings {
            panel.setFrame(persistence.restoreFrame(settings: settings), display: false)
            applyWindowLevel(to: panel, settings: settings)
            settings.floatingWindowWasVisible = true
        }
        applyInteractionMode()
        panel.orderFrontRegardless()
        isVisible = true
        playbackState?.showFloatingWindow = true
    }

    private func hide() {
        guard let panel else { return }
        saveFrame(panel)
        panel.orderOut(nil)
        isVisible = false
        settings?.floatingWindowWasVisible = false
        playbackState?.showFloatingWindow = false
    }

    private func applyInteractionMode() {
        guard let panel else { return }
        let editable = interactionMode == .interactive
        panel.isMovable = editable
        panel.isMovableByWindowBackground = editable
        if editable {
            panel.styleMask.insert(.resizable)
        } else {
            panel.styleMask.remove(.resizable)
        }
        panel.ignoresMouseEvents = interactionMode == .passThrough
        if !editable, panel.isKeyWindow {
            panel.resignKey()
        }
    }

    private func applyWindowLevel() {
        guard let panel, let settings else { return }
        applyWindowLevel(to: panel, settings: settings)
    }

    private func applyWindowLevel(to panel: NSPanel, settings: AppSettingsStore) {
        // `.floating` stays below system alerts and menus; no statusBar or
        // modalPanel level is used for the lyric window.
        panel.level = settings.floatingWindowAlwaysOnTop ? .floating : .normal
    }

    private func applyOpacity() {
        guard let panel, let settings else { return }
        panel.alphaValue = CGFloat(min(1, max(0.45, settings.floatingWindowOpacity)))
    }

    private func saveFrame(_ panel: NSWindow) {
        guard let settings else { return }
        persistence.save(frame: panel.frame, settings: settings)
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        saveFrame(panel)
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel else { return }
        let safe = persistence.clamp(panel.frame, to: panel.screen?.visibleFrame ?? panel.frame)
        if safe != panel.frame {
            panel.setFrame(safe, display: false)
        }
        saveFrame(panel)
    }

    func windowWillClose(_ notification: Notification) {
        // A user/system close is treated as a hide. The retained panel can be
        // reopened without creating another controller or state tree.
        if let panel { saveFrame(panel) }
        isVisible = false
        settings?.floatingWindowWasVisible = false
        playbackState?.showFloatingWindow = false
    }

    private func observeScreenChanges() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.clampToCurrentScreen()
            }
        }
    }

    private func clampToCurrentScreen() {
        guard let panel else { return }
        let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
        guard let visible else { return }
        let safe = persistence.clamp(panel.frame, to: visible)
        if safe != panel.frame {
            panel.setFrame(safe, display: true)
        }
        saveFrame(panel)
    }
}
