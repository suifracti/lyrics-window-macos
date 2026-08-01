import Foundation

/// The fullscreen surface is a deliberately small projection.  It carries no
/// playback clock and no lyric document copy beyond the row indices that the
/// view is allowed to render for this pass.
public enum FullScreenLyricsSurface: Equatable, Sendable {
    case synchronized(currentIndex: Int?, visibleIndices: [Int])
    case plainText(status: String, visibleIndices: [Int])
    case status(title: String, detail: String)
}

public enum FullScreenLyricsPresentation {
    /// Returns true only when a lyric document contains evidence of a real
    /// timeline.  A synchronized flag with every timestamp at zero is not
    /// enough to make the first line look like the current line.
    public static func hasTimingEvidence(_ lines: [LyricLine]) -> Bool {
        lines.contains { line in
            if line.timestamp.isFinite, line.timestamp > 0 { return true }
            if let endTime = line.endTime,
               endTime.isFinite,
               endTime > 0 { return true }
            return false
        }
    }

    /// Projects the shared live lyrics into either a bounded synchronized
    /// window, a manually scrollable plain-text document, or a small status
    /// state.  The caller supplies `currentIndex` from PlaybackState; this
    /// method never derives one from time and never averages timestamps.
    public static func surface(
        lines: [LyricLine],
        state: LyricsLoadState,
        isSynchronized: Bool,
        currentIndex: Int?,
        visibleRowBudget: Int = 6
    ) -> FullScreenLyricsSurface {
        switch state {
        case .loaded:
            guard !lines.isEmpty else {
                return .status(title: "暂无歌词", detail: "当前歌词版本没有可显示的行")
            }
            guard isSynchronized, hasTimingEvidence(lines) else {
                return .plainText(status: "纯文本 / 未排轴", visibleIndices: allIndices(for: lines))
            }
            return synchronizedSurface(
                lines: lines,
                currentIndex: currentIndex,
                visibleRowBudget: visibleRowBudget
            )

        case .alignmentQueued, .alignmentRunning, .alignmentPreview:
            guard !lines.isEmpty else {
                return .status(title: "暂无歌词", detail: "歌词正在等待排轴")
            }
            // A queued, running, or unconfirmed preview is intentionally
            // shown as ordinary text.  Preview timestamps are not live truth.
            return .plainText(status: "纯文本 / 未排轴", visibleIndices: allIndices(for: lines))

        case .loading:
            return .status(title: "正在加载歌词…", detail: "正在等待共享歌词会话")
        case .noLyrics:
            return .status(title: "暂无歌词", detail: "当前来源没有歌词正文")
        case .noMatch:
            return .status(title: "暂无歌词", detail: "自动补全未找到可用歌词")
        case .candidates:
            return .status(title: "需要选择歌词", detail: "请回主窗口选择匹配的歌词")
        case .failed(_, let failure):
            return .status(title: "歌词加载失败", detail: failure.userFacingMessage)
        case .idle:
            return .status(title: "等待歌曲", detail: "等待 Spotify 当前歌曲")
        case .mockPreview:
            return .status(title: "预览模式", detail: "全屏歌词只显示真实 live 歌词")
        }
    }

    private static func synchronizedSurface(
        lines: [LyricLine],
        currentIndex: Int?,
        visibleRowBudget: Int
    ) -> FullScreenLyricsSurface {
        let budget = max(1, visibleRowBudget)
        let safeIndex = currentIndex.flatMap { lines.indices.contains($0) ? $0 : nil }

        guard let safeIndex else {
            return .synchronized(
                currentIndex: nil,
                // Before the first timed line there is no trustworthy current
                // lyric. Keep the canvas empty instead of showing the first
                // line early during an intro or instrumental passage.
                visibleIndices: []
            )
        }

        let before = max(1, budget / 3)
        let after = max(1, budget - before - 1)
        let lower = max(0, safeIndex - before)
        let upper = min(lines.count, safeIndex + after + 1)
        return .synchronized(
            currentIndex: safeIndex,
            visibleIndices: Array(lower..<upper)
        )
    }

    private static func allIndices(for lines: [LyricLine]) -> [Int] {
        Array(lines.indices)
    }
}
