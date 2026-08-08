import Foundation

/// Contract for the production Japanese morphology → kana → romaji pipeline.
///
/// This test intentionally exercises real MeCab/IPADIC output rather than a
/// finite longest-match reading table.  Every printed row is the data that a
/// caller may use for diagnostics or a later alignment gate.
@main
struct JapaneseReadingContract {
    struct Fixture {
        let text: String
        let surfaces: [String]
        let lemmas: [String]
        let kana: String
        let romaji: String
    }

    static func main() {
        let fixtures = [
            Fixture(text: "言われた", surfaces: ["言わ", "れ", "た"], lemmas: ["言う", "れる", "た"], kana: "いわれた", romaji: "iwareta"),
            Fixture(text: "言えなかった", surfaces: ["言え", "なかっ", "た"], lemmas: ["言える", "ない", "た"], kana: "いえなかった", romaji: "ienakatta"),
            Fixture(text: "日々", surfaces: ["日々"], lemmas: ["日々"], kana: "ひび", romaji: "hibi"),
            Fixture(text: "戻れない", surfaces: ["戻れ", "ない"], lemmas: ["戻れる", "ない"], kana: "もどれない", romaji: "modorenai"),
            Fixture(text: "流れた", surfaces: ["流れ", "た"], lemmas: ["流れる", "た"], kana: "ながれた", romaji: "nagareta"),
            Fixture(text: "混じった", surfaces: ["混じっ", "た"], lemmas: ["混じる", "た"], kana: "まじった", romaji: "majitta"),
            Fixture(text: "歩いた", surfaces: ["歩い", "た"], lemmas: ["歩く", "た"], kana: "あるいた", romaji: "aruita"),
            Fixture(text: "景色", surfaces: ["景色"], lemmas: ["景色"], kana: "けしき", romaji: "keshiki"),
            Fixture(text: "紛れてく", surfaces: ["紛れ", "て", "く"], lemmas: ["紛れる", "て", "く"], kana: "まぎれてく", romaji: "magireteku")
        ]

        for fixture in fixtures {
            let result = JapaneseReadingPipeline.analyze(originalText: fixture.text)
            precondition(result.originalText == fixture.text, "original text was changed for \(fixture.text)")
            precondition(result.tokens.map(\.originalText) == fixture.surfaces, "surface tokenization failed for \(fixture.text)")
            precondition(result.tokens.map { $0.lemma ?? "<nil>" } == fixture.lemmas, "lemma failed for \(fixture.text)")
            precondition(result.tokens.compactMap(\.kana).joined() == fixture.kana, "kana failed for \(fixture.text)")
            precondition(result.kanaText == fixture.kana, "line kana failed for \(fixture.text)")
            precondition(result.romajiText == fixture.romaji, "romaji failed for \(fixture.text): \(result.romajiText ?? "<nil>")")
            precondition(!result.containsUnknown, "known regression became unknown: \(fixture.text)")

            for token in result.tokens {
                print("TOKEN original=\(token.originalText) lemma=\(token.lemma ?? "<nil>") kana=\(token.kana ?? "<unknown>") romaji=\(token.romaji ?? "<unknown>") source=\(token.source.rawValue) confidence=\(String(format: "%.2f", token.confidence))")
            }
        }

        // Particle pronunciation is determined by morphology, not by a
        // character-wide replacement rule.
        let particles = JapaneseReadingPipeline.analyze(originalText: "私は学校へ行く水を飲む")
        precondition(particles.kanaText == "わたしわがっこうえいくみずおのむ", "particle readings were not morphology-aware")

        // IPADIC classifies the later glyphs in a repeated kanji run as
        // suffix nouns. They still represent the same repeated lyric sound.
        let repeatedHand = JapaneseReadingPipeline.analyze(originalText: "手手手手")
        precondition(
            repeatedHand.kanaText == "てててて",
            "repeated kanji suffix readings were not normalized: \(repeatedHand.kanaText ?? "<nil>")"
        )
        let repeatedHandRuby = repeatedHand.tokens.flatMap {
            JapaneseReadingPipeline.rubyTokens(for: $0)
        }
        precondition(repeatedHandRuby.map(\.surface) == ["手", "手", "手", "手"])
        precondition(repeatedHandRuby.map(\.ruby) == ["て", "て", "て", "て"])

        // IPADIC may analyze 満 as the given name "みつる" in isolation.
        // Context v2 must resolve the fixed phrase without placing a whole
        // sentence reading under the line or changing unrelated tokens.
        let rawMan = JapaneseReadingPipeline.analyze(originalText: "満を持して")
        let contextualMan = JapaneseReadingPipeline.analyzeContextually(originalText: "満を持して")
        precondition(rawMan.tokens.first?.kana == "みつる", "dictionary v1 baseline unexpectedly changed")
        precondition(contextualMan.tokens.first?.originalText == "満")
        precondition(contextualMan.tokens.first?.kana == "まん", "context v2 did not resolve 満を持して")
        let contextualRuby = contextualMan.tokens.flatMap {
            JapaneseReadingPipeline.rubyTokens(for: $0)
        }
        precondition(contextualRuby.first(where: { $0.surface == "満" })?.ruby == "まん")
        precondition(contextualRuby.allSatisfy { $0.ruby != "まんおじして" })
        let contextualMixedLine = JapaneseReadingPipeline.analyzeContextually(
            originalText: "満を持して 衝動にFeeling Feeling Yeah"
        )
        precondition(
            contextualMixedLine.tokens.first(where: { $0.originalText == "満" })?.kana == "まん",
            "context phrase stopped working when followed by mixed-script lyrics"
        )

        // These are the exact lines that previously lost ruby in the V3
        // screenshots.  A line-level reading must be complete enough for the
        // view to derive per-kanji ruby tokens, not merely return a partial
        // morphology result.
        let screenshotLines = [
            "七回目のベルで受話器を取った君",
            "名前を言わなくても声ですぐ分かってくれる",
            "唇から自然とこぼれ落ちるメロディー",
            "名前",
            "君"
        ]
        for text in screenshotLines {
            let reading = JapaneseReadingPipeline.analyze(originalText: text)
            precondition(reading.kanaText?.isEmpty == false, "screenshot line has no complete kana: \(text)")
            let rubyTokens = reading.tokens.flatMap { token in
                JapaneseReadingPipeline.rubyTokens(for: token)
            }
            precondition(rubyTokens.contains(where: { $0.ruby?.isEmpty == false }), "screenshot line has no kanji ruby tokens: \(text)")
        }

        // Long vowels, sokuon, yoon, punctuation, latin and digits remain
        // deterministic and do not destroy the original script.
        let orthography = JapaneseReadingPipeline.analyze(originalText: "「きょう」コーヒー きって SNS １２３")
        precondition(orthography.originalText == "「きょう」コーヒー きって SNS １２３")
        precondition(orthography.romajiText?.contains("kyou") == true)
        precondition(orthography.romajiText?.contains("koohii") == true)
        precondition(orthography.romajiText?.contains("kitte") == true)
        precondition(orthography.romajiText?.contains("SNS") == true)
        precondition(orthography.romajiText?.contains("123") == true || orthography.romajiText?.contains("１２３") == true)

        let sns = JapaneseReadingPipeline.analyze(originalText: "SNS")
        precondition(sns.tokens.count == 1)
        precondition(sns.tokens[0].originalText == "SNS")
        precondition(sns.tokens[0].kana == "SNS")
        precondition(sns.tokens[0].romaji == "SNS")
        precondition(sns.tokens[0].source == .literalPreserved)
        precondition(sns.tokens[0].confidence == 1.0)

        // Official/provider kana is a line-level authoritative override and
        // must win over local morphology.
        let official = JapaneseReadingPipeline.analyze(originalText: "言われた", providerKana: "イワレタ")
        precondition(official.originalText == "言われた")
        precondition(official.kanaText == "いわれた")
        precondition(official.romajiText == "iwareta")
        precondition(official.tokens.count == 1)
        precondition(official.tokens[0].source == .providerOfficial)
        precondition(official.tokens[0].confidence == 1.0)

        // A romaji value in a provider's kana field is not a confirmed kana
        // layer. It must fail closed rather than being rendered as ruby.
        let invalidProvider = JapaneseReadingPipeline.analyze(
            originalText: "言われた",
            providerKana: "iwareta"
        )
        precondition(invalidProvider.source != .providerOfficial)
        precondition(invalidProvider.kanaText == "いわれた")

        let symbolProvider = JapaneseReadingPipeline.analyze(
            originalText: "言われた",
            providerKana: "!!!"
        )
        precondition(symbolProvider.source != .providerOfficial)
        precondition(symbolProvider.kanaText == "いわれた")

        // An unresolvable Han token fails closed.  It must never receive a
        // Chinese/Unicode fallback reading and must not enter alignment.
        let unknown = JapaneseReadingPipeline.analyze(originalText: "𩸽定食")
        precondition(unknown.containsUnknown)
        precondition(unknown.kanaText == nil)
        precondition(unknown.romajiText == nil)
        precondition(unknown.tokens.contains { $0.source == .unknown && $0.confidence == 0.0 })

        // The compatibility generator delegates to the morphology pipeline,
        // not to its old finite dictionary as the primary engine.
        precondition(JapaneseKanaGenerator.kanaPreservingOriginal("水曜日の約束") == "すいようびのやくそく")
        precondition(JapaneseKanaGenerator.kanaPreservingOriginal("𩸽定食") == nil)

        print("japanese reading contract passed")
    }
}
