import Foundation

public protocol AITranslationService: Sendable {
    func translate(
        context: AITranslationContext,
        sourceContentHash: String,
        configuration: AITranslationConfiguration
    ) async throws -> AITranslationDraft

    func testConnection(configuration: AITranslationConfiguration) async throws
}

public struct OpenAICompatibleTranslationService: AITranslationService, Sendable {
    private let client: OpenAICompatibleClient
    private let keyStore: any AITranslationAPIKeyStore
    private let promptBuilder: AITranslationPromptBuilder

    public init(
        client: OpenAICompatibleClient = OpenAICompatibleClient(),
        keyStore: any AITranslationAPIKeyStore = KeychainAITranslationAPIKeyStore(),
        promptBuilder: AITranslationPromptBuilder = AITranslationPromptBuilder()
    ) {
        self.client = client
        self.keyStore = keyStore
        self.promptBuilder = promptBuilder
    }

    public func translate(
        context: AITranslationContext,
        sourceContentHash: String,
        configuration: AITranslationConfiguration
    ) async throws -> AITranslationDraft {
        guard configuration.isConfigured else { throw AITranslationError.notConfigured }
        guard let key = keyStore.read(), !key.isEmpty else { throw AITranslationError.missingAPIKey }
        let prompt = try promptBuilder.build(context: context, configuration: configuration)
        let result = try await client.complete(
            prompt: prompt,
            configuration: configuration,
            apiKey: key,
            inputLineCount: context.lines.count
        )
        do {
            let parsed = try AITranslationResponseParser.parse(
                result.content,
                expectedLineCount: context.lines.count
            )
            let validated = try AITranslationResponseParser.validate(
                parsed,
                against: context.lines.map(\.original)
            )
            return AITranslationDraft(
                lines: validated,
                targetLanguage: configuration.targetLanguage,
                model: configuration.model,
                baseURLHost: AITranslationEndpoint(baseURL: configuration.baseURL).hostForLogging,
                promptHash: prompt.promptHash,
                sourceContentHash: sourceContentHash
            )
        } catch let error as AITranslationResponseError {
            throw AITranslationError.invalidResponse(String(describing: error))
        }
    }

    public func testConnection(configuration: AITranslationConfiguration) async throws {
        guard configuration.isConfigured else { throw AITranslationError.notConfigured }
        guard let key = keyStore.read(), !key.isEmpty else { throw AITranslationError.missingAPIKey }
        _ = try await client.testConnection(configuration: configuration, apiKey: key)
    }
}
