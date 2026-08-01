import Foundation

/// Stable identifiers for the two renderers that can be selected for the
/// single retained floating lyrics panel.
public enum FloatingLyricsPresentationVersion: String, CaseIterable, Codable, Sendable {
    case legacyPanel = "floatingLyrics.legacyPanel.v1"
    case transparentV2 = "floatingLyrics.transparent.v2"

    public static let current: Self = .transparentV2
    public static let archived: [Self] = [.legacyPanel]

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .legacyPanel: return "旧版卡片"
        case .transparentV2: return "透明桌面歌词"
        }
    }
}

public enum FloatingLyricsSurfaceStyle: String, CaseIterable, Codable, Sendable {
    case ultraTransparent
    case lightMaterial

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ultraTransparent: return "超透明"
        case .lightMaterial: return "浅色材质"
        }
    }
}

/// Pure presentation helpers shared by the floating view and its contract
/// tests. This layer contains no playback clock and never mutates lyrics.
public struct FloatingLyricsSelection: Equatable, Sendable {
    public let visibleIndices: [Int]
    public let currentIndex: Int?
    public let autoScroll: Bool

    public init(visibleIndices: [Int], currentIndex: Int?, autoScroll: Bool) {
        self.visibleIndices = visibleIndices
        self.currentIndex = currentIndex
        self.autoScroll = autoScroll
    }
}

public enum FloatingLyricsPresentationHelper {
    public static func selection(
        lines: [LyricLine],
        currentIndex: Int?,
        isSynchronized: Bool,
        isPlaying: Bool,
        precedingCount: Int = 2,
        followingCount: Int = 2
    ) -> FloatingLyricsSelection {
        guard isSynchronized, !lines.isEmpty else {
            return FloatingLyricsSelection(
                visibleIndices: lines.indices.map { $0 },
                currentIndex: nil,
                autoScroll: false
            )
        }

        // Before the first timed line there is no current lyric yet. Keep a
        // small leading projection instead of expanding to the full document;
        // the floating window must remain bounded even during an intro.
        guard let currentIndex, lines.indices.contains(currentIndex) else {
            let upper = min(lines.count - 1, max(0, followingCount))
            return FloatingLyricsSelection(
                visibleIndices: Array(0...upper),
                currentIndex: nil,
                autoScroll: false
            )
        }

        let lower = max(0, currentIndex - max(0, precedingCount))
        let upper = min(lines.count - 1, currentIndex + max(0, followingCount))
        return FloatingLyricsSelection(
            visibleIndices: Array(lower...upper),
            currentIndex: currentIndex,
            // A paused player still needs the current line to remain in view;
            // the helper never advances time and only describes the target.
            autoScroll: true
        )
    }

    /// Kept deliberately small: the floating window never owns a timer. It
    /// is useful for pure contracts and for callers that need to reason about
    /// a paused state without starting a second playback clock.
    public static func advance(
        currentTime: TimeInterval,
        elapsed: TimeInterval,
        isPlaying: Bool
    ) -> TimeInterval {
        guard isPlaying, elapsed.isFinite, elapsed > 0 else { return currentTime }
        return currentTime + elapsed
    }
}
