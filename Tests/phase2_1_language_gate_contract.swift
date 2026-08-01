import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct Phase2_1LanguageGateContract {
    static func main() {
        expect(LyricsLanguageGate.allowsJapaneseReadings(language: "ja", text: "言葉だけ"), "explicit Japanese language may allow Han-only lyrics")
        expect(LyricsLanguageGate.allowsJapaneseReadings(language: "ja", text: "夜の窓"), "Japanese kana/kanji lyrics are allowed")
        expect(!LyricsLanguageGate.allowsJapaneseReadings(language: nil, text: "夜窓雨"), "unknown Han-only text must fail closed")
        expect(LyricsLanguageGate.allowsJapaneseReadings(language: nil, text: "夜の窓に雨が落ちるよ"), "unknown Japanese text with Hiragana is allowed")
        expect(!LyricsLanguageGate.allowsJapaneseReadings(language: "zh-Hans", text: "夜的窗边下着雨"), "Chinese lyrics must not show Japanese readings")
        expect(!LyricsLanguageGate.allowsJapaneseReadings(language: "en", text: "Hello world"), "English lyrics must not show Japanese readings")
        expect(!LyricsLanguageGate.allowsJapaneseReadings(language: "ko", text: "오늘 밤"), "Korean lyrics must not show Japanese readings")
        expect(!LyricsLanguageGate.allowsJapaneseReadings(language: "und", text: "言葉"), "und Han-only text must fail closed")
        expect(LyricsLanguageGate.allowsJapaneseReadings(language: "ja", text: "SNS と歌う"), "mixed Japanese/Latin lyrics remain Japanese")
        print("phase2_1_language_gate_contract: PASS")
    }
}
