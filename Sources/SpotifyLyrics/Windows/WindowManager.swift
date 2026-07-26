import SwiftUI
import AppKit

// Floating transparent borderless window controller
public class WindowManager: ObservableObject {
    public static let shared = WindowManager()

    private var floatingWindow: NSWindow?
    private var capsuleWindow: NSWindow?
    private var fullScreenWindow: NSWindow?

    @MainActor
    public func toggleFloatingWindow(state: PlaybackState) {
        if let window = floatingWindow, window.isVisible {
            window.orderOut(nil)
            state.showFloatingWindow = false
        } else {
            if floatingWindow == nil {
                let window = NSWindow(
                    contentRect: NSRect(x: 100, y: 100, width: 600, height: 180),
                    styleMask: [.borderless, .resizable],
                    backing: .buffered,
                    defer: false
                )
                window.isOpaque = false
                window.backgroundColor = .clear
                window.level = .floating
                window.isMovableByWindowBackground = true
                window.hasShadow = true
                window.contentView = NSHostingView(rootView: FloatingLyricsView().environmentObject(state))
                floatingWindow = window
            }
            floatingWindow?.makeKeyAndOrderFront(nil)
            state.showFloatingWindow = true
        }
    }

    @MainActor
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
                window.contentView = NSHostingView(rootView: CapsulePlayerView().environmentObject(state))
                capsuleWindow = window
            }
            capsuleWindow?.makeKeyAndOrderFront(nil)
            state.showCapsulePlayer = true
        }
    }

    @MainActor
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
                window.contentView = NSHostingView(rootView: FullScreenLyricsView().environmentObject(state))
                fullScreenWindow = window
            }
            fullScreenWindow?.makeKeyAndOrderFront(nil)
            state.showFullScreen = true
        }
    }
}
