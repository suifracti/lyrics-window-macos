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

        let preview = TranslationCandidatePreviewEvidence.build(
            sourceLines: [
                LyricLine(timestamp: 12.5, originalText: "夜の窓に雨が落ちる"),
                LyricLine(timestamp: 28, originalText: "遠い街の灯りを見ている")
            ],
            translations: [
                IndexedTranslationPreview(lineIndex: 1, text: "望着远方城市的灯火"),
                IndexedTranslationPreview(lineIndex: 0, text: "雨落在夜晚的窗边")
            ],
            isSynchronized: true
        )
        require(preview.count == 2, "translation preview must preserve every source line")
        require(preview[0].lineIndex == 0, "translation preview must follow source order")
        require(preview[0].originalText == "夜の窓に雨が落ちる", "translation preview lost original evidence")
        require(preview[0].translatedText == "雨落在夜晚的窗边", "translation preview mapped the wrong translated line")
        require(preview[0].timestamp == 12.5, "translation preview lost timeline evidence")
        require(preview[0].hasTiming, "synchronized preview must expose timing")

        let recoveryQuery = LyricsRecoveryPresentation.primaryWebQuery(
            track: Track(title: "  One Last Kiss  ", artist: " 宇多田ヒカル ", album: "", duration: 0)
        )
        require(recoveryQuery == "One Last Kiss 宇多田ヒカル", "web recovery query must be ready to copy or open")

        print("current song operations contract: PASS")
    }
}
