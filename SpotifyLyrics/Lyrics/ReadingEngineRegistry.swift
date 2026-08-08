import Foundation

/// The single routing table for local reading engines. It contains no
/// playback/session state and deliberately does not create an AI client.
public enum ReadingEngineRegistry {
    public static let userSelectableJapaneseIDs: [ReadingEngineID] = [
        .japaneseContextual
    ]

    public static let stableIDs: [ReadingEngineID] = [
        .japaneseDictionary,
        .japaneseContextual,
        .chinesePinyin
    ]

    public static func make(
        _ id: ReadingEngineID,
        userEntries: [ReadingDictionaryEntry] = []
    ) -> any ReadingEngine {
        switch id {
        case .japaneseDictionary:
            return JapaneseDictionaryReadingEngine(userEntries: userEntries)
        case .japaneseContextual:
            return JapaneseContextualReadingEngine(userEntries: userEntries)
        case .chinesePinyin:
            return ChinesePinyinReadingEngine(userEntries: userEntries)
        }
    }

    public static func make(
        stableID: String,
        userEntries: [ReadingDictionaryEntry] = []
    ) -> any ReadingEngine {
        let id = ReadingEngineID(rawValue: stableID) ?? .japaneseContextual
        return make(id, userEntries: userEntries)
    }
}
