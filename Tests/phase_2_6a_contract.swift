import Foundation

@main
struct ReadingFoundationContract {
    static func main() {
        precondition(ReadingEngineID.japaneseDictionary.rawValue == "readingEngine.japaneseDictionary.v1")
        precondition(ReadingEngineID.japaneseContextual.rawValue == "readingEngine.japaneseContextual.v2")
        precondition(ReadingEngineID.chinesePinyin.rawValue == "readingEngine.chinesePinyin.v1")
        precondition(ReadingRepresentationID.allCases.count == 5)

        let japanese = ReadingLanguageGate.analyze("学生として生きる", languageHint: "ja")
        precondition(japanese.language == .japanese)
        precondition(japanese.segments.allSatisfy { $0.language == .japanese })
        precondition(ReadingLanguageGate.shouldRunJapanese(on: japanese))
        precondition(!ReadingLanguageGate.shouldRunPinyin(on: japanese))

        let chinese = ReadingLanguageGate.analyze("银行行长", languageHint: "zh-Hans")
        precondition(chinese.language == .simplifiedChinese)
        precondition(ReadingLanguageGate.shouldRunPinyin(on: chinese))
        precondition(!ReadingLanguageGate.shouldRunJapanese(on: chinese))

        let mixed = ReadingLanguageGate.analyze("君と Love", languageHint: "ja")
        precondition(mixed.language == .mixed)
        precondition(mixed.segments.contains { $0.language == .japanese })
        precondition(mixed.segments.contains { $0.language == .latin })

        let record = ReadingVersionRecord(
            id: UUID(),
            lyricsVersionID: UUID(),
            sourceContentHash: "source-hash",
            engineID: ReadingEngineID.japaneseDictionary.rawValue,
            representationID: ReadingRepresentationID.kana.rawValue,
            language: .japanese,
            createdAt: Date(),
            updatedAt: Date(),
            isMachineGenerated: true,
            isManuallyEdited: false,
            isCurrent: true,
            isLocked: false,
            isArchived: false,
            parentVersionID: nil,
            confidence: 0.96,
            warningMetadata: [],
            contextHash: "context-hash"
        )
        precondition(record.engineID == "readingEngine.japaneseDictionary.v1")
        precondition(record.sourceContentHash == "source-hash")

        print("phase 2.6A foundation contract passed")
    }
}
