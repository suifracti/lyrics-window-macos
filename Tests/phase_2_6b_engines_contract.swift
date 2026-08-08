import Foundation

@main
struct ReadingEnginesContract {
    static func main() async throws {
        let japaneseLines = [
            ReadingInputLine(lineIndex: 0, originalText: "生ビールを飲む"),
            ReadingInputLine(lineIndex: 1, originalText: "学生として生きる"),
            ReadingInputLine(lineIndex: 2, originalText: "上手に歌う"),
            ReadingInputLine(lineIndex: 3, originalText: "階段を上がる"),
            ReadingInputLine(lineIndex: 4, originalText: "Love 生ビール")
        ]
        let request = ReadingGenerationRequest(
            lyricsVersionID: UUID(),
            sourceContentHash: "fixture",
            lines: japaneseLines,
            languageHint: "ja",
            nearbyContext: japaneseLines.map(\.originalText),
            representationID: .kana
        )
        let dictionary = try await JapaneseDictionaryReadingEngine().generate(request)
        precondition(dictionary.engineID == .japaneseDictionary)
        precondition(dictionary.lines.count == japaneseLines.count)
        precondition(dictionary.lines[0].readingText?.isEmpty == false)
        precondition(dictionary.lines[4].originalText == "Love 生ビール")
        precondition(ReadingEngineRegistry.make(.japaneseDictionary).stableID == .japaneseDictionary)
        precondition(ReadingEngineRegistry.make(stableID: "unknown.engine").stableID == .japaneseContextual)
        precondition(
            ReadingEngineRegistry.userSelectableJapaneseIDs == [.japaneseContextual],
            "legacy Japanese engines must not remain user-selectable"
        )

        let legacyPreferences = ReadingPreferences(
            japaneseEngineID: ReadingEngineID.japaneseDictionary.rawValue
        )
        precondition(
            legacyPreferences.normalizedForCurrentEngines().japaneseEngineID
                == ReadingEngineID.japaneseContextual.rawValue,
            "legacy Japanese engine preference was not migrated"
        )
        let unknownPreferences = ReadingPreferences(japaneseEngineID: "readingEngine.removed.v9")
        precondition(
            unknownPreferences.normalizedForCurrentEngines().japaneseEngineID
                == ReadingEngineID.japaneseContextual.rawValue,
            "unknown Japanese engine preference was not migrated"
        )

        let contextual = try await JapaneseContextualReadingEngine().generate(request)
        precondition(contextual.engineID == .japaneseContextual)
        precondition(contextual.contextHash != dictionary.contextHash)

        let scopedCorrection = ReadingDictionaryEntry(
            surface: "満",
            reading: "まん",
            language: .japanese,
            trackStableKey: "spotify:track:scope-a",
            priority: 100
        )
        let corrected = try await JapaneseContextualReadingEngine(
            userEntries: [scopedCorrection]
        ).generate(
            ReadingGenerationRequest(
                lyricsVersionID: UUID(),
                sourceContentHash: "scoped-correction",
                lines: [ReadingInputLine(lineIndex: 0, originalText: "満の声")],
                languageHint: "ja",
                trackStableKey: "spotify:track:scope-a",
                artistDisplay: "fixture",
                representationID: .kana
            )
        )
        let correctedLine = corrected.lines[0]
        precondition(correctedLine.originalText == "満の声")
        precondition(
            correctedLine.tokens.first(where: { $0.surface == "満" })?.reading == "まん",
            "scoped correction did not replace the matching token"
        )
        precondition(
            correctedLine.tokens.allSatisfy { $0.surface != "満の声" },
            "a token correction must not collapse the full lyric into one ruby token"
        )

        let romajiRequest = ReadingGenerationRequest(
            lyricsVersionID: UUID(), sourceContentHash: "fixture", lines: japaneseLines,
            languageHint: "ja", representationID: .romaji
        )
        let romaji = try await JapaneseDictionaryReadingEngine().generate(romajiRequest)
        precondition(romaji.lines[0].readingText?.contains(" ") == true || romaji.lines[0].readingText?.isEmpty == false)

        let chineseLines = [
            ReadingInputLine(lineIndex: 0, originalText: "银行行长"),
            ReadingInputLine(lineIndex: 1, originalText: "重庆重新开始"),
            ReadingInputLine(lineIndex: 2, originalText: "音乐使人快乐"),
            ReadingInputLine(lineIndex: 3, originalText: "Hello，音乐")
        ]
        let pinyinRequest = ReadingGenerationRequest(
            lyricsVersionID: UUID(), sourceContentHash: "fixture", lines: chineseLines,
            languageHint: "zh-Hans", representationID: .pinyinToneMarks
        )
        let pinyin = try await ChinesePinyinReadingEngine().generate(pinyinRequest)
        precondition(pinyin.engineID == .chinesePinyin)
        precondition(pinyin.lines[0].readingText?.contains("y") == true)
        precondition(pinyin.lines[1].readingText?.contains("ch") == true)
        precondition(pinyin.lines[2].warnings.contains(.ambiguousReading) == false)
        precondition(pinyin.lines[3].readingText?.contains("Hello") == true)

        let traditional = try await ChinesePinyinReadingEngine().generate(
            ReadingGenerationRequest(
                lyricsVersionID: UUID(),
                sourceContentHash: "fixture-traditional",
                lines: [ReadingInputLine(lineIndex: 0, originalText: "銀行行長")],
                languageHint: "zh-Hant",
                representationID: .pinyinToneMarks
            )
        )
        precondition(traditional.lines[0].readingText == "yīn háng háng zhǎng")

        let numbers = try await ChinesePinyinReadingEngine().generate(
            ReadingGenerationRequest(lyricsVersionID: UUID(), sourceContentHash: "fixture", lines: chineseLines, languageHint: "zh-Hans", representationID: .pinyinToneNumbers)
        )
        precondition(numbers.lines[0].readingText?.contains("1") == true)
        let plain = try await ChinesePinyinReadingEngine().generate(
            ReadingGenerationRequest(lyricsVersionID: UUID(), sourceContentHash: "fixture", lines: chineseLines, languageHint: "zh-Hans", representationID: .pinyinPlain)
        )
        precondition(plain.lines[0].readingText?.contains("1") == false)

        precondition(ReadingScriptConverter.convert("銀行行長", using: .traditionalToSimplified) == "银行行长")
        precondition(ReadingScriptConverter.convert("银行行长", using: .simplifiedToTraditional) == "銀行行長")
        precondition(ReadingScriptConverter.convert("A🙂1", using: .traditionalToSimplified) == "A🙂1")

        let defaults = UserDefaults(suiteName: "reading-contract-\(UUID().uuidString)")!
        let store = ReadingUserDictionaryStore(defaults: defaults)
        let entry = ReadingDictionaryEntry(surface: "生ビール", reading: "なまビール", language: .japanese, priority: 10)
        store.upsert(entry)
        precondition(store.load().first?.surface == "生ビール")
        store.remove(id: entry.id)
        precondition(store.load().isEmpty)

        print("phase 2.6B engines contract passed")
    }
}
