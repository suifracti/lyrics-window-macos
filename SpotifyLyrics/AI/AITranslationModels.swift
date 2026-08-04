import Foundation

public enum AITranslationSourceKind: String, CaseIterable, Codable, Sendable {
    case ai
    case providerEmbedded
    case manualImport
    case manualEdit
    case legacyImported
}

/// Stable identifiers for the translation engines.  These are presentation
/// and routing identifiers only; the translation session remains the single
/// owner of in-flight work and selected versions.
public enum TranslationEngineID: String, CaseIterable, Codable, Sendable {
    case openAICompatible = "translationEngine.openAICompatible.v1"
    case appleSystem = "translationEngine.appleSystem.v1"
}

public enum TranslationEngineAvailability: String, Codable, Sendable {
    case available
    case unavailable
    case requiresConfiguration
    case requiresSystemSupport
}

public enum TranslationFallbackStrategy: String, CaseIterable, Codable, Sendable {
    case none
    case ask
    case automaticSystem

    public var title: String {
        switch self {
        case .none: return "不自动切换"
        case .ask: return "失败后询问"
        case .automaticSystem: return "自动尝试系统翻译"
        }
    }
}

public enum TranslationWorkflowID: String, CaseIterable, Codable, Sendable {
    case classicV1 = "translationWorkflow.classicV1"
    case contextualV2 = "translationWorkflow.contextualV2"
}

public struct TranslationEngineMetadata: Equatable, Sendable {
    public let stableID: String
    public let displayName: String
    public let availability: TranslationEngineAvailability
    public let requiresAPIKey: Bool
    public let supportsModelDirectory: Bool

    public init(
        stableID: String,
        displayName: String,
        availability: TranslationEngineAvailability,
        requiresAPIKey: Bool,
        supportsModelDirectory: Bool
    ) {
        self.stableID = stableID
        self.displayName = displayName
        self.availability = availability
        self.requiresAPIKey = requiresAPIKey
        self.supportsModelDirectory = supportsModelDirectory
    }
}

public enum TranslationEngineCatalog {
    public static let all: [TranslationEngineMetadata] = [
        TranslationEngineMetadata(
            stableID: TranslationEngineID.openAICompatible.rawValue,
            displayName: "OpenAI-compatible API",
            availability: .requiresConfiguration,
            requiresAPIKey: true,
            supportsModelDirectory: true
        ),
        TranslationEngineMetadata(
            stableID: TranslationEngineID.appleSystem.rawValue,
            displayName: "Apple 系统翻译",
            availability: .requiresSystemSupport,
            requiresAPIKey: false,
            supportsModelDirectory: false
        )
    ]

    public static func metadata(for stableID: String) -> TranslationEngineMetadata? {
        all.first { $0.stableID == stableID }
    }
}

public enum TranslationPromptPresetID: String, CaseIterable, Codable, Sendable {
    case naturalSong = "translationPrompt.naturalSong.v1"
    case literalFaithful = "translationPrompt.literalFaithful.v1"
    case poeticFlow = "translationPrompt.poeticFlow.v1"
    case contextAware = "translationPrompt.contextAware.v1"
    case custom = "translationPrompt.custom.v1"

    public var displayName: String {
        switch self {
        case .naturalSong: return "自然歌曲"
        case .literalFaithful: return "忠实直译"
        case .poeticFlow: return "诗意流畅"
        case .contextAware: return "上下文优先"
        case .custom: return "自定义"
        }
    }
}

public struct TranslationPromptPresetMetadata: Equatable, Sendable {
    public let id: TranslationPromptPresetID
    public let displayName: String
    public let detail: String

    public init(id: TranslationPromptPresetID, displayName: String, detail: String) {
        self.id = id
        self.displayName = displayName
        self.detail = detail
    }
}

public enum TranslationPromptPresetCatalog {
    public static let all: [TranslationPromptPresetMetadata] = [
        .init(id: .naturalSong, displayName: "自然歌曲", detail: "保留歌曲语气与意象，优先自然中文"),
        .init(id: .literalFaithful, displayName: "忠实直译", detail: "尽量贴近原句结构，不补写未提供的信息"),
        .init(id: .poeticFlow, displayName: "诗意流畅", detail: "在不改变含义的前提下保持诗性与节奏"),
        .init(id: .contextAware, displayName: "上下文优先", detail: "结合整首歌词统一主语、语气和重复副歌"),
        .init(id: .custom, displayName: "自定义", detail: "使用自定义系统提示词")
    ]

