import Foundation
#if canImport(Translation)
import Translation
#endif

public protocol AITranslationService: Sendable {
    func translate(
        context: AITranslationContext,
        sourceContentHash: String,
        configuration: AITranslationConfiguration
    ) async throws -> AITranslationDraft

    func testConnection(configuration: AITranslationConfiguration) async throws
}

public protocol TranslationEngine: AITranslationService {
    var metadata: TranslationEngineMetadata { get }
}

private struct LegacyTranslationEngineAdapter: TranslationEngine {
    let service: any AITranslationService

    var metadata: TranslationEngineMetadata {
        TranslationEngineMetadata(
            stableID: TranslationEngineID.openAICompatible.rawValue,
            displayName: "兼容旧翻译服务",
            availability: .available,
            requiresAPIKey: true,
            supportsModelDirectory: false
        )
    }

    func translate(
        context: AITranslationContext,
        sourceContentHash: String,
        configuration: AITranslationConfiguration
    ) async throws -> AITranslationDraft {
        try await service.translate(context: context, sourceContentHash: sourceContentHash, configuration: configuration)
    }

    func testConnection(configuration: AITranslationConfiguration) async throws {
        try await service.testConnection(configuration: configuration)
    }
}

public struct OpenAICompatibleTranslationService: TranslationEngine, Sendable {
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

    public var metadata: TranslationEngineMetadata {
        TranslationEngineMetadata(
            stableID: TranslationEngineID.openAICompatible.rawValue,
            displayName: "OpenAI-compatible API",
            availability: .requiresConfiguration,
            requiresAPIKey: true,
            supportsModelDirectory: true
        )
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
                sourceContentHash: sourceContentHash,
                engineID: TranslationEngineID.openAICompatible.rawValue,
                promptPresetID: configuration.promptPresetID,
                profileID: configuration.profileID,
                profileSnapshot: configuration.profileSnapshot,
                temperature: configuration.temperature,
                workflowID: configuration.workflowID,
                fallbackStrategy: configuration.fallbackStrategy,
                isDraft: true
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

/// Apple System Translation is an independent engine. It is never silently
/// selected when the compatible API fails; the session applies the user's
/// explicit fallback strategy before calling this type.
public struct AppleSystemTranslationEngine: TranslationEngine, Sendable {
    public init() {}

    public var metadata: TranslationEngineMetadata {
        TranslationEngineMetadata(
            stableID: TranslationEngineID.appleSystem.rawValue,
            displayName: "Apple 系统翻译",
            availability: Self.isRuntimeAvailable ? .available : .requiresSystemSupport,
            requiresAPIKey: false,
            supportsModelDirectory: false
        )
    }

    private static var isRuntimeAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    public func translate(
        context: AITranslationContext,
        sourceContentHash: String,
        configuration: AITranslationConfiguration
    ) async throws -> AITranslationDraft {
#if canImport(Translation)
        guard #available(macOS 26.0, *) else {
            throw AITranslationError.engineUnavailable("当前 macOS 不支持 Apple 系统翻译")
        }
        let source = Locale.Language(identifier: context.sourceLanguage)
        let target = Locale.Language(identifier: configuration.targetLanguage)
        let availability = await LanguageAvailability().status(from: source, to: target)
        guard availability != .unsupported else {
            throw AITranslationError.engineUnavailable("Apple 系统翻译不支持当前语言组合")
        }
        let nonBlank = context.lines.filter { !$0.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let session = TranslationSession(installedSource: source, target: target)
        let responses = try await session.translations(from: nonBlank.map { TranslationSession.Request(sourceText: $0.original) })
        guard responses.count == nonBlank.count else {
            throw AITranslationError.invalidResponse("Apple 系统翻译返回行数不匹配")
        }
        var responseIndex = 0
        let lines = context.lines.map { line -> AITranslationLine in
            guard !line.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return AITranslationLine(index: line.index, translation: "")
            }
            defer { responseIndex += 1 }
            return AITranslationLine(index: line.index, translation: responses[responseIndex].targetText)
        }
        let validated = try AITranslationResponseValidator.validate(lines, against: context.lines.map(\.original))
        return AITranslationDraft(
            lines: validated,
            targetLanguage: configuration.targetLanguage,
            model: "Apple System Translation",
            baseURLHost: "",
            promptHash: "apple-system-translation-v1",
            sourceContentHash: sourceContentHash,
            engineID: TranslationEngineID.appleSystem.rawValue,
            promptPresetID: configuration.promptPresetID,
            profileID: configuration.profileID,
            profileSnapshot: configuration.profileSnapshot,
            temperature: configuration.temperature,
            workflowID: configuration.workflowID,
            fallbackStrategy: configuration.fallbackStrategy,
            isDraft: true
        )
#else
        _ = context; _ = sourceContentHash; _ = configuration
        throw AITranslationError.engineUnavailable("当前构建不包含 Apple 系统翻译")
#endif
    }

    public func testConnection(configuration: AITranslationConfiguration) async throws {
        _ = try await translate(
            context: AITranslationContext(
                title: "", artist: "", album: "", sourceLanguage: "ja",
                targetLanguage: configuration.targetLanguage, style: "",
                lines: [AITranslationSourceLine(index: 0, original: "テスト")]
            ),
            sourceContentHash: "connection-test",
            configuration: configuration
        )
    }
}

public enum TranslationEngineRegistry {
    public static func make(stableID: String) -> any TranslationEngine {
        if stableID == TranslationEngineID.appleSystem.rawValue {
            return AppleSystemTranslationEngine()
        }
        return OpenAICompatibleTranslationService()
    }
}

extension TranslationEngineRegistry {
    public static func wrapping(_ service: any AITranslationService) -> any TranslationEngine {
        LegacyTranslationEngineAdapter(service: service)
    }
}
