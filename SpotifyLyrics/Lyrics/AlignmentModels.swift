import Foundation

public enum AlignmentLineStatus: String, Codable, Sendable, Equatable {
    case aligned
    case lowConfidence
    case unmatched
    case interpolated
}

public struct AlignmentParameters: Codable, Equatable, Sendable {
    public let algorithmVersion: String
    public let recognizerID: String
    public let localeIdentifier: String
    public let sampleRate: Int
    public let channels: Int
    public let maxWindowSegments: Int
    public let minimumDirectScore: Double

    public init(
        algorithmVersion: String = "line-dp-v1",
        recognizerID: String = "unknown",
        localeIdentifier: String = "ja-JP",
        sampleRate: Int = 16_000,
        channels: Int = 1,
        maxWindowSegments: Int = 8,
        minimumDirectScore: Double = 0.42
    ) {
        self.algorithmVersion = algorithmVersion
        self.recognizerID = recognizerID
        self.localeIdentifier = localeIdentifier
        self.sampleRate = sampleRate
        self.channels = channels
        self.maxWindowSegments = max(1, maxWindowSegments)
        self.minimumDirectScore = min(1, max(0, minimumDirectScore))
    }
}

public struct AlignmentLineEvidence: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case directSpeech
        case boundedInterpolation
        case noEvidence
    }

    public let kind: Kind
    public let segmentStartIndex: Int?
    public let segmentEndIndex: Int?
    public let transcriptConfidence: Double?
    public let matchScore: Double
    public let note: String

    public init(
        kind: Kind,
        segmentStartIndex: Int? = nil,
        segmentEndIndex: Int? = nil,
        transcriptConfidence: Double? = nil,
        matchScore: Double = 0,
        note: String = ""
    ) {
        self.kind = kind
        self.segmentStartIndex = segmentStartIndex
        self.segmentEndIndex = segmentEndIndex
        self.transcriptConfidence = transcriptConfidence
        self.matchScore = matchScore
        self.note = note
    }
}

public struct AlignedLyricLine: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let originalText: String
    public var kanaText: String?
    public var romajiText: String?
    public var translationText: String?
    public var rubyTokens: [LyricRubyToken]?
    public var startTime: TimeInterval
    public var endTime: TimeInterval?
    public var confidence: Double
    public var status: AlignmentLineStatus
    public var evidence: AlignmentLineEvidence

    public init(
        id: UUID = UUID(),
        originalText: String,
        kanaText: String? = nil,
        romajiText: String? = nil,
        translationText: String? = nil,
        rubyTokens: [LyricRubyToken]? = nil,
        startTime: TimeInterval,
        endTime: TimeInterval? = nil,
        confidence: Double,
        status: AlignmentLineStatus,
        evidence: AlignmentLineEvidence = AlignmentLineEvidence(kind: .noEvidence)
    ) {
        self.id = id
        self.originalText = originalText
        self.kanaText = kanaText
        self.romajiText = romajiText
        self.translationText = translationText
        self.rubyTokens = rubyTokens
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.status = status
        self.evidence = evidence
    }

    public func asLyricLine() -> LyricLine {
        LyricLine(
            id: id,
            timestamp: startTime,
            originalText: originalText,
            translationText: translationText,
            romajiText: romajiText,
            kanaText: kanaText,
            rubyTokens: rubyTokens
        )
    }
}

public struct LineAlignmentResult: Equatable, Sendable {
    public let lines: [AlignedLyricLine]
    public let skippedTranscriptSegmentIndices: [Int]
    public let unresolvedLineIndices: [Int]

    public init(
        lines: [AlignedLyricLine],
        skippedTranscriptSegmentIndices: [Int] = [],
        unresolvedLineIndices: [Int] = []
    ) {
        self.lines = lines
        self.skippedTranscriptSegmentIndices = skippedTranscriptSegmentIndices
        self.unresolvedLineIndices = unresolvedLineIndices
    }

    public var isComplete: Bool { unresolvedLineIndices.isEmpty }
}

public struct AlignmentRequest: Equatable, Sendable {
    public let identity: TrackIdentity
    public let track: Track
    public let plainLines: [LyricLine]
    public let audioURL: URL
    public let durationHint: TimeInterval?
    public let sourceVersionID: UUID?
    public let sourceContentHash: String?
    public let sourceIsSynchronized: Bool
    /// Files without embedded title/artist tags require an explicit user
    /// continuation in the App's preflight sheet.  Direct service callers
    /// default to fail-closed and must opt in deliberately.
    public let allowMissingEmbeddedMetadata: Bool

    public init(
        identity: TrackIdentity,
        track: Track,
        plainLines: [LyricLine],
        audioURL: URL,
        durationHint: TimeInterval? = nil,
        sourceVersionID: UUID? = nil,
        sourceContentHash: String? = nil,
        sourceIsSynchronized: Bool = false,
        allowMissingEmbeddedMetadata: Bool = false
    ) {
        self.identity = identity
        self.track = track
        self.plainLines = plainLines
        self.audioURL = audioURL
        self.durationHint = durationHint
        self.sourceVersionID = sourceVersionID
        self.sourceContentHash = sourceContentHash
        self.sourceIsSynchronized = sourceIsSynchronized
        self.allowMissingEmbeddedMetadata = allowMissingEmbeddedMetadata
    }
}