    public static var defaultPreset: TranslationPromptPresetMetadata {
        all[0]
    }
}

/// A personal translation style is a UserDefaults object, not a translation
/// version and not a second secret store. Its snapshot is copied into a
/// translation version only when an explicit request is saved.
public struct TranslationStyleProfile: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var basePresetID: TranslationPromptPresetID
    public var customInstructions: String
    public var targetLanguage: String
    public var temperatureOverride: Double?
    public var preserveProperNouns: Bool
    public var preserveRepetition: Bool
    public var keepSongTone: Bool
    public let createdAt: Date
    public var updatedAt: Date
    public var isArchived: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        basePresetID: TranslationPromptPresetID = .naturalSong,
        customInstructions: String = "",
        targetLanguage: String = "zh-Hans",
        temperatureOverride: Double? = nil,
        preserveProperNouns: Bool = true,
        preserveRepetition: Bool = true,
        keepSongTone: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.basePresetID = basePresetID
        self.customInstructions = customInstructions
        self.targetLanguage = targetLanguage
        self.temperatureOverride = temperatureOverride.map { min(max($0, 0), 2) }
        self.preserveProperNouns = preserveProperNouns
        self.preserveRepetition = preserveRepetition
        self.keepSongTone = keepSongTone
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }

    public func with(name: String) -> TranslationStyleProfile {
        var copy = self
        copy.name = name
        copy.updatedAt = Date()
        return copy
    }
}

public final class TranslationProfileStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "ai.translationProfiles.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func list(includeArchived: Bool = false) -> [TranslationStyleProfile] {
        guard let data = defaults.data(forKey: key),
              let profiles = try? JSONDecoder().decode([TranslationStyleProfile].self, from: data) else { return [] }
        return profiles
            .filter { includeArchived || !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    public func create(
        name: String,
        basePresetID: TranslationPromptPresetID = .naturalSong,
        customInstructions: String = "",
        targetLanguage: String = "zh-Hans",
        temperatureOverride: Double? = nil,
        preserveProperNouns: Bool = true,
        preserveRepetition: Bool = true,
        keepSongTone: Bool = true
    ) -> TranslationStyleProfile {
        let profile = TranslationStyleProfile(
            name: name,
            basePresetID: basePresetID,
            customInstructions: customInstructions,
            targetLanguage: targetLanguage,
            temperatureOverride: temperatureOverride,
            preserveProperNouns: preserveProperNouns,
            preserveRepetition: preserveRepetition,
            keepSongTone: keepSongTone
        )
        save(profile)
        return profile
    }

    public func update(_ profile: TranslationStyleProfile) {
        save(profile)
    }

    public func archive(id: UUID, archived: Bool = true) {
        guard let existing = list(includeArchived: true).first(where: { $0.id == id }) else { return }
        var updated = existing
        updated.isArchived = archived
        updated.updatedAt = Date()
        save(updated)
    }

    private func save(_ profile: TranslationStyleProfile) {
        var all = list(includeArchived: true).filter { $0.id != profile.id }
        all.append(profile)
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: key) }
    }
}

public struct TranslationModelDescriptor: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let source: String
    public let updatedAt: Date?

    public init(id: String, displayName: String? = nil, source: String = "directory", updatedAt: Date? = nil) {
        self.id = id
        self.displayName = displayName ?? id
        self.source = source
        self.updatedAt = updatedAt
    }
}

public enum TranslationModelDirectoryStatus: Equatable, Sendable {
    case idle
    case loading
    case loaded([TranslationModelDescriptor])
    case empty
    case unauthorized
    case unavailable(String)
    case manualFallback

    public var userFacingTitle: String {
        switch self {
        case .idle: return "尚未刷新"
        case .loading: return "正在刷新模型"
        case .loaded(let models): return "已加载 \(models.count) 个模型"
        case .empty: return "服务未返回模型"
        case .unauthorized: return "未授权"
        case .unavailable: return "目录暂不可用"
        case .manualFallback: return "使用手动模型"
        }
    }
}

public enum AITranslationVersionStatus: String, Codable, Sendable {
    case complete
    case incomplete
}

public struct AITranslationLine: Codable, Equatable, Sendable {
    public let index: Int
    public let translation: String

    public init(index: Int, translation: String) {
        self.index = index
        self.translation = translation
    }
}

