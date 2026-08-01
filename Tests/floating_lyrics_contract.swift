import Foundation

@main
struct FloatingLyricsContract {
    static func main() {
        let lines = (0..<7).map { index in
            LyricLine(timestamp: TimeInterval(index * 10), originalText: "line \(index)")
        }

        let synchronized = FloatingLyricsPresentationHelper.selection(
            lines: lines,
            currentIndex: 3,
            isSynchronized: true,
            isPlaying: true
        )
        precondition(synchronized.currentIndex == 3)
        precondition(Set(synchronized.visibleIndices) == Set(1...5))
        precondition(synchronized.autoScroll)

        let plain = FloatingLyricsPresentationHelper.selection(
            lines: lines,
            currentIndex: 3,
            isSynchronized: false,
            isPlaying: true
        )
        precondition(plain.currentIndex == nil)
        precondition(!plain.autoScroll)

        let beforeFirstLine = FloatingLyricsPresentationHelper.selection(
            lines: lines,
            currentIndex: nil,
            isSynchronized: true,
            isPlaying: true
        )
        precondition(beforeFirstLine.currentIndex == nil)
        precondition(beforeFirstLine.visibleIndices == Array(0...2))
        precondition(!beforeFirstLine.autoScroll)

        let paused = FloatingLyricsPresentationHelper.advance(
            currentTime: 12,
            elapsed: 0.2,
            isPlaying: false
        )
        precondition(paused == 12)

        let active = FloatingLyricsPresentationHelper.selection(
            lines: lines,
            currentIndex: LyricsTimeline.activeLineIndex(
                lines: lines,
                time: 35,
                isSynchronized: true
            ),
            isSynchronized: true,
            isPlaying: true
        )
        precondition(active.currentIndex == LyricsTimeline.activeLineIndex(
            lines: lines,
            time: 35,
            isSynchronized: true
        ))

        precondition(LyricsTimeline.activeLineIndex(lines: lines, time: -1, isSynchronized: true) == nil)
        let repeated = [
            LyricLine(timestamp: 0, originalText: "zero"),
            LyricLine(timestamp: 10, originalText: "first"),
            LyricLine(timestamp: 10, originalText: "second")
        ]
        precondition(LyricsTimeline.activeLineIndex(lines: repeated, time: 10, isSynchronized: true) == 2)
        precondition(LyricsTimeline.activeLineIndex(lines: lines, time: 35, isSynchronized: false) == nil)

        print("floating lyrics pure-data contract passed")
    }
}
