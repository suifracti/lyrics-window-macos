import Foundation

@main
struct Phase25BContract {
    static func main() throws {
        let suite = "SpotifyLyrics.phase25b.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let profiles = TranslationProfileStore(defaults: defaults)
        let first = profiles.create(
            name: "我的自然风格",
            basePresetID: .naturalSong,
            customInstructions: "保持重复副歌一致",
            targetLanguage: "zh-Hans",
            temperatureOverride: 0.1,
            preserveProperNouns: true,
            preserveRepetition: true,
            keepSongTone: true
        )
        let second = profiles.create(name: "直译", basePresetID: .literalFaithful)
        precondition(first.id != second.id)
        precondition(profiles.list().count == 2)
        profiles.update(first.with(name: "我的自然风格 2"))
        precondition(profiles.list().first(where: { $0.id == first.id })?.name == "我的自然风格 2")

        let context = AITranslationContext(
            title: "夜",
            artist: "歌手",
            album: "专辑",
            sourceLanguage: "ja",
            targetLanguage: "zh-Hans",
            style: "natural_song",
            lines: [AITranslationSourceLine(index: 0, original: "夜の歌", kana: "よるのうた", romaji: "yoru no uta")]
        )
        let builder = AITranslationPromptBuilder()
        let natural = try builder.build(context: context, configuration: AITranslationConfiguration(), presetID: .naturalSong)
        let literal = try builder.build(context: context, configuration: AITranslationConfiguration(), presetID: .literalFaithful)
        precondition(natural.promptHash != literal.promptHash)
        precondition(natural.user.contains("index"))
        precondition(natural.system.contains("translation"))

        let preview = try builder.preview(context: context, configuration: AITranslationConfiguration(), presetID: .naturalSong)
        precondition(preview.promptHash == natural.promptHash)

        let valid = try AITranslationResponseValidator.validate(
            [AITranslationLine(index: 0, translation: "夜之歌")],
            against: ["夜の歌"]
        )
        precondition(valid.count == 1)
        for body in [
            #"[{"index":0,"translation":"译文","startTime":1}]"#,
            #"[{"index":0,"translation":"译文\n第二行"}]"#
        ] {
            do {
                _ = try AITranslationResponseParser.parse(Data(body.utf8), expectedLineCount: 1)
                fatalError("unsafe structured output accepted")
            } catch AITranslationResponseError.validationFailed { }
        }
        print("phase 2.5B contracts passed")
    }
}
