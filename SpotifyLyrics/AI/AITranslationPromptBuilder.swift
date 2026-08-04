import Foundation
import CryptoKit

public struct AITranslationPrompt: Equatable, Sendable {
    public let system: String
    public let user: String
    public let promptHash: String

    public init(system: String, user: String, promptHash: String) {
        self.system = system
        self.user = user
        self.promptHash = promptHash
    }
}

public struct AITranslationPromptBuilder: Sendable {
    public init() {}

    public func build(
        context: AITranslationContext,
        configuration: AITranslationConfiguration
    ) throws -> AITranslationPrompt {
        let presetID = TranslationPromptPresetID(rawValue: configuration.promptPresetID) ?? .naturalSong
        return try build(context: context, configuration: configuration, presetID: presetID, profile: nil)
    }

    public func build(
        context: AITranslationContext,
        configuration: AITranslationConfiguration,
        presetID: TranslationPromptPresetID,
        profile: TranslationStyleProfile? = nil
    ) throws -> AITranslationPrompt {
        let presetGuidance: String
        switch presetID {
        case .naturalSong:
            presetGuidance = "Translate naturally as a song while preserving imagery, tone, and line structure."
        case .literalFaithful:
            presetGuidance = "Stay faithful to the source wording and do not add unstated story details."
        case .poeticFlow:
            presetGuidance = "Keep poetic flow and rhythm without changing the source meaning."
        case .contextAware:
            presetGuidance = "Use the entire song context to keep subjects, tone, proper nouns, and repeated choruses consistent."
        case .custom:
            presetGuidance = "Follow the custom style guidance below without changing line structure."
        }
        let system = """
        You translate an entire song while preserving line structure. Return ONLY a JSON array. Each item must have exactly two keys: index (integer) and translation (string). Preserve every input index, including blank lines. For a nonblank input line return a nonblank translation; for a blank input line return an empty string. Never merge, split, reorder, renumber, or add lines. Never return timestamps, explanations, markdown, or metadata.
        Target language: \(configuration.targetLanguage)
        Style: \(configuration.style)
        Preset: \(presetGuidance)
        """
        var custom = configuration.customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if let profile, !profile.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            custom += (custom.isEmpty ? "" : "\n") + profile.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let profile {
            if profile.preserveProperNouns { custom += "\nPreserve proper nouns and names conservatively." }
            if profile.preserveRepetition { custom += "\nKeep repeated chorus translations consistent." }
            if profile.keepSongTone { custom += "\nKeep the song's original tone." }
        }
        let fullSystem = custom.isEmpty ? system : system + "\nAdditional user style guidance:\n" + custom

        let payload: [String: Any] = [
            "title": context.title,
            "artist": context.artist,
            "album": context.album,
            "sourceLanguage": context.sourceLanguage,
            "targetLanguage": context.targetLanguage,
            "style": context.style,
            "lines": context.lines.map { line in
                var item: [String: Any] = ["index": line.index, "text": line.original]
                if let kana = line.kana, !kana.isEmpty { item["kana"] = kana }
                if let romaji = line.romaji, !romaji.isEmpty { item["romaji"] = romaji }
                return item
            }
        ]
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw AITranslationError.invalidResponse("无法构造翻译请求")
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let user = String(data: data, encoding: .utf8) else {
            throw AITranslationError.invalidResponse("无法编码翻译请求")
        }
        let hashInput = Data((fullSystem + "\n" + user).utf8)
        let hash = SHA256.hash(data: hashInput).map { String(format: "%02x", $0) }.joined()
        return AITranslationPrompt(system: fullSystem, user: user, promptHash: hash)
    }

    /// Prompt Preview deliberately returns the same immutable prompt value as
    /// execution, but has no network, persistence, playback, or Keychain side
    /// effects. The UI may render it as a read-only preview.
    public func preview(
        context: AITranslationContext,
        configuration: AITranslationConfiguration,
        presetID: TranslationPromptPresetID,
        profile: TranslationStyleProfile? = nil
    ) throws -> AITranslationPrompt {
        try build(context: context, configuration: configuration, presetID: presetID, profile: profile)
    }
}
