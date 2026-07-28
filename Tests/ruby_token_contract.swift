import Foundation

private struct FixtureJapaneseEngine: JapaneseMorphologyEngine {
    func tokenize(_ text: String) throws -> [JapaneseMorphologyToken] {
        [
            JapaneseMorphologyToken(
                originalText: "言われ",
                readingKatakana: "イワレ",
                lemma: "言う",
                partOfSpeech: "動詞"
            ),
            JapaneseMorphologyToken(
                originalText: "た",
                readingKatakana: "タ",
                lemma: "た",
                partOfSpeech: "助動詞"
            ),
            JapaneseMorphologyToken(
                originalText: "夜",
                readingKatakana: "ヨル",
                lemma: "夜",
                partOfSpeech: "名詞"
            )
        ]
    }
}

@main
struct RubyTokenContract {
    static func main() {
        let result = JapaneseReadingPipeline.analyze(
            originalText: "言われた夜",
            engine: FixtureJapaneseEngine()
        )
        let tokens = result.tokens.map(LyricRubyToken.init(readingToken:))

        precondition(tokens.map(\.surface) == ["言われ", "た", "夜"])
        precondition(tokens[0].ruby == "いわれ")
        precondition(tokens[1].ruby == nil)
        precondition(tokens[2].ruby == "よる")

        print("ruby token contract passed: 言われ→いわれ, 夜→よる")
    }
}
