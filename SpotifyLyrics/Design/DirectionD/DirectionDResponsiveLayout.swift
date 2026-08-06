import SwiftUI

/// Responsive Layout Mode for Direction D Main Window (Phase 3.4).
public enum DirectionDLayoutMode: String, CaseIterable, Sendable {
    case wide = "wide"
    case small = "small"
    case lyricsFocus = "lyricsFocus"

    public var isSmall: Bool { self == .small }
    public var isWide: Bool { self == .wide }
    public var isFocus: Bool { self == .lyricsFocus }
}

/// Responsive Layout Resolver for Direction D Main Window.
public struct DirectionDResponsiveLayout {
    public static let wideBreakpoint: CGFloat = 900
    public static let smallBreakpoint: CGFloat = 580

    /// Resolves the effective layout mode based on container dimensions and user override.
    public static func resolveMode(
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        userOverrideMode: DirectionDLayoutMode? = nil
    ) -> DirectionDLayoutMode {
        if let overrideMode = userOverrideMode {
            return overrideMode
        }

        if availableWidth <= smallBreakpoint {
            return .small
        } else if availableWidth >= wideBreakpoint {
            return .wide
        } else {
            // Mid-width (580px - 900px): Uses Lyrics Focus or Small
            return availableHeight >= availableWidth ? .lyricsFocus : .wide
        }
    }
}
