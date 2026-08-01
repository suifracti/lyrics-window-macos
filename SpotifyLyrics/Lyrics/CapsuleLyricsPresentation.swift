import Foundation

public enum CapsulePresentationState: Equatable, Sendable {
    case collapsed
    case hover
    case expanded
}

/// The deliberately small projection consumed by the top capsule.  Playback
/// and lyric sessions remain the owners of the clock and current-line lookup;
/// this type only chooses the two rows the capsule is allowed to render.
public struct CapsuleLyricsSelection: Equatable, Sendable {
    public let current: LyricLine?
    public let following: LyricLine?
    public let isSynchronized: Bool
    public let status: String?

    public init(
        current: LyricLine?,
        following: LyricLine?,
        isSynchronized: Bool,
        status: String?
    ) {
        self.current = current
        self.following = following
        self.isSynchronized = isSynchronized
        self.status = status
    }
}

public enum CapsuleLyricsPresentation {
    /// Projects only the current and following line from the already shared
    /// current-line index.  It never derives an index from time and never
    /// treats the first plain-text line as a pseudo-current line.
    public static func selection(
        lines: [LyricLine],
        currentIndex: Int?,
        isSynchronized: Bool,
        state: LyricsLoadState
    ) -> CapsuleLyricsSelection {
        switch state {
        case .loading:
            return empty(isSynchronized: false, status: "正在加载歌词…")
        case .noLyrics:
            return empty(isSynchronized: false, status: "暂无歌词")
        case .noMatch:
            return empty(isSynchronized: false, status: "未找到歌词")
        case .candidates:
            return empty(isSynchronized: false, status: "请回主窗口选择歌词")
        case .failed(_, let failure):
            return empty(isSynchronized: false, status: failure.userFacingMessage)
        case .alignmentQueued, .alignmentRunning:
            return empty(isSynchronized: false, status: "未排轴")
        case .alignmentPreview:
            return empty(isSynchronized: false, status: "排轴预览")
        case .idle:
            return empty(isSynchronized: false, status: "等待歌词")
        case .mockPreview:
            return empty(isSynchronized: false, status: "Mock Preview")
        case .loaded:
            break
        }

        // A legacy/manual record can carry an optimistic synchronized flag
        // while all of its lines still have the zero timestamp used by plain
        // text.  The capsule is a live playback surface, so it must fail
        // closed rather than turn the first row into pseudo-sync.
        guard isSynchronized, hasTimingEvidence(lines) else {
            return CapsuleLyricsSelection(
                current: nil,
                following: nil,
                isSynchronized: false,
                status: "纯文本 / 未排轴"
            )
        }

        guard let currentIndex, lines.indices.contains(currentIndex) else {
            return CapsuleLyricsSelection(
                current: nil,
                following: nil,
                isSynchronized: true,
                status: "前奏"
            )
        }

        let followingIndex = currentIndex + 1
        return CapsuleLyricsSelection(
            current: lines[currentIndex],
            following: lines.indices.contains(followingIndex) ? lines[followingIndex] : nil,
            isSynchronized: true,
            status: nil
        )
    }

    private static func empty(isSynchronized: Bool, status: String) -> CapsuleLyricsSelection {
        CapsuleLyricsSelection(
            current: nil,
            following: nil,
            isSynchronized: isSynchronized,
            status: status
        )
    }

    private static func hasTimingEvidence(_ lines: [LyricLine]) -> Bool {
        lines.contains { line in
            if line.timestamp.isFinite, line.timestamp > 0 {
                return true
            }
            if let endTime = line.endTime, endTime.isFinite, endTime > 0 {
                return true
            }
            return false
        }
    }
}