/// Safety gate for the local audio selected for line alignment.
///
/// The audio is never assumed to be the Spotify track merely because a user
/// selected a file. A small edit/intro/outro difference is acceptable, but a
/// materially different recording must be rejected before Speech recognition
/// can produce timestamps for the live track.
public enum AlignmentDurationValidator {
    public static let relativeTolerance: TimeInterval = 0.10
    public static let minimumAbsoluteTolerance: TimeInterval = 8.0

    public static func isCompatible(
        audioDuration: TimeInterval,
        trackDuration: TimeInterval?
    ) -> Bool {
        guard audioDuration.isFinite, audioDuration > 0 else { return false }
        guard let trackDuration,
              trackDuration.isFinite,
              trackDuration > 0 else {
            return true
        }

        let tolerance = max(
            minimumAbsoluteTolerance,
            trackDuration * relativeTolerance
        )
        return abs(audioDuration - trackDuration) <= tolerance
    }
}

public struct AlignmentReport: Equatable, Sendable {
    public let identity: TrackIdentity
    public let lines: [AlignedLyricLine]
    public let audioDuration: TimeInterval
    public let audioSHA256: String
    public let modelID: String
    public let usedVocalsStem: Bool
    public let overallConfidence: Double
    public let createdAt: Date
    public let sourceVersionID: UUID?
    public let sourceContentHash: String?
    public let parameters: AlignmentParameters
    public let sampleRate: Int
    public let channels: Int
    public let reportEvidence: [AlignmentLineEvidence]

    public init(
        identity: TrackIdentity,
        lines: [AlignedLyricLine],
        audioDuration: TimeInterval,
        audioSHA256: String,
        modelID: String,
        usedVocalsStem: Bool,
        overallConfidence: Double,
        createdAt: Date = Date(),
        sourceVersionID: UUID? = nil,
        sourceContentHash: String? = nil,
        parameters: AlignmentParameters = AlignmentParameters(),
        sampleRate: Int = 16_000,
        channels: Int = 1,
        reportEvidence: [AlignmentLineEvidence] = []
    ) {
        self.identity = identity
        self.lines = lines
        self.audioDuration = audioDuration
        self.audioSHA256 = audioSHA256
        self.modelID = modelID
        self.usedVocalsStem = usedVocalsStem
        self.overallConfidence = overallConfidence
        self.createdAt = createdAt
        self.sourceVersionID = sourceVersionID
        self.sourceContentHash = sourceContentHash
        self.parameters = parameters
        self.sampleRate = sampleRate
        self.channels = channels
        self.reportEvidence = reportEvidence
    }

    public var lowConfidenceCount: Int {
        lines.filter { $0.status == .lowConfidence || $0.status == .unmatched || $0.status == .interpolated }.count
    }

    public func makeDocument(
        base: LyricsDocument,
        source: LyricsSource = .automaticAlignment
    ) -> LyricsDocument {
        LyricsDocument(
            identity: identity,
            title: base.title,
            artist: base.artist,
            album: base.album,
            duration: audioDuration > 0 ? audioDuration : base.duration,
            lines: lines.map { $0.asLyricLine() },
            isSynchronized: true,
            source: source,
            confidence: overallConfidence,
            providerSourceID: base.providerSourceID
        )
    }
}

public enum AlignmentProgress: Equatable, Sendable {
    case preparingAudio(Double)
    case recognizing(Double)
    case aligning(Double)
    case scoring(Double)
    case finished
}

public enum AlignmentError: Error, Equatable, Sendable {
    case invalidAudio(String)
    case speechPermissionDenied
    case recognizerUnavailable
    case noSpeech
    case emptyLyrics
    case identityMismatch
    case audioDurationMismatch(expected: TimeInterval, actual: TimeInterval)
    case lockedResult
    case cancelled
    case failed(String)
    case insufficientEvidence([Int])
}

extension AlignmentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidAudio(let message): return message
        case .speechPermissionDenied: return "没有获得日语语音识别权限"
        case .recognizerUnavailable: return "日语语音识别不可用"
        case .noSpeech: return "音频中没有可识别的人声"
        case .emptyLyrics: return "没有可排轴的歌词行"
        case .identityMismatch: return "排轴结果与当前歌曲不一致"
        case .audioDurationMismatch(let expected, let actual):
            return String(
                format: "所选音频时长 %.1f 秒与当前歌曲 %.1f 秒不匹配，未生成时间轴",
                actual,
                expected
            )
        case .lockedResult: return "本地歌词已锁定，未覆盖现有结果"
        case .cancelled: return "自动排轴已取消"
        case .failed(let message): return message
        case .insufficientEvidence(let indices):
            return "识别证据不足，无法安全排轴（未解析行：\(indices.map(String.init).joined(separator: ", "))）"
        }
    }
}
