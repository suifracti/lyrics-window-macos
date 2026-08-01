import AppKit
import Foundation

/// Frame persistence for the floating panel. The stored screen token is only
/// a recovery hint; every restore is clamped against a currently connected
/// visible frame before the panel is shown.
@MainActor
final class FloatingLyricsWindowPersistence {
    static let shared = FloatingLyricsWindowPersistence()

    let minimumSize = NSSize(width: 360, height: 120)
    let maximumSize = NSSize(width: 960, height: 640)

    private init() {}

    func defaultFrame() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 620, height: 220)
        return NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    func restoreFrame(settings: AppSettingsStore) -> NSRect {
        let requested: NSRect
        if settings.restoreWindowState,
           let saved = settings.savedFloatingWindowFrame {
            let parsed = NSRectFromString(saved)
            requested = isUsable(parsed) ? parsed : defaultFrame()
        } else {
            requested = defaultFrame()
        }

        let screen = screen(for: settings.savedFloatingWindowScreenID)
            ?? screen(containing: requested)
            ?? NSScreen.main
            ?? NSScreen.screens.first
        return clamp(requested, to: screen?.visibleFrame ?? defaultFrame())
    }

    func save(frame: NSRect, settings: AppSettingsStore) {
        guard settings.restoreWindowState, isUsable(frame) else { return }
        let screen = screen(containing: frame) ?? NSScreen.main
        let safeFrame = clamp(frame, to: screen?.visibleFrame ?? defaultFrame())
        settings.saveFloatingWindowFrame(
            NSStringFromRect(safeFrame),
            screenID: screen.map(screenIdentifier)
        )
    }

    func clamp(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else { return defaultFrame() }
        let width = min(max(frame.width, minimumSize.width), min(maximumSize.width, visibleFrame.width))
        let height = min(max(frame.height, minimumSize.height), min(maximumSize.height, visibleFrame.height))
        let x = min(
            max(frame.minX, visibleFrame.minX),
            max(visibleFrame.minX, visibleFrame.maxX - width)
        )
        let y = min(
            max(frame.minY, visibleFrame.minY),
            max(visibleFrame.minY, visibleFrame.maxY - height)
        )
        return NSRect(x: x, y: y, width: width, height: height)
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

    private func screen(containing frame: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
        }
    }

    private func isUsable(_ frame: NSRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width.isFinite && frame.height.isFinite
            && frame.width >= 1 && frame.height >= 1
    }
}

private extension CGRect {
    var area: CGFloat { max(0, width) * max(0, height) }
}
