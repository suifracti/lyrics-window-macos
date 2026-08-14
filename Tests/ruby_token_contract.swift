import Foundation

private struct FixtureJapaneseEngine: JapaneseMorphologyEngine {
    func tokenize(_ text: String) throws -> [JapaneseMorphologyToken] {
        switch text {
        case "言われた夜":
            return [
                JapaneseMorphologyToken(originalText: "言われ", readingKatakana: "イワレ", lemma: "言う", partOfSpeech: "動詞"),
                JapaneseMorphologyToken(originalText: "た", readingKatakana: "タ", lemma: "た", partOfSpeech: "助動詞"),
                JapaneseMorphologyToken(originalText: "夜", readingKatakana: "ヨル", lemma: "夜", partOfSpeech: "名詞")
            ]
        case "流れた":
            return [
                JapaneseMorphologyToken(originalText: "流れ", readingKatakana: "ナガレ", lemma: "流れる", partOfSpeech: "動詞"),
                JapaneseMorphologyToken(originalText: "た", readingKatakana: "タ", lemma: "た", partOfSpeech: "助動詞")
            ]
        case "思い出す":
            return [
                JapaneseMorphologyToken(originalText: "思い出す", readingKatakana: "オモイダス", lemma: "思い出す", partOfSpeech: "動詞")
            ]
        case "日々":
            return [
                JapaneseMorphologyToken(originalText: "日々", readingKatakana: "ヒビ", lemma: "日々", partOfSpeech: "名詞")
            ]
        case "日":
            return [
                JapaneseMorphologyToken(originalText: "日", readingKatakana: "ヒ", lemma: "日", partOfSpeech: "名詞")
            ]
        default:
            return []
        }
    }
}

@main
struct RubyTokenContract {
    static func main() {
        let result = JapaneseReadingPipeline.analyze(
            originalText: "言われた夜",
            engine: FixtureJapaneseEngine()
        )
        let tokens = result.tokens.flatMap { JapaneseReadingPipeline.rubyTokens(for: $0, engine: FixtureJapaneseEngine()) }

        precondition(tokens.map(\.surface) == ["言", "われ", "た", "夜"])
        precondition(tokens.map(\.ruby) == ["い", nil, nil, "よる"])
        precondition(tokens.map(\.kanaSurface) == ["い", "われ", nil, "よる"])

        let inflected = JapaneseReadingPipeline.analyze(
            originalText: "流れた",
            engine: FixtureJapaneseEngine()
        )
        let inflectedRuby = inflected.tokens.flatMap { JapaneseReadingPipeline.rubyTokens(for: $0, engine: FixtureJapaneseEngine()) }
        precondition(inflectedRuby.map(\.surface) == ["流", "れ", "た"])
        precondition(inflectedRuby.map(\.ruby) == ["なが", nil, nil])
        precondition(inflectedRuby.map(\.kanaSurface) == ["なが", "れ", nil])

        let compound = JapaneseReadingPipeline.analyze(
            originalText: "思い出す",
            engine: FixtureJapaneseEngine()
        )
        let compoundRuby = compound.tokens.flatMap { JapaneseReadingPipeline.rubyTokens(for: $0, engine: FixtureJapaneseEngine()) }
        precondition(compoundRuby.map(\.surface) == ["思", "い", "出", "す"])
        precondition(compoundRuby.map(\.ruby) == ["おも", nil, "だ", nil])
        precondition(compoundRuby.map(\.kanaSurface) == ["おも", "い", "だ", "す"])

        let iteration = JapaneseReadingPipeline.analyze(
            originalText: "日々",
            engine: FixtureJapaneseEngine()
        )
        let iterationRuby = iteration.tokens.flatMap { JapaneseReadingPipeline.rubyTokens(for: $0, engine: FixtureJapaneseEngine()) }
        precondition(iterationRuby.map(\.surface) == ["日", "々"])
        precondition(iterationRuby.map(\.ruby) == ["ひ", nil])
        precondition(iterationRuby.map(\.kanaSurface) == ["ひ", "び"])

        let katakana = JapaneseReadingPipeline.analyze(
            originalText: "イマジネーション",
            engine: FixtureJapaneseEngine()
        )
        let katakanaRuby = katakana.tokens.flatMap {
            JapaneseReadingPipeline.rubyTokens(for: $0, engine: FixtureJapaneseEngine())
        }
        precondition(katakanaRuby.map(\.surface) == ["イマジネーション"])
        precondition(katakanaRuby.map(\.ruby) == [nil])
        precondition(katakanaRuby.map(\.kanaSurface) == ["いまじねーしょん"])

        print("ruby token contract passed: okurigana excluded from ruby and kana replacement preserved")
    }
}
