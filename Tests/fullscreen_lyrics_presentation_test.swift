import Foundation

@main
struct FullscreenLyricsPresentationContract {
    static func main() {
        let identity = TrackIdentity(
            title: "恋風",
            artist: "Lilas",
            album: "Test",
            duration: 120,
            spotifyTrackID: "track-test"
        )
        let lines = [
            LyricLine(timestamp: 0, originalText: "前奏"),
            LyricLine(timestamp: 10, originalText: "一行目", endTime: 18),
            LyricLine(timestamp: 22, originalText: "二行目", endTime: 30),
            LyricLine(timestamp: 35, originalText: "三行目", endTime: 45),
            LyricLine(timestamp: 50, originalText: "四行目", endTime: 60)
        ]
        let document = LyricsDocument(
            identity: identity,
            lines: lines,
            isSynchronized: true,
            source: .lrclib
        )

        let intro = FullScreenLyricsPresentation.surface(
            lines: lines,
            state: .loaded(document),
            isSynchronized: true,
            currentIndex: nil,
            visibleRowBudget: 4
        )
        precondition(intro == .synchronized(currentIndex: nil, visibleIndices: []))

        let active = FullScreenLyricsPresentation.surface(
            lines: lines,
            state: .loaded(document),
            isSynchronized: true,
            currentIndex: 2,
            visibleRowBudget: 4
        )
        precondition(active == .synchronized(currentIndex: 2, visibleIndices: [1, 2, 3, 4]))

        let plainLines = lines.map {
            LyricLine(timestamp: 0, originalText: $0.originalText)
        }
        let plainDocument = LyricsDocument(
            identity: identity,
            lines: plainLines,
            isSynchronized: true,
            source: .manualCreate
        )
        let plain = FullScreenLyricsPresentation.surface(
            lines: plainLines,
            state: .loaded(plainDocument),
            isSynchronized: true,
            currentIndex: 0,
            visibleRowBudget: 4
        )
        precondition(plain == .plainText(status: "纯文本 / 未排轴", visibleIndices: [0, 1, 2, 3, 4]))

        let queued = FullScreenLyricsPresentation.surface(
            lines: lines,
            state: .alignmentQueued(identity, document),
            isSynchronized: true,
            currentIndex: 2,
            visibleRowBudget: 4
        )
        precondition(queued == .plainText(status: "纯文本 / 未排轴", visibleIndices: [0, 1, 2, 3, 4]))

        let failed = FullScreenLyricsPresentation.surface(
            lines: [],
            state: .noMatch(identity),
            isSynchronized: false,
            currentIndex: nil,
            visibleRowBudget: 4
        )
        precondition(failed == .status(title: "暂无歌词", detail: "自动补全未找到可用歌词"))

        print("fullscreen lyrics presentation contract passed")
    }
}