public struct AITranslationContext: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let sourceLanguage: String
    public let targetLanguage: String
    public let style: String
    public let lines: [AITranslationSourceLine]

    public init(
        title: String,
        artist: String,
        album: String,
        sourceLanguage: String,
        targetLanguage: String,
        style: String,
        lines: [AITranslationSourceLine]
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.style = style
        self.lines = lines
    }
}

public struct AITranslationSourceLine: Equatable, Sendable {
    public let index: Int
    public let original: String
    public let kana: String?
    public let romaji: String?

    public init(index: Int, original: String, kana: String? = nil, romaji: String? = nil) {
        self.index = index
        self.original = original
        self.kana = kana
        self.romaji = romaji
    }
}

public struct AITranslationDraft: Equatable, Sendable {
    public let lines: [AITranslationLine]
    public let targetLanguage: String
    public let model: String
    public let baseURLHost: String
    public let promptHash: String
    public let sourceContentHash: String
    public let sourceKind: AITranslationSourceKind
    public let isMachineGenerated: Bool
    public let isManuallyEdited: Bool
    public let confidence: Double
    public let engineID: String
    public let promptPresetID: String
    public let profileID: UUID?
    public let profileSnapshot: String
    public let temperature: Double
    public let workflowID: String
    public let fallbackStrategy: TranslationFallbackStrategy
    public let isDraft: Bool
    public let isArchived: Bool

    public init(
        lines: [AITranslationLine],
        targetLanguage: String,
        model: String,
        baseURLHost: String,
        promptHash: String,
        sourceContentHash: String,
        sourceKind: AITranslationSourceKind = .ai,
        isMachineGenerated: Bool = true,
        isManuallyEdited: Bool = false,
        confidence: Double = 1,
        engineID: String = TranslationEngineID.openAICompatible.rawValue,
        promptPresetID: String = TranslationPromptPresetID.naturalSong.rawValue,
        profileID: UUID? = nil,
        profileSnapshot: String = "",
        temperature: Double = 0.2,
        workflowID: String = TranslationWorkflowID.contextualV2.rawValue,
        fallbackStrategy: TranslationFallbackStrategy = .none,
        isDraft: Bool = false,
        isArchived: Bool = false
    ) {
        self.lines = lines
        self.targetLanguage = targetLanguage
        self.model = model
        self.baseURLHost = baseURLHost
        self.promptHash = promptHash
        self.sourceContentHash = sourceContentHash
        self.sourceKind = sourceKind
        self.isMachineGenerated = isMachineGenerated
        self.isManuallyEdited = isManuallyEdited
        self.confidence = confidence
        self.engineID = engineID
        self.promptPresetID = promptPresetID
        self.profileID = profileID
        self.profileSnapshot = profileSnapshot
        self.temperature = temperature
        self.workflowID = workflowID
        self.fallbackStrategy = fallbackStrategy
        self.isDraft = isDraft
        self.isArchived = isArchived
    }
}

public enum AITranslationError: Error, Equatable, Sendable, LocalizedError {
    case notConfigured
    case invalidEndpoint
    case missingAPIKey
    case unauthorized
    case rateLimited
    case timedOut
    case network(String)
    case server(Int)
    case cancelled
    case invalidResponse(String)
    case persistence(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "AI 翻译尚未配置 Base URL 或模型"
        case .invalidEndpoint: return "AI Base URL 无效"
        case .missingAPIKey: return "AI API Key 未填写"
        case .unauthorized: return "AI API 未授权（401）"
        case .rateLimited: return "AI API 请求过于频繁（429）"
        case .timedOut: return "AI 翻译请求超时"
        case .network: return "AI 翻译网络不可用"
        case .server(let status): return "AI 服务错误（HTTP \(status)）"
        case .cancelled: return "AI 翻译已取消"
        case .invalidResponse: return "AI 翻译响应校验失败"
        case .persistence: return "AI 翻译保存失败"
        }
    }
}

public struct AITranslationProgress: Equatable, Sendable {
    public let requestID: String
    public let inputLineCount: Int
    public let outputLineCount: Int
    public let elapsed: TimeInterval

    public init(requestID: String, inputLineCount: Int, outputLineCount: Int = 0, elapsed: TimeInterval = 0) {
        self.requestID = requestID
        self.inputLineCount = inputLineCount
        self.outputLineCount = outputLineCount
        self.elapsed = elapsed
    }
}
