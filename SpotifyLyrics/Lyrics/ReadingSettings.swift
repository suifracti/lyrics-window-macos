import Foundation

public enum ReadingUncertaintyPolicy: String, CaseIterable, Codable, Sendable {
    case needsConfirmation
    case allowLocalHighConfidence

    public var displayName: String {
        switch self {
        case .needsConfirmation: return "低置信读音需确认"
        case .allowLocalHighConfidence: return "仅采用高置信本地结果"
        }
    }
}

/// Preferences for the shared reading projection. This is deliberately a
/// value type owned by AppSettingsStore; it contains no session or playback
/// state and is never written to SQLite.
public struct ReadingPreferences: Codable, Equatable, Sendable {
    public var japaneseEngineID: String
    public var japaneseRepresentationID: String
    public var pinyinRepresentationID: String
    public var scriptConversionID: String
    public var automaticGeneration: Bool
    public var aiAssistedCandidate: Bool
    public var uncertaintyPolicy: ReadingUncertaintyPolicy

    public init(
        japaneseEngineID: String = ReadingEngineID.japaneseContextual.rawValue,
        japaneseRepresentationID: String = ReadingRepresentationID.kana.rawValue,
        pinyinRepresentationID: String = ReadingRepresentationID.pinyinToneMarks.rawValue,
        scriptConversionID: String = ScriptConversionID.none.rawValue,
        automaticGeneration: Bool = false,
        aiAssistedCandidate: Bool = false,
        uncertaintyPolicy: ReadingUncertaintyPolicy = .needsConfirmation
    ) {
        self.japaneseEngineID = japaneseEngineID
        self.japaneseRepresentationID = japaneseRepresentationID
        self.pinyinRepresentationID = pinyinRepresentationID
        self.scriptConversionID = scriptConversionID
        self.automaticGeneration = automaticGeneration
        self.aiAssistedCandidate = aiAssistedCandidate
        self.uncertaintyPolicy = uncertaintyPolicy
    }

    public var japaneseRepresentation: ReadingRepresentationID {
        ReadingRepresentationID(rawValue: japaneseRepresentationID) ?? .kana
    }

    public var pinyinRepresentation: ReadingRepresentationID {
        ReadingRepresentationID(rawValue: pinyinRepresentationID) ?? .pinyinToneMarks
    }

    public var scriptConversion: ScriptConversionID {
        ScriptConversionID(rawValue: scriptConversionID) ?? .none
    }

    /// Old and unknown Japanese engine IDs remain decodable so existing
    /// settings never fail to load, but the current product has one supported
    /// Japanese path. Normalize only that field and preserve every other
    /// reading preference verbatim.
    public func normalizedForCurrentEngines() -> ReadingPreferences {
        guard japaneseEngineID != ReadingEngineID.japaneseContextual.rawValue else {
            return self
        }
        var normalized = self
        normalized.japaneseEngineID = ReadingEngineID.japaneseContextual.rawValue
        return normalized
    }
}
