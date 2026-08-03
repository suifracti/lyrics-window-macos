import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct CurrentSongOperationsContract {
    static func main() {
        let noLyrics = CurrentSongOperationSnapshot(
            title: "あやふや",
            artist: "みさき",
            lyricsState: .noMatch,
            lyricsSource: nil,
            lyricsVersionID: nil,
            isSynchronized: false,
            isLyricsNoSelection: false,
            hasTranslationSelection: false,
            translationVersionCount: 0
        )
        require(noLyrics.lyricsStatusLabel == "暂无歌词", "no-match should be content-first")
        require(noLyrics.primaryLyricsAction == .importOrCreate, "no-match should expose import/create")
        require(noLyrics.translationStatusLabel == "无翻译版本", "no translation selection must be explicit")

        let notUsed = CurrentSongOperationSnapshot(
            title: "水曜日の約束",
            artist: "Kawasaki.Rio",
            lyricsState: .noSelection,
            lyricsSource: .qqExperimental,
            lyricsVersionID: UUID(),
            isSynchronized: false,
            isLyricsNoSelection: true,
            hasTranslationSelection: false,
            translationVersionCount: 2
        )
        require(notUsed.lyricsStatusLabel == "本次播放不使用", "session no-selection must not mean deletion")
        require(notUsed.lyricsSourceLabel == "QQ音乐（实验）", "source must remain visible")
        require(notUsed.primaryLyricsAction == .chooseVersion, "no-selection should offer version recovery")

        let loaded = CurrentSongOperationSnapshot(
            title: "恋風",
            artist: "Lilas",
            lyricsState: .synchronized,
            lyricsSource: .lrclib,
            lyricsVersionID: UUID(),
            isSynchronized: true,
            isLyricsNoSelection: false,
            hasTranslationSelection: true,
            translationVersionCount: 1
        )
        require(loaded.lyricsStatusLabel == "已加载 · 同步歌词", "loaded status should include timing")
        require(loaded.lyricsSourceLabel == "LRCLIB", "provider source should be readable")
        require(loaded.primaryLyricsAction == .edit, "loaded lyrics should expose edit")
        require(loaded.translationStatusLabel == "已选择翻译", "selected translation should differ from no version")

        print("current song operations contract: PASS")
    }
}
