import AppKit

#if DEBUG
/// Internal-only comparison anchors for design-review builds. This type and
/// its non-center cases are not compiled into Release.
enum CapsuleDebugAnchor: String, CaseIterable {
    case topLeft
    case topCenter
    case topRight
}
#endif

/// Top-safe-area positioning for the capsule.  Unlike the floating lyrics
/// window this stores no arbitrary frame: the three presentation sizes are
/// fixed and only the horizontal offset from the target display's center is
/// persisted.  The persisted screenID is only a recovery hint; it never
/// replaces the live main-window screen selection.
@MainActor
final class CapsuleLyricsWindowPersistence {
    static let shared = CapsuleLyricsWindowPersistence()

    let collapsedSize = NSSize(width: 360, height: 46)
    let hoverSize = NSSize(width: 520, height: 82)
    let expandedSize = NSSize(width: 620, height: 220)
    private let topInset: CGFloat = 10

    private init() {}

    func size(for state: CapsulePresentationState) -> NSSize {
        switch state {
        case .collapsed: return collapsedSize
        case .hover: return hoverSize
        case .expanded: return expandedSize
        }
    }

    func screenIdentifier(_ screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        return "name-\(screen.localizedName)-\(NSStringFromRect(screen.frame))"
    }

    func screen(for identifier: String?) -> NSScreen? {
        guard let identifier, !identifier.isEmpty else { return nil }
        return NSScreen.screens.first { screenIdentifier($0) == identifier }
    }

    func targetScreen(mainWindow: NSWindow?) -> NSScreen? {
        mainWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    func frame(
        for state: CapsulePresentationState,
        screen: NSScreen,
        horizontalOffset: CGFloat
    ) -> NSRect {
        let visible = screen.visibleFrame
        let requested = size(for: state)
        let width = min(requested.width, max(1, visible.width))
        let height = min(requested.height, max(1, visible.height))
        let x = visible.midX - width / 2 + horizontalOffset
        return makeTopFrame(
            x: x,
            height: height,
            width: width,
            visible: visible,
            topSafeInset: topSafeInset(for: screen)
        )
    }

#if DEBUG
    func frame(
        for state: CapsulePresentationState,
        screen: NSScreen,
        horizontalOffset: CGFloat,
        debugAnchor: CapsuleDebugAnchor
    ) -> NSRect {
        let visible = screen.visibleFrame
        let requested = size(for: state)
        let width = min(requested.width, max(1, visible.width))
        let height = min(requested.height, max(1, visible.height))
        let x: CGFloat
        switch debugAnchor {
        case .topLeft:
            x = visible.minX + horizontalOffset
        case .topCenter:
            x = visible.midX - width / 2 + horizontalOffset
        case .topRight:
            x = visible.maxX - width - horizontalOffset
        }
        return makeTopFrame(
            x: x,
            height: height,
            width: width,
            visible: visible,
            topSafeInset: topSafeInset(for: screen)
        )
    }
#endif

    func restoreFrame(
        for state: CapsulePresentationState,
        settings: AppSettingsStore,
        mainWindow: NSWindow?
    ) -> NSRect {
        // A live main-window screen always wins.  The saved screen ID is used
        // only while the SwiftUI main window has not attached yet, followed by
        // the documented NSScreen.main/first fallbacks.
        let screen = mainWindow?.screen
            ?? screen(for: settings.capsuleWindowScreenID)
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            return NSRect(origin: .zero, size: size(for: state))
        }
        return frame(
            for: state,
            screen: screen,
            horizontalOffset: CGFloat(settings.capsuleWindowHorizontalOffset)
        )
    }

#if DEBUG
    func restoreFrame(
        for state: CapsulePresentationState,
        settings: AppSettingsStore,
        mainWindow: NSWindow?,
        debugAnchor: CapsuleDebugAnchor
    ) -> NSRect {
        let screen = mainWindow?.screen
            ?? screen(for: settings.capsuleWindowScreenID)
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            return NSRect(origin: .zero, size: size(for: state))
        }
        return frame(
            for: state,
            screen: screen,
            horizontalOffset: CGFloat(settings.capsuleWindowHorizontalOffset),
            debugAnchor: debugAnchor
        )
    }
#endif

    private func topSafeInset(for screen: NSScreen) -> CGFloat {
        max(topInset, screen.safeAreaInsets.top)
    }

    private func makeTopFrame(
        x: CGFloat,
        height: CGFloat,
        width: CGFloat,
        visible: NSRect,
        topSafeInset: CGFloat
    ) -> NSRect {
        let y = visible.maxY - height - topSafeInset
        return clampTopFrame(
            NSRect(x: x, y: y, width: width, height: height),
            to: visible,
            topInset: topSafeInset
        )
    }

    func horizontalOffset(for frame: NSRect, screen: NSScreen) -> CGFloat {
        frame.midX - screen.visibleFrame.midX
    }

    func clampTopFrame(_ frame: NSRect, to visible: NSRect) -> NSRect {
        clampTopFrame(frame, to: visible, topInset: topInset)
    }

    func clampTopFrame(_ frame: NSRect, screen: NSScreen) -> NSRect {
        clampTopFrame(
            frame,
            to: screen.visibleFrame,
            topInset: topSafeInset(for: screen)
        )
    }

    private func clampTopFrame(_ frame: NSRect, to visible: NSRect, topInset: CGFloat) -> NSRect {
        guard visible.width > 0, visible.height > 0 else { return frame }
        let width = min(max(1, frame.width), visible.width)
        let height = min(max(1, frame.height), visible.height)
        let x = min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - width))
        let y = min(
            max(frame.minY, visible.minY),
            max(visible.minY, visible.maxY - height - topInset)
        )
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
