import Foundation

public enum AITranslationSourceKind: String, CaseIterable, Codable, Sendable {
    case ai
    case providerEmbedded
    case manualImport
    case manualEdit
    case legacyImported
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
        confidence: Double = 1
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
