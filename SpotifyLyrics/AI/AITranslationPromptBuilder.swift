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
        let system = """
        You translate an entire song while preserving line structure. Return ONLY a JSON array. Each item must have exactly two keys: index (integer) and translation (string). Preserve every input index, including blank lines. For a nonblank input line return a nonblank translation; for a blank input line return an empty string. Never merge, split, reorder, renumber, or add lines. Never return timestamps, explanations, markdown, or metadata.
        Target language: \(configuration.targetLanguage)
        Style: \(configuration.style)
        """
        let custom = configuration.customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
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
}
