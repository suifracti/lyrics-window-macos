import Foundation
import CryptoKit

public struct AITranslationConfiguration: Equatable, Sendable {
    public var baseURL: String
    public var model: String
    public var targetLanguage: String
    public var style: String
    public var customSystemPrompt: String
    public var temperature: Double
    public var timeout: TimeInterval
    public var autoTranslateNewLyrics: Bool

    public init(
        baseURL: String = "",
        model: String = "",
        targetLanguage: String = "zh-Hans",
        style: String = "natural_song",
        customSystemPrompt: String = "",
        temperature: Double = 0.2,
        timeout: TimeInterval = 60,
        autoTranslateNewLyrics: Bool = false
    ) {
        self.baseURL = baseURL
        self.model = model
        self.targetLanguage = targetLanguage
        self.style = style
        self.customSystemPrompt = customSystemPrompt
        self.temperature = min(max(temperature, 0), 2)
        self.timeout = min(max(timeout, 5), 600)
        self.autoTranslateNewLyrics = autoTranslateNewLyrics
    }

    public var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var promptHash: String {
        let payload = [style, targetLanguage, customSystemPrompt]
            .joined(separator: "\u{1f}")
        return SHA256.hash(data: Data(payload.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public struct AITranslationEndpoint: Equatable, Sendable {
    public let baseURL: String

    public init(baseURL: String) {
        self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var chatCompletionsURL: URL {
        // The public property is intentionally convenient for contract tests.
        // Production requests call validatedChatCompletionsURL() first.
        normalizedURL() ?? URL(string: "about:blank")!
    }

    public func validatedChatCompletionsURL() throws -> URL {
        guard let url = normalizedURL(), url.scheme == "http" || url.scheme == "https" else {
            throw AITranslationError.invalidEndpoint
        }
        return url
    }

    public var hostForLogging: String {
        guard let url = URL(string: baseURL), let host = url.host, !host.isEmpty else { return "invalid" }
        return host
    }

    private func normalizedURL() -> URL? {
        var value = baseURL
        while value.hasSuffix("/") { value.removeLast() }
        guard !value.isEmpty, let raw = URL(string: value), let scheme = raw.scheme,
              (scheme == "http" || scheme == "https"), raw.host != nil,
              raw.query == nil, raw.fragment == nil else { return nil }

        let lower = value.lowercased()
        if lower.hasSuffix("/chat/completions") {
            return raw
        }
        if lower.hasSuffix("/v1") {
            return URL(string: value + "/chat/completions")
        }
        return URL(string: value + "/v1/chat/completions")
    }
}
